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
                                  :deps (if options.deps options.deps {})})})

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

(table.insert tests {:name "create-session-creates-workflow-run-and-projects-session" :fn create-session-creates-workflow-run-and-projects-session})
(table.insert tests {:name "list-sessions-sorts-projected-workflow-sessions-by-updated-at" :fn list-sessions-sorts-projected-workflow-sessions-by-updated-at})
(table.insert tests {:name "run-turn-appends-user-message-and-returns-turn-handle" :fn run-turn-appends-user-message-and-returns-turn-handle})
(table.insert tests {:name "streaming-callbacks-persist-item-events" :fn streaming-callbacks-persist-item-events})
(table.insert tests {:name "completion-sets-session-idle-and-preserves-items" :fn completion-sets-session-idle-and-preserves-items})
(table.insert tests {:name "error-adds-error-item-and-sets-session-idle" :fn error-adds-error-item-and-sets-session-idle})
(table.insert tests {:name "cancel-turn-cancels-active-turn-and-allows-next-input" :fn cancel-turn-cancels-active-turn-and-allows-next-input})
(table.insert tests {:name "new-turn-cancels-existing-active-turn-for-same-session" :fn new-turn-cancels-existing-active-turn-for-same-session})
(table.insert tests {:name "runtime-context-preserves-provider-continuity-fields" :fn runtime-context-preserves-provider-continuity-fields})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "agent-workflow-runner" :tests tests}))

{:tests tests
 :main main}
