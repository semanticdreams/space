(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local {: WorkflowStore} (require :workflows/store))
(local {: WorkflowRunner} (require :workflows/runner))
(local {: WorkflowCodeExecutor} (require :workflows/code-executor))
(local {: CodeEntityStore} (require :entities/code))
(local WorkflowEvents (require :llm/agent/workflow-events))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "agent-session-migration"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "migration-" (os.time) "-" temp-counter)))

(fn make-harness []
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local workflow-store (WorkflowStore {:base-dir dir}))
  (local code-store (CodeEntityStore {:base-dir dir}))
  (local executor (WorkflowCodeExecutor {:code-store code-store :app {}}))
  (local workflow-runner (WorkflowRunner {:store workflow-store :executor executor :app {}}))
  {:dir dir
   :workflow-store workflow-store
   :code-store code-store
   :workflow-runner workflow-runner})

(fn session-dir [base-dir]
  (fs.join-path base-dir "agent-sessions"))

(fn session-path [base-dir id]
  (fs.join-path (session-dir base-dir) (.. id ".json")))

(fn write-session! [base-dir session]
  (local dir (session-dir base-dir))
  (when (not (fs.exists dir))
    (fs.create-dirs dir))
  (JsonUtils.write-json! (session-path base-dir session.id) session))

(fn migrate [h]
  (local Migration (require :llm/agent/session-migration))
  (Migration.migrate {:base-dir h.dir
                      :workflow-store h.workflow-store
                      :workflow-runner h.workflow-runner
                      :code-store h.code-store}))

(fn projected-for [h result legacy-id]
  (local run-id (assert (. result.mapping legacy-id) "migration mapping should include legacy id"))
  (WorkflowEvents.project-session (assert (h.workflow-store:get-run run-id) "workflow run should exist")))

(fn sample-session [overrides]
  (local session {:id "legacy-1"
                  :agent-id "space-agent"
                  :status :idle
                  :items [{:id "item-1" :type "message" :role "user" :content "hello" :created-at 10}
                          {:id "item-2" :type "message" :role "assistant" :content "hi" :created-at 11}]
                  :data {:opencode-session-id "opc-1"
                         :runtime-context {:agent-session-id "legacy-1"
                                           :artifact-dir "/old/artifacts/legacy-1"
                                           :report-path "/old/artifacts/legacy-1/report.md"
                                           :opencode-session-id "opc-1"
                                           :opencode-server-url "http://127.0.0.1:4444"
                                           :last-live-connection-at 123
                                           :validation-mode "live"}}
                  :created-at 9
                  :updated-at 12})
  (local changes (if (= overrides nil) {} overrides))
  (each [k v (pairs changes)]
    (tset session k v))
  session)

(fn migrates-items-to-workflow-events []
  (local h (make-harness))
  (write-session! h.dir (sample-session {}))
  (local result (migrate h))
  (local projected (projected-for h result "legacy-1"))
  (assert (= result.migrated 1) "one session should migrate")
  (assert (= (length projected.items) 2) "projection should include migrated transcript")
  (assert (= (. projected.items 1 :id) "item-1") "first item id should be preserved")
  (assert (= (. projected.items 1 :content) "hello") "first item content should be preserved")
  (assert (= (. projected.items 2 :id) "item-2") "second item id should be preserved")
  (assert (= (. projected.items 2 :content) "hi") "second item content should be preserved"))

(fn preserves-provider-continuity-fields []
  (local h (make-harness))
  (write-session! h.dir (sample-session {}))
  (local result (migrate h))
  (local projected (projected-for h result "legacy-1"))
  (assert (= projected.legacy-agent-session-id "legacy-1") "legacy id should project as migration metadata")
  (assert (= projected.agent-id "space-agent") "agent id should be preserved")
  (assert (= projected.created-at 9) "created timestamp should be preserved")
  (assert (= projected.updated-at 12) "updated timestamp should be preserved")
  (assert (= projected.data.opencode-session-id "opc-1") "top-level provider session id should be preserved")
  (assert (= projected.data.runtime-context.agent-session-id "legacy-1") "runtime agent session id should be preserved")
  (assert (= projected.data.runtime-context.artifact-dir "/old/artifacts/legacy-1") "artifact dir should be preserved")
  (assert (= projected.data.runtime-context.report-path "/old/artifacts/legacy-1/report.md") "report path should be preserved")
  (assert (= projected.data.runtime-context.opencode-session-id "opc-1") "runtime provider session id should be preserved")
  (assert (= projected.data.runtime-context.opencode-server-url "http://127.0.0.1:4444") "server url should be preserved")
  (assert (= projected.data.runtime-context.last-live-connection-at 123) "live connection timestamp should be preserved"))

(fn archives-old-files-after-successful-migration []
  (local h (make-harness))
  (write-session! h.dir (sample-session {}))
  (local old-path (session-path h.dir "legacy-1"))
  (local result (migrate h))
  (assert (= result.archived 1) "one file should archive")
  (assert (not (fs.exists old-path)) "old session file should be moved")
  (assert (fs.exists (fs.join-path result.archive-dir "legacy-1.json")) "archived file should exist"))

(fn does-not-archive-when-workflow-write-fails []
  (local h (make-harness))
  (write-session! h.dir (sample-session {}))
  (local old-append h.workflow-store.append-event)
  (tset h.workflow-store :append-event (fn [_self _run-id _event]
                                         (error "injected workflow write failure")))
  (local (ok err) (pcall migrate h))
  (tset h.workflow-store :append-event old-append)
  (assert (not ok) "migration should fail loudly when workflow write fails")
  (assert (string.find (tostring err) "injected workflow write failure" 1 true) "error should preserve write failure")
  (assert (fs.exists (session-path h.dir "legacy-1")) "old file should remain when conversion fails")
  (assert (not (fs.exists (fs.join-path h.dir "agent-sessions-archive"))) "archive dir should not be created on failed conversion"))

(fn rerun-does-not-create-duplicate-for-legacy-id []
  (local h (make-harness))
  (write-session! h.dir (sample-session {}))
  (local first (migrate h))
  (write-session! h.dir (sample-session {}))
  (local second (migrate h))
  (assert (= (. second.mapping "legacy-1") (. first.mapping "legacy-1")) "rerun should map to existing workflow run")
  (assert (= second.migrated 0) "rerun should not create a new workflow run")
  (assert (= (length (h.workflow-store:list-runs {})) 1) "rerun should not duplicate runs")
  (local projected (projected-for h second "legacy-1"))
  (assert (= (length projected.items) 2) "rerun should not duplicate transcript events"))

(fn malformed-json-fails-loudly []
  (local h (make-harness))
  (local dir (session-dir h.dir))
  (fs.create-dirs dir)
  (fs.write-file (fs.join-path dir "bad.json") "{not json")
  (local (ok err) (pcall migrate h))
  (assert (not ok) "malformed json should fail")
  (assert (string.find (tostring err) "failed to parse legacy agent session" 1 true) "error should identify malformed legacy session")
  (assert (fs.exists (fs.join-path dir "bad.json")) "malformed file should remain for operator repair"))

(fn rerun-with-changed-content-or-provider-fails-without-archive []
  (local h (make-harness))
  (write-session! h.dir (sample-session {}))
  (local first (migrate h))
  (write-session! h.dir
                  (sample-session {:items [{:id "item-1" :type "message" :role "user" :content "corrected hello" :created-at 10}
                                           {:id "item-2" :type "message" :role "assistant" :content "hi" :created-at 11}]
                                   :data {:opencode-session-id "opc-2"
                                          :runtime-context {:agent-session-id "legacy-1"
                                                            :artifact-dir "/old/artifacts/legacy-1"
                                                            :report-path "/old/artifacts/legacy-1/report.md"
                                                            :opencode-session-id "opc-2"
                                                            :opencode-server-url "http://127.0.0.1:4444"
                                                            :last-live-connection-at 456
                                                            :validation-mode "live"}}
                                   :updated-at 13}))
  (local restored-path (session-path h.dir "legacy-1"))
  (local (ok err) (pcall migrate h))
  (assert (not ok) "rerun with changed legacy content/provider data should fail")
  (assert (string.find (tostring err) "existing workflow run does not match legacy agent session" 1 true)
          "error should identify incompatible existing migration")
  (assert (fs.exists restored-path) "changed restored legacy file should not be archived")
  (assert (= (length (h.workflow-store:list-runs {})) 1) "failed rerun should not duplicate runs")
  (local projected (projected-for h first "legacy-1"))
  (assert (= (. projected.items 1 :content) "hello") "failed rerun should not mutate existing transcript")
  (assert (= projected.data.opencode-session-id "opc-1") "failed rerun should not mutate provider continuity data"))

(fn malformed-item-fails-without-archive-or-run []
  (local h (make-harness))
  (write-session! h.dir (sample-session {:items [{:id "item-1" :role "user" :content "missing type"}]}))
  (local old-path (session-path h.dir "legacy-1"))
  (local (ok err) (pcall migrate h))
  (assert (not ok) "legacy item without type should fail")
  (assert (string.find (tostring err) "requires string :type" 1 true) "error should identify malformed item type")
  (assert (fs.exists old-path) "malformed item file should remain for operator repair")
  (assert (not (fs.exists (fs.join-path h.dir "agent-sessions-archive"))) "archive dir should not be created for malformed item")
  (assert (= (length (h.workflow-store:list-runs {})) 0) "malformed item should not create a workflow run"))

(table.insert tests {:name "migrates-items-to-workflow-events" :fn migrates-items-to-workflow-events})
(table.insert tests {:name "preserves-provider-continuity-fields" :fn preserves-provider-continuity-fields})
(table.insert tests {:name "archives-old-files-after-successful-migration" :fn archives-old-files-after-successful-migration})
(table.insert tests {:name "does-not-archive-when-workflow-write-fails" :fn does-not-archive-when-workflow-write-fails})
(table.insert tests {:name "rerun-does-not-create-duplicate-for-legacy-id" :fn rerun-does-not-create-duplicate-for-legacy-id})
(table.insert tests {:name "malformed-json-fails-loudly" :fn malformed-json-fails-loudly})
(table.insert tests {:name "rerun-with-changed-content-or-provider-fails-without-archive" :fn rerun-with-changed-content-or-provider-fails-without-archive})
(table.insert tests {:name "malformed-item-fails-without-archive-or-run" :fn malformed-item-fails-without-archive-or-run})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "agent-session-migration" :tests tests}))

{:tests tests
 :main main}
