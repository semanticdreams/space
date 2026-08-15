(local fs (require :fs))
(local {: WorkflowStore} (require :workflows/store))
(local WorkflowEvents (require :llm/agent/workflow-events))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "agent-workflow-events"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "store-" (os.time) "-" temp-counter)))

(fn prepare-temp-dir []
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn remove-temp-dir [dir]
  (when (fs.exists dir)
    (fs.remove-all dir)))

(fn make-temp-store []
  (local root (prepare-temp-dir))
  (local store (WorkflowStore {:base-dir root}))
  (local definition (store:create-definition {:id "wf-agent-test" :name "Agent test workflow"}))
  (local run (store:create-run definition.id {} {:agent-id "agent-alpha"
                                                 :data {:topic "initial"}
                                                 :legacy-session-id "legacy-1"}))
  {:root root :store store :run run})

(fn with-temp-store [f]
  (local record (make-temp-store))
  (local (ok result) (pcall f record.store record.run))
  (remove-temp-dir record.root)
  (if ok
      result
      (error result)))

(fn get-projected-session [store run-id]
  (WorkflowEvents.project-session (store:get-run run-id)))

(fn assert-pcall-error-containing [ok err expected]
  (assert (not ok) "expected function to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error containing " expected ", got " (tostring err))))

(fn assert-session-created-projection [store run]
  (WorkflowEvents.append-session-created store run.id {:agent-id "agent-beta"
                                                       :data {:topic "created"}
                                                       :created-at "2026-08-15T00:00:00Z"})
  (local session (get-projected-session store run.id))
  (assert (= session.id run.id) "session id should be the workflow run id")
  (assert (= session.workflow-run-id run.id) "workflow run id should be exposed")
  (assert (= session.agent-id "agent-beta") "session-created event should set agent id")
  (assert (= session.data.topic "created") "session-created event data should be projected")
  (assert (= session.legacy-session-id "legacy-1") "legacy metadata should come from run context")
  (assert (= (length session.items) 0) "session starts without transcript items")
  (assert (= session.created-at "2026-08-15T00:00:00Z") "created-at should come from session-created event")
  (assert (= session.updated-at "2026-08-15T00:00:00Z") "updated-at should come from latest relevant event")
  (local summary (WorkflowEvents.session-summary session))
  (assert (= summary.id run.id) "summary id should match session")
  (assert (= summary.agent-id "agent-beta") "summary agent id should match session")
  (assert (= summary.item-count 0) "summary should count projected items"))

(fn projects-session-created-event-to-sidebar-session-shape []
  (with-temp-store assert-session-created-projection))

(fn assert-appended-message-items-in-order [store run]
  (WorkflowEvents.append-item store run.id {:id "item-user" :type :message :role :user :content "hello"})
  (WorkflowEvents.append-item store run.id {:id "item-assistant" :type :message :role :assistant :content "hi"})
  (local session (get-projected-session store run.id))
  (assert (= (length session.items) 2) "two appended items should project")
  (local first-item (. session.items 1))
  (local second-item (. session.items 2))
  (assert (= first-item.id "item-user") "first item should stay first")
  (assert (= second-item.id "item-assistant") "second item should stay second"))

(fn projects-appended-message-items-in-order []
  (with-temp-store assert-appended-message-items-in-order))

(fn assert-status-changes-use-latest-status [store run]
  (WorkflowEvents.append-status store run.id :running {:created-at "2026-08-15T00:00:01Z"})
  (WorkflowEvents.append-status store run.id :idle {:created-at "2026-08-15T00:00:02Z"})
  (local session (get-projected-session store run.id))
  (assert (= session.status :idle) "latest status event should win")
  (assert (= session.updated-at "2026-08-15T00:00:02Z") "latest status timestamp should be updated-at"))

(fn projects-status-changes-with-latest-status []
  (with-temp-store assert-status-changes-use-latest-status))

(fn assert-upsert-replaces-stream-item [store run]
  (WorkflowEvents.append-item store run.id {:id "stream-1" :type :message :role :assistant :content "hel"})
  (WorkflowEvents.append-upsert store run.id {:id "stream-1" :type :message :role :assistant :content "hello"})
  (local session (get-projected-session store run.id))
  (assert (= (length session.items) 1) "upsert should replace existing item")
  (local item (. session.items 1))
  (assert (= item.id "stream-1") "upsert should preserve stable item id")
  (assert (= item.content "hello") "upsert should replace item fields"))

(fn upserts-existing-stream-item-with-stable-id []
  (with-temp-store assert-upsert-replaces-stream-item))

(fn assert-update-merges-existing-item-fields [store run]
  (WorkflowEvents.append-item store run.id {:id "tool-1" :type :tool-call :status :running :content "call"})
  (WorkflowEvents.append-update store run.id "tool-1" {:status :done :result "ok"})
  (local session (get-projected-session store run.id))
  (assert (= (length session.items) 1) "update should not append a new item")
  (local item (. session.items 1))
  (assert (= item.id "tool-1") "update should preserve item id")
  (assert (= item.status :done) "update should change requested field")
  (assert (= item.result "ok") "update should add requested field")
  (assert (= item.content "call") "update should preserve other fields"))

(fn updates-existing-item-fields []
  (with-temp-store assert-update-merges-existing-item-fields))

(fn assert-duplicate-append-is-rejected [store run]
  (WorkflowEvents.append-item store run.id {:id "dup" :type :message :content "one"})
  (local (ok err) (pcall WorkflowEvents.append-item store run.id {:id "dup" :type :message :content "two"}))
  (assert-pcall-error-containing ok err "duplicate agent item id"))

(fn rejects-duplicate-append-item-id []
  (with-temp-store assert-duplicate-append-is-rejected))

(fn assert-missing-update-is-rejected [store run]
  (local (ok err) (pcall WorkflowEvents.append-update store run.id "missing" {:status :done}))
  (assert-pcall-error-containing ok err "missing agent item id"))

(fn rejects-update-for-missing-item-id []
  (with-temp-store assert-missing-update-is-rejected))

(table.insert tests {:name "projects-session-created-event-to-sidebar-session-shape"
                     :fn projects-session-created-event-to-sidebar-session-shape})
(table.insert tests {:name "projects-appended-message-items-in-order"
                     :fn projects-appended-message-items-in-order})
(table.insert tests {:name "projects-status-changes-with-latest-status"
                     :fn projects-status-changes-with-latest-status})
(table.insert tests {:name "upserts-existing-stream-item-with-stable-id"
                     :fn upserts-existing-stream-item-with-stable-id})
(table.insert tests {:name "updates-existing-item-fields"
                     :fn updates-existing-item-fields})
(table.insert tests {:name "rejects-duplicate-append-item-id"
                     :fn rejects-duplicate-append-item-id})
(table.insert tests {:name "rejects-update-for-missing-item-id"
                     :fn rejects-update-for-missing-item-id})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "agent-workflow-events"
                       :tests tests})))

{:name "agent-workflow-events"
 :tests tests
 :main main}
