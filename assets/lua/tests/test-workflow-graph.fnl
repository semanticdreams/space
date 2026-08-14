(local fs (require :fs))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "workflow-graph"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "graph-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok result (error result)))

(fn table-or-empty [value]
  (if value value {}))

(fn make-runner [workflow-store]
  (local started [])
  (local cancelled [])
  (fn start-run [self definition-id input context]
    (table.insert self.started {:definition-id definition-id
                                :input (table-or-empty input)
                                :context (table-or-empty context)})
    (workflow-store:create-run definition-id (table-or-empty input) (table-or-empty context)))
  (fn cancel-run [self run-id reason]
    (table.insert self.cancelled {:run-id run-id :reason reason})
    (workflow-store:update-run run-id {:status :cancelled :error {:message (tostring reason)}}))
  {:started started
   :cancelled cancelled
   :start-run start-run
   :cancel-run cancel-run})

(fn make-runtime [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local Graph (require :graph/init))
  (local GraphKeyLoaders (require :graph/key-loaders))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code")}))
  (local runner (make-runner workflow-store))
  (local graph (Graph {:with-start false}))
  (GraphKeyLoaders.register graph {:code-store code-store
                                   :workflow-store workflow-store
                                   :workflow-runner runner})
  {:store workflow-store
   :code-store code-store
   :runner runner
   :graph graph})

(fn with-runtime-dir [f dir]
  (local runtime (make-runtime dir))
  (local (ok result) (pcall f runtime))
  (runtime.graph:drop)
  (if ok result (error result)))

(fn with-runtime [f]
  (with-temp-dir (fn [dir] (with-runtime-dir f dir))))

(fn edge-target-key-set [edges]
  (local keys {})
  (each [_ edge (ipairs (if edges edges []))]
    (when (and edge edge.target edge.target.key)
      (set (. keys edge.target.key) true)))
  keys)

(fn assert-edge-target [edges key message]
  (local keys (edge-target-key-set edges))
  (assert (. keys key) message))

(fn seed-definition-with-run [runtime]
  (local code-a (runtime.code-store:create-entity {:id "code-a" :name "A" :source "(+ 1 1)"}))
  (local code-b (runtime.code-store:create-entity {:id "code-b" :name "B" :source "(+ 2 2)"}))
  (local definition (runtime.store:create-definition {:id "wf-demo"
                                                     :name "Demo workflow"
                                                     :steps [{:id "step-a" :name "A" :code-entity-id code-a.id}
                                                             {:id "step-b" :name "B" :code-entity-id code-b.id}]
                                                     :edges [{:id "edge-a-b" :source-step-id "step-a" :target-step-id "step-b"}]}))
  (local run (runtime.runner:start-run definition.id {:prompt "go"} {:source :test}))
  (runtime.store:upsert-run-step run.id "step-a" {:status :succeeded :output {:answer 42}})
  (runtime.store:upsert-run-step run.id "step-b" {:status :waiting :wait {:kind :human-input}})
  (local event (runtime.store:append-event run.id {:id "event-started" :kind :step-started :step-id "step-a"}))
  {:definition definition :run (runtime.store:get-run run.id) :event event})

(fn workflow-key-loaders-resolve-all-workflow-keys-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local keys ["workflows"
               (.. "workflow-definition:" seeded.definition.id)
               (.. "workflow-step:" seeded.definition.id ":step-a")
               (.. "workflow-run:" seeded.run.id)
               (.. "workflow-run-step:" seeded.run.id ":step-a")
               (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id)])
  (each [_ key (ipairs keys)]
    (local node (graph:create-node-by-key key))
    (assert node (.. "workflow key should resolve: " key))
    (assert (= node.key key) (.. "workflow key should match: " key))))

(fn workflow-key-loaders-resolve-all-workflow-keys []
  (with-runtime workflow-key-loaders-resolve-all-workflow-keys-case))

(fn missing-key-result [graph key]
  (graph:create-node-by-key key))

(fn workflow-key-loaders-return-nil-for-missing-records-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local keys ["workflow-definition:missing"
                   "workflow-step:missing:step-a"
                   (.. "workflow-step:" seeded.definition.id ":missing-step")
                   "workflow-run:missing"
                   "workflow-run-step:missing:step-a"
                   (.. "workflow-run-step:" seeded.run.id ":missing-step")
                   "workflow-run-event:missing:event-a"
                   (.. "workflow-run-event:" seeded.run.id ":missing-event")])
  (each [_ key (ipairs keys)]
    (local (ok result) (pcall missing-key-result graph key))
    (assert ok (.. "missing workflow key should not throw: " key))
    (assert (= result nil) (.. "missing workflow key should return nil: " key))))

(fn workflow-key-loaders-return-nil-for-missing-records []
  (with-runtime workflow-key-loaders-return-nil-for-missing-records-case))

(fn workflow-definition-node-expands-to-step-code-and-run-edges-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local node (graph:load-by-key (.. "workflow-definition:" seeded.definition.id)))
  (local edges (node:get-edges))
  (assert-edge-target edges (.. "workflow-step:" seeded.definition.id ":step-a") "definition should link to first step")
  (assert-edge-target edges (.. "workflow-step:" seeded.definition.id ":step-b") "definition should link to second step")
  (assert-edge-target edges "code-entity:code-a" "definition expansion should include step code entity")
  (assert-edge-target edges "code-entity:code-b" "definition expansion should include second step code entity")
  (assert-edge-target edges (.. "workflow-run:" seeded.run.id) "definition should link to its runs")
  (local step-node (graph:load-by-key (.. "workflow-step:" seeded.definition.id ":step-a")))
  (assert-edge-target (step-node:get-edges)
                      (.. "workflow-step:" seeded.definition.id ":step-b")
                      "workflow step should project canonical workflow step edges"))

(fn workflow-definition-node-expands-to-step-code-and-run-edges []
  (with-runtime workflow-definition-node-expands-to-step-code-and-run-edges-case))

(fn workflow-run-node-expands-to-definition-run-step-and-event-edges-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local node (graph:load-by-key (.. "workflow-run:" seeded.run.id)))
  (var edges (node:get-edges))
  (assert-edge-target edges (.. "workflow-definition:" seeded.definition.id) "run should always link to definition")
  (assert (= (. (edge-target-key-set edges) (.. "workflow-run-step:" seeded.run.id ":step-a")) nil)
          "run should hide run-step edges before details expansion")
  (node:show-details)
  (set edges (node:get-edges))
  (assert-edge-target edges (.. "workflow-run-step:" seeded.run.id ":step-a") "expanded run should link run step")
  (assert-edge-target edges (.. "workflow-run-step:" seeded.run.id ":step-b") "expanded run should link second run step")
  (assert-edge-target edges (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id) "expanded run should link event")
  (node:hide-details)
  (assert (not node.details-expanded?) "hide-details should collapse details"))

(fn workflow-run-node-expands-to-definition-run-step-and-event-edges []
  (with-runtime workflow-run-node-expands-to-definition-run-step-and-event-edges-case))

(fn workflow-status-color-mapping-covers-all-statuses []
  (local WorkflowRunNode (require :graph/nodes/workflow-run))
  (local statuses [:pending :queued :ready :running :waiting :failed :succeeded :skipped :cancelled])
  (each [_ status (ipairs statuses)]
    (local color (WorkflowRunNode.status-color status))
    (assert color (.. "status color should exist for " (tostring status)))
    (assert (= (type color) :userdata) (.. "status color should be vec4 for " (tostring status)))))

(table.insert tests {:name "workflow key loaders resolve all workflow keys"
                     :fn workflow-key-loaders-resolve-all-workflow-keys})
(table.insert tests {:name "workflow key loaders return nil for missing records"
                     :fn workflow-key-loaders-return-nil-for-missing-records})
(table.insert tests {:name "workflow definition node expands to step code and run edges"
                     :fn workflow-definition-node-expands-to-step-code-and-run-edges})
(table.insert tests {:name "workflow run node expands to definition run step and event edges"
                     :fn workflow-run-node-expands-to-definition-run-step-and-event-edges})
(table.insert tests {:name "workflow status color mapping covers all statuses"
                     :fn workflow-status-color-mapping-covers-all-statuses})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "workflow-graph"
                       :tests tests})))

{:name "workflow-graph"
 :tests tests
 :main main}
