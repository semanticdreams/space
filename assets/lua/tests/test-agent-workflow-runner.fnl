(local fs (require :fs))
(local {: WorkflowStore} (require :workflows/store))
(local {: WorkflowRunner} (require :workflows/runner))
(local {: WorkflowCodeExecutor} (require :workflows/code-executor))
(local {: CodeEntityStore} (require :entities/code))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "agent-workflow-runner"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "runner-" (os.time) "-" temp-counter)))

(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn make-registry [agents]
  {:get (fn [_self id]
          (. agents id))})

(fn required-deps []
  {:app {}
   :presets {}
   :tools {}
   :approvals {}
   :agents {}
   :providers {}})

(fn merge-deps [overrides]
  (local deps (required-deps))
  (each [k v (pairs (table-or-empty overrides))]
    (tset deps k v))
  deps)

(fn make-harness [opts]
  (local options (table-or-empty opts))
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local workflow-store (WorkflowStore {:base-dir dir}))
  (local code-store (CodeEntityStore {:base-dir dir}))
  (local executor (WorkflowCodeExecutor {:code-store code-store :app {}}))
  (local workflow-runner (WorkflowRunner {:store workflow-store :executor executor :app {}}))
  (local agents (if options.agents options.agents {}))
  (local {: WorkflowAgentRunner} (require :llm/agent/workflow-runner))
  {:dir dir
   :workflow-store workflow-store
   :code-store code-store
   :workflow-runner workflow-runner
   :runner (WorkflowAgentRunner {:workflow-store workflow-store
                                 :workflow-runner workflow-runner
                                 :code-store code-store
                                 :registry (make-registry agents)
                                  :artifact-root (fs.join-path dir "agent-artifacts")
                                  :deps (merge-deps options.deps)})})

(fn find-item [items item-id]
  (var found nil)
  (each [_ item (ipairs items)]
    (when (= item.id item-id)
      (set found item)))
  found)

(fn idle-agent []
  {:id "space-agent"
   :name "Space Agent"
   :run (fn [_agent _input _session ctx]
          (ctx.turn:finish {:ok true}))})

(fn async-agent [record]
  {:id "space-agent"
   :name "Space Agent"
   :run (fn [_agent _input _session ctx]
          (set record.turn ctx.turn)
          (ctx.turn:set-cancel (fn [] (set record.cancelled true))))})

(fn create-session-creates-workflow-run-and-projects-session []
  (local h (make-harness {:agents {"space-agent" (idle-agent)}}))
  (local session (h.runner:create-session "space-agent"))
  (assert session.id "projected session should have workflow run id")
  (assert (= session.workflow-run-id session.id) "session id should be workflow run id")
  (assert (= session.agent-id "space-agent") "projection should preserve agent id")
  (assert (= session.status :idle) "new session should project idle status")
  (assert (= (length session.items) 0) "new session should have no transcript items")
  (local run (assert (h.workflow-store:get-run session.id) "workflow run should be durable"))
  (assert (= run.context.agent-session? true) "run context should mark agent sessions")
  (assert (= (. run.steps "step-agent-chat" :status) :waiting) "agent workflow should be waiting for user input"))

(fn list-sessions-sorts-projected-workflow-sessions-by-updated-at []
  (local h (make-harness {:agents {"space-agent" (idle-agent)}}))
  (local older (h.runner:create-session "space-agent"))
  (local newer (h.runner:create-session "space-agent"))
  (local Events (require :llm/agent/workflow-events))
  (Events.append-status h.workflow-store older.id :idle {:created-at 10})
  (Events.append-status h.workflow-store newer.id :idle {:created-at 20})
  (local sessions (h.runner:list-sessions))
  (assert (= (. sessions 1 :id) newer.id) "newer session should sort first")
  (assert (= (. sessions 2 :id) older.id) "older session should sort second"))

(fn run-turn-appends-user-message-and-returns-turn-handle []
  (local h (make-harness {:agents {"space-agent" (idle-agent)}}))
  (local session (h.runner:create-session "space-agent"))
  (local handle (h.runner:run-turn session.id "hello" {}))
  (assert handle "run-turn should return handle")
  (local projected (h.runner:get-session session.id))
  (assert (= (. projected.items 1 :role) :user) "first item should be user message")
  (assert (= (. projected.items 1 :content) "hello") "user message should preserve input"))

(fn streaming-callbacks-persist-item-events []
  (local record {})
  (local h (make-harness {:agents {"space-agent" (async-agent record)}}))
  (local seen [])
  (local session (h.runner:create-session "space-agent"))
  (h.runner:run-turn session.id "stream" {:on-item (fn [item] (table.insert seen item))})
  (record.turn:append-item {:id "assistant-1" :type :message :role :assistant :content "hel" :created-at 30})
  (record.turn:update-item "assistant-1" {:content "hello" :updated-at 31})
  (record.turn:upsert-item {:id "assistant-2" :type :message :role :assistant :content "there" :created-at 32})
  (local projected (h.runner:get-session session.id))
  (assert (= (length seen) 2) "append and inserted upsert should call on-item")
  (assert (= (. (find-item projected.items "assistant-1") :content) "hello") "item update should persist")
  (assert (= (. (find-item projected.items "assistant-2") :content) "there") "upsert should persist"))

(fn completion-sets-session-idle-and-preserves-items []
  (local record {})
  (local h (make-harness {:agents {"space-agent" (async-agent record)}}))
  (local completed [])
  (local session (h.runner:create-session "space-agent"))
  (h.runner:run-turn session.id "complete" {:on-complete (fn [info] (table.insert completed info))})
  (record.turn:append-item {:id "assistant-1" :type :message :role :assistant :content "done" :created-at 40})
  (record.turn:finish {:ok true})
  (local projected (h.runner:get-session session.id))
  (assert (= projected.status :idle) "completion should return session to idle")
  (assert (= (. (find-item projected.items "assistant-1") :content) "done") "completion should preserve items")
  (assert (= (length completed) 1) "completion callback should fire"))

(fn error-adds-error-item-and-sets-session-idle []
  (local record {})
  (local h (make-harness {:agents {"space-agent" (async-agent record)}}))
  (local errors [])
  (local session (h.runner:create-session "space-agent"))
  (h.runner:run-turn session.id "fail" {:on-error (fn [info] (table.insert errors info))})
  (record.turn:fail "boom")
  (local projected (h.runner:get-session session.id))
  (assert (= projected.status :idle) "error should return session to idle")
  (assert (= (. projected.items (length projected.items) :type) :error) "error should append error item")
  (assert (= (. projected.items (length projected.items) :error) "boom") "error item should preserve message")
  (assert (= (length errors) 1) "error callback should fire"))

(fn resume-step-failure-adds-error-item-and-sets-session-idle []
  (local h (make-harness {:agents {"space-agent" (idle-agent)}}))
  (local errors [])
  (fn record-error [info]
    (table.insert errors info))
  (local session (h.runner:create-session "space-agent"))
  (h.workflow-store:upsert-run-step session.id "step-agent-chat" {:status :succeeded})
  (local handle (h.runner:run-turn session.id "not waiting" {:on-error record-error}))
  (local projected (h.runner:get-session session.id))
  (assert (= (handle:status) :failed) "resume failure should fail the turn handle")
  (assert (= projected.status :idle) "resume failure should return session to idle")
  (assert (= (. projected.items (length projected.items) :type) :error) "resume failure should append compatible error item")
  (assert (string.find (. projected.items (length projected.items) :error) "workflow run step is not waiting" 1 true)
          "error item should preserve resume-step failure message")
  (assert (= (length errors) 1) "error callback should fire once"))

(fn cancel-turn-cancels-active-turn-and-allows-next-input []
  (local record {})
  (local h (make-harness {:agents {"space-agent" (async-agent record)}}))
  (local session (h.runner:create-session "space-agent"))
  (local first (h.runner:run-turn session.id "first" {}))
  (assert (= (first:status) :running) "first handle should be running")
  (h.runner:cancel-turn session.id)
  (assert (= record.cancelled true) "cancel hook should run")
  (local second (h.runner:run-turn session.id "second" {}))
  (assert (= (second:status) :running) "second turn should be accepted after cancel")
  (local projected (h.runner:get-session session.id))
  (assert (= (. projected.items 1 :content) "first") "first input should persist")
  (assert (= (. projected.items (length projected.items) :content) "second") "second input should persist"))

(fn new-turn-cancels-existing-active-turn-for-same-session []
  (local record {})
  (local h (make-harness {:agents {"space-agent" (async-agent record)}}))
  (local session (h.runner:create-session "space-agent"))
  (local first (h.runner:run-turn session.id "first" {}))
  (h.runner:run-turn session.id "second" {})
  (assert (= (first:status) :cancelled) "starting next turn should cancel active turn")
  (assert (= record.cancelled true) "previous cancel hook should run"))

(fn runtime-context-preserves-provider-continuity-fields []
  (local h (make-harness {:agents {"space-agent" (idle-agent)}
                          :deps {:runtime-context {:opencode-session-id "opc-1"
                                                    :mcp-endpoint "ipc:///tmp/mcp.sock"
                                                    :opencode-server-url "http://127.0.0.1:1234"
                                                    :last-live-connection-at 123
                                                    :validation-mode "live"}}}))
  (local session (h.runner:create-session "space-agent"))
  (local runtime (assert session.data.runtime-context "session should project runtime context"))
  (assert (= runtime.agent-session-id session.id) "runtime should include agent-session-id")
  (assert runtime.artifact-dir "runtime should include artifact-dir")
  (assert runtime.report-path "runtime should include report-path")
  (assert (= runtime.opencode-session-id "opc-1") "runtime should preserve opencode-session-id")
  (assert (= runtime.mcp-endpoint "ipc:///tmp/mcp.sock") "runtime should preserve mcp-endpoint")
  (assert (= runtime.opencode-server-url "http://127.0.0.1:1234") "runtime should preserve opencode-server-url")
  (assert (= runtime.last-live-connection-at 123) "runtime should preserve last-live-connection-at")
  (assert (= runtime.validation-mode "live") "runtime should preserve validation-mode"))

(fn turn-persist-preserves-provider-continuity-mutations []
  (local observations [])
  (local mutating-agent
    {:id "space-agent"
     :name "Space Agent"
     :run (fn [_agent input session ctx]
            (if (= input "first")
                (do
                  (tset session.data :opencode-session-id "opc-from-turn")
                  (when (not session.data.runtime-context)
                    (tset session.data :runtime-context {}))
                  (tset session.data.runtime-context :opencode-session-id "opc-from-turn")
                  (tset session.data.runtime-context :last-live-connection-at 456)
                  (ctx.turn:finish {:ok true}))
                (do
                  (table.insert observations {:opencode-session-id session.data.opencode-session-id
                                              :runtime-opencode-session-id session.data.runtime-context.opencode-session-id
                                              :last-live-connection-at session.data.runtime-context.last-live-connection-at})
                  (ctx.turn:finish {:ok true}))))})
  (local h (make-harness {:agents {"space-agent" mutating-agent}}))
  (local session (h.runner:create-session "space-agent"))
  (h.runner:run-turn session.id "first" {})
  (local after-first (h.runner:get-session session.id))
  (assert (= after-first.data.opencode-session-id "opc-from-turn")
          "projection should preserve provider session id mutated during turn")
  (assert (= after-first.data.runtime-context.opencode-session-id "opc-from-turn")
          "projection should preserve runtime provider id mutated during turn")
  (h.runner:run-turn session.id "second" {})
  (assert (= (. observations 1 :opencode-session-id) "opc-from-turn")
          "second turn should observe persisted provider session id")
  (assert (= (. observations 1 :runtime-opencode-session-id) "opc-from-turn")
          "second turn should observe persisted runtime provider id")
  (assert (= (. observations 1 :last-live-connection-at) 456)
          "second turn should observe persisted runtime context updates"))

(fn constructor-requires-runtime-dependencies []
  (local h (make-harness {:agents {"space-agent" (idle-agent)}}))
  (local {: WorkflowAgentRunner} (require :llm/agent/workflow-runner))
  (fn build-with-deps [deps]
    (WorkflowAgentRunner {:workflow-store h.workflow-store
                          :workflow-runner h.workflow-runner
                          :code-store h.code-store
                          :registry (make-registry {"space-agent" (idle-agent)})
                          :artifact-root (fs.join-path h.dir "assertion-artifacts")
                          :deps deps}))
  (each [_ assertion-case (ipairs [{:deps nil :message "WorkflowAgentRunner requires :deps"}
                                   {:deps {:presets {} :tools {} :approvals {} :agents {} :providers {}}
                                    :message "WorkflowAgentRunner requires deps.app"}
                                   {:deps {:app {} :tools {} :approvals {} :agents {} :providers {}}
                                    :message "WorkflowAgentRunner requires deps.presets"}
                                   {:deps {:app {} :presets {} :approvals {} :agents {} :providers {}}
                                    :message "WorkflowAgentRunner requires deps.tools"}
                                   {:deps {:app {} :presets {} :tools {} :agents {} :providers {}}
                                    :message "WorkflowAgentRunner requires deps.approvals"}
                                   {:deps {:app {} :presets {} :tools {} :approvals {} :providers {}}
                                    :message "WorkflowAgentRunner requires deps.agents"}
                                   {:deps {:app {} :presets {} :tools {} :approvals {} :agents {}}
                                    :message "WorkflowAgentRunner requires deps.providers"}])]
    (local (ok err) (pcall build-with-deps assertion-case.deps))
    (assert (not ok) (.. "constructor should reject missing dependency: " assertion-case.message))
    (assert (string.find (tostring err) assertion-case.message 1 true)
            (.. "constructor error should mention missing dependency: " assertion-case.message)))
  (assert (build-with-deps (required-deps)) "constructor should accept explicit runtime deps"))

(table.insert tests {:name "create-session-creates-workflow-run-and-projects-session" :fn create-session-creates-workflow-run-and-projects-session})
(table.insert tests {:name "list-sessions-sorts-projected-workflow-sessions-by-updated-at" :fn list-sessions-sorts-projected-workflow-sessions-by-updated-at})
(table.insert tests {:name "run-turn-appends-user-message-and-returns-turn-handle" :fn run-turn-appends-user-message-and-returns-turn-handle})
(table.insert tests {:name "streaming-callbacks-persist-item-events" :fn streaming-callbacks-persist-item-events})
(table.insert tests {:name "completion-sets-session-idle-and-preserves-items" :fn completion-sets-session-idle-and-preserves-items})
(table.insert tests {:name "error-adds-error-item-and-sets-session-idle" :fn error-adds-error-item-and-sets-session-idle})
(table.insert tests {:name "resume-step-failure-adds-error-item-and-sets-session-idle" :fn resume-step-failure-adds-error-item-and-sets-session-idle})
(table.insert tests {:name "cancel-turn-cancels-active-turn-and-allows-next-input" :fn cancel-turn-cancels-active-turn-and-allows-next-input})
(table.insert tests {:name "new-turn-cancels-existing-active-turn-for-same-session" :fn new-turn-cancels-existing-active-turn-for-same-session})
(table.insert tests {:name "runtime-context-preserves-provider-continuity-fields" :fn runtime-context-preserves-provider-continuity-fields})
(table.insert tests {:name "turn-persist-preserves-provider-continuity-mutations" :fn turn-persist-preserves-provider-continuity-mutations})
(table.insert tests {:name "constructor-requires-runtime-dependencies" :fn constructor-requires-runtime-dependencies})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "agent-workflow-runner" :tests tests}))

{:tests tests
 :main main}
