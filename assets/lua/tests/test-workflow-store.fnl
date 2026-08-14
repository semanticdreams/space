(local fs (require :fs))
(local json (require :json))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "workflow-store"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "store-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok
      result
      (error result)))

(fn with-temp-store [f]
  (with-temp-dir
    (fn [root]
      (local {: WorkflowStore} (require :workflows/store))
      (local store (WorkflowStore {:base-dir root}))
      (f store root))))

(fn assert-file-json [path message]
  (assert (fs.exists path) message)
  (json.loads (fs.read-file path)))

(fn assert-not-path-owned-by-world-or-graph-map [path]
  (assert (not (string.find path "world-123" 1 true)) "workflow path must not contain world id")
  (assert (not (string.find path "graph-map-456" 1 true)) "workflow path must not contain graph-map id"))

(fn connect-count [store signal-name counts key]
  (local signal (. store signal-name))
  (local handler (fn [_payload]
                   (local current (if (= (. counts key) nil) 0 (. counts key)))
                   (set (. counts key) (+ current 1))))
  (signal:connect handler)
  {:signal signal :handler handler})

(fn disconnect-signal-handlers [records]
  (each [_ record (ipairs records)]
    (record.signal:disconnect record.handler true)))

(fn exercise-signal-emitting-mutations [store]
  (local definition (store:create-definition {:name "signals"
                                              :steps [{:id "step-signals"
                                                       :name "step"
                                                       :code-entity-id "code-signals"}]}))
  (store:update-definition definition.id {:description "updated"})
  (local run (store:create-run definition.id {} {}))
  (store:update-run run.id {:status :running})
  (store:upsert-run-step run.id "step-signals" {:status :running})
  (store:append-event run.id {:kind :started})
  (store:delete-definition definition.id {}))

(fn assert-signal-counts [counts]
  (assert (= counts.definition-created 1) "definition-created signal should emit once")
  (assert (= counts.definition-updated 1) "definition-updated signal should emit once")
  (assert (= counts.definition-deleted 1) "definition-deleted signal should emit once")
  (assert (= counts.run-updated 1) "run-updated signal should emit once")
  (assert (= counts.run-step-updated 1) "run-step-updated signal should emit once")
  (assert (= counts.event-appended 1) "event-appended signal should emit once"))

(fn workflow-store-persists-definitions-app-scoped []
  (with-temp-store
    (fn [store root]
      (local definition (store:create-definition {:name "App scoped workflow"
                                                  :description "durable"}))
      (assert definition.id "definition should have id")
      (assert (= (string.sub definition.id 1 3) "wf-") "definition id should use wf- prefix")
      (assert (= definition.name "App scoped workflow") "definition name should persist")
      (assert (= (length definition.steps) 0) "definition starts with no steps")
      (assert (= (length definition.edges) 0) "definition starts with no edges")
      (local definition-path (fs.join-path root "workflows" "definitions" (.. definition.id ".json")))
      (assert-not-path-owned-by-world-or-graph-map definition-path)
      (local persisted (assert-file-json definition-path "definition should persist under workflows/definitions"))
      (assert (= persisted.id definition.id) "persisted definition id should match")
      (local workflow-module (require :workflows/store))
      (local reloaded-store (workflow-module.WorkflowStore {:base-dir root}))
      (local reloaded (reloaded-store:get-definition definition.id))
      (assert (= reloaded.id definition.id) "definition should reload by id")
      (assert (= (length (reloaded-store:list-definitions)) 1) "definition list should include persisted definition")
      (local updated (store:update-definition definition.id {:status :active :parameters {:topic "demo"}}))
      (assert (= updated.status :active) "definition status should update")
      (assert (= updated.parameters.topic "demo") "definition parameters should update")
      (local deleted (store:delete-definition definition.id {}))
      (assert (= deleted.id definition.id) "delete-definition should return deleted definition")
      (assert (= (store:get-definition definition.id) nil) "deleted definition should not be returned"))))

(fn workflow-store-creates-updates-steps-and-edges []
  (with-temp-store
    (fn [store _root]
      (local definition (store:create-definition {:name "steps"}))
      (local (missing-code-ok _) (pcall store.add-step store definition.id {:name "missing code"}))
      (assert (not missing-code-ok) "steps must require :code-entity-id")
      (local first-step (store:add-step definition.id {:name "first" :code-entity-id "code-first"}))
      (local second-step (store:add-step definition.id {:name "second" :code-entity-id "code-second" :config {:limit 1}}))
      (assert (= (string.sub first-step.id 1 5) "step-") "step id should use step- prefix")
      (assert (= second-step.config.limit 1) "step config should persist")
      (local updated-step (store:update-step definition.id first-step.id {:name "renamed" :retry {:max-attempts 2}}))
      (assert (= updated-step.name "renamed") "step name should update")
      (assert (= updated-step.retry.max-attempts 2) "step retry should update")
      (local edge (store:add-edge definition.id {:source-step-id first-step.id :target-step-id second-step.id}))
      (assert (= (string.sub edge.id 1 5) "edge-") "edge id should use edge- prefix")
      (assert (= edge.kind :control) "edge kind should default to control")
      (local updated-edge (store:update-edge definition.id edge.id {:kind :data :source-port "result" :target-port "input"}))
      (assert (= updated-edge.kind :data) "edge kind should update")
      (assert (= updated-edge.source-port "result") "edge source port should update")
      (local deleted-edge (store:delete-edge definition.id edge.id))
      (assert (= deleted-edge.id edge.id) "delete-edge should return deleted edge")
      (local definition-after-delete (store:get-definition definition.id))
      (assert (= (length definition-after-delete.edges) 0) "edge should be removed from definition"))))

(fn workflow-store-delete-step-requires-dependent-edge-decision []
  (with-temp-store
    (fn [store _root]
      (local definition (store:create-definition {:name "delete"}))
      (local first-step (store:add-step definition.id {:name "first" :code-entity-id "code-first"}))
      (local second-step (store:add-step definition.id {:name "second" :code-entity-id "code-second"}))
      (local edge (store:add-edge definition.id {:source-step-id first-step.id :target-step-id second-step.id}))
      (local run (store:create-run definition.id {} {}))
      (store:upsert-run-step run.id first-step.id {:status :succeeded :output {:value 1}})
      (local (ok _) (pcall store.delete-step store definition.id first-step.id {}))
      (assert (not ok) "delete-step should require explicit dependent edge decision")
      (local deleted-step (store:delete-step definition.id first-step.id {:delete-dependent-edges? true}))
      (assert (= deleted-step.id first-step.id) "delete-step should return deleted step")
      (local updated-definition (store:get-definition definition.id))
      (assert (= (length updated-definition.edges) 0) "dependent definition edges should be removed")
      (local historical-run-step (store:get-run-step run.id first-step.id))
      (assert (= historical-run-step.output.value 1) "existing run history should remain intact"))))

(fn workflow-store-persists-runs-steps-events-and-waits []
  (with-temp-store
    (fn [store root]
      (local definition (store:create-definition {:name "runs"}))
      (local step (store:add-step definition.id {:name "wait" :code-entity-id "code-wait"}))
      (local run (store:create-run definition.id {:prompt "go"} {:world-id "world-123" :graph-map-id "graph-map-456"}))
      (assert (= (string.sub run.id 1 4) "wfr-") "run id should use wfr- prefix")
      (assert (= run.context.world-id "world-123") "run context may record world id")
      (local run-path (fs.join-path root "workflows" "runs" (.. run.id ".json")))
      (assert-not-path-owned-by-world-or-graph-map run-path)
      (local run-step (store:upsert-run-step run.id step.id {:status :waiting
                                                             :attempt 1
                                                             :wait {:kind :human-input :request {:prompt "continue?"}}
                                                             :state {:token "abc"}}))
      (assert (= run-step.status :waiting) "run-step status should persist")
      (assert (= run-step.wait.kind :human-input) "run-step wait should persist")
      (local event (store:append-event run.id {:kind :step-waiting :step-id step.id :data {:reason "human"}}))
      (assert (= (string.sub event.id 1 6) "event-") "event id should use event- prefix")
      (local persisted-run (assert-file-json run-path "run should persist under workflows/runs"))
      (assert (= persisted-run.id run.id) "persisted run id should match")
      (assert persisted-run.steps "run JSON should contain nested steps")
      (assert persisted-run.events "run JSON should contain nested events")
      (local workflow-module (require :workflows/store))
      (local reloaded-store (workflow-module.WorkflowStore {:base-dir root}))
      (local reloaded-run (reloaded-store:get-run run.id))
      (local reloaded-run-step (reloaded-store:get-run-step run.id step.id))
      (assert (= reloaded-run.input.prompt "go") "run should reload by id")
      (assert (= reloaded-run-step.wait.request.prompt "continue?") "run-step wait should reload")
      (assert (= (length (reloaded-store:list-run-steps run.id)) 1) "run-step list should reload")
      (assert (= (length (reloaded-store:list-events run.id)) 1) "event list should reload")
      (assert (= (length (reloaded-store:list-runs {:definition-id definition.id})) 1) "run list should filter by definition id")
      (local updated-run (store:update-run run.id {:status :waiting :current-step-ids [step.id]}))
      (assert (= updated-run.status :waiting) "run status should update"))))

(fn workflow-store-signals-fire []
  (with-temp-store
    (fn [store _root]
      (local counts {})
      (local records [(connect-count store :definition-created counts :definition-created)
                      (connect-count store :definition-updated counts :definition-updated)
                      (connect-count store :definition-deleted counts :definition-deleted)
                      (connect-count store :run-updated counts :run-updated)
                      (connect-count store :run-step-updated counts :run-step-updated)
                      (connect-count store :event-appended counts :event-appended)])
      (exercise-signal-emitting-mutations store)
      (disconnect-signal-handlers records)
      (assert-signal-counts counts))))

(table.insert tests {:name "workflow-store-persists-definitions-app-scoped"
                     :fn workflow-store-persists-definitions-app-scoped})
(table.insert tests {:name "workflow-store-creates-updates-steps-and-edges"
                     :fn workflow-store-creates-updates-steps-and-edges})
(table.insert tests {:name "workflow-store-delete-step-requires-dependent-edge-decision"
                     :fn workflow-store-delete-step-requires-dependent-edge-decision})
(table.insert tests {:name "workflow-store-persists-runs-steps-events-and-waits"
                     :fn workflow-store-persists-runs-steps-events-and-waits})
(table.insert tests {:name "workflow-store-signals-fire"
                     :fn workflow-store-signals-fire})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "workflow-store"
                       :tests tests})))

{:name "workflow-store"
 :tests tests
 :main main}
