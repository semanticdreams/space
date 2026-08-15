(local fs (require :fs))
(local GraphMap (require :graph/map))
(local _main (require :main))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "workflow-graph-action-boundaries"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "graph-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir) (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir) (fs.remove-all dir))
  (if ok result (error result)))

(fn make-runner [workflow-store]
  {:start-run (fn [_self definition-id input context]
                (workflow-store:create-run definition-id
                                           (if input input {})
                                           (if context context {})))})

(fn make-runtime [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code")}))
  {:store workflow-store :code-store code-store :runner (make-runner workflow-store)})

(fn with-runtime [f]
  (with-temp-dir (fn [dir] (f (make-runtime dir)))))

(fn make-graph-with-workflow-loaders [runtime loader-names]
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (each [_ loader-name (ipairs loader-names)]
    (local module (require (.. :graph/nodes/ loader-name)))
    (module.register-loader graph {:store runtime.store :runner runtime.runner :code-store runtime.code-store}))
  graph)

(fn workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code-case [runtime]
  (local graph (make-graph-with-workflow-loaders runtime [:workflows :workflow-definition]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-workflow-missing-loader-map"}))
  (local root (map:load-by-key "workflows"))
  (local before-definitions (length (runtime.store:list-definitions)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall root.create-workflow-from-graph root {:name "Should Not Persist"}))
  (assert (not ok) "New Workflow without required graph loaders should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing loader failure should explain the missing graph loader")
  (assert (= (length (runtime.store:list-definitions)) before-definitions) "failed New Workflow should not persist a workflow definition")
  (assert (= (length (runtime.code-store:list-entities)) before-code) "failed New Workflow should not persist a code entity")
  (assert (= (map:node-count) 1) "failed New Workflow should not leave partial graph nodes")
  (assert (= (map:edge-count) 0) "failed New Workflow should not leave partial graph edges")
  (map:drop)
  (graph:drop))

(fn workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code []
  (with-runtime workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code-case))

(fn workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code-case [runtime]
  (local graph (make-graph-with-workflow-loaders runtime [:workflows :workflow-step :code-entity]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-workflow-missing-definition-loader-map"}))
  (local root (map:load-by-key "workflows"))
  (local before-definitions (length (runtime.store:list-definitions)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall root.create-workflow-from-graph root {:name "Should Not Persist"}))
  (assert (not ok) "New Workflow without workflow-definition loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader for workflow-definition" 1 true)
          "missing workflow-definition loader failure should explain the missing graph loader")
  (assert (= (length (runtime.store:list-definitions)) before-definitions)
          "failed New Workflow without workflow-definition loader should not persist a workflow definition")
  (assert (= (length (runtime.code-store:list-entities)) before-code)
          "failed New Workflow without workflow-definition loader should not persist a code entity")
  (assert (= (map:node-count) 1) "failed New Workflow without workflow-definition loader should not leave partial graph nodes")
  (assert (= (map:edge-count) 0) "failed New Workflow without workflow-definition loader should not leave partial graph edges")
  (map:drop)
  (graph:drop))

(fn workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code []
  (with-runtime workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code-case))

(fn seed-definition [runtime]
  (local code (runtime.code-store:create-entity {:id "code-a" :name "A" :source "(+ 1 1)"}))
  (runtime.store:create-definition {:id "wf-demo" :name "Demo" :steps [{:id "step-a" :name "A" :code-entity-id code.id}] :edges []}))

(fn assert-no-step-or-code-topology [map message]
  (each [key _ (pairs map.nodes)]
    (assert (not (string.find key "workflow-step:" 1 true)) (.. message " should not leave stale step graph nodes"))
    (assert (not (string.find key "code-entity:" 1 true)) (.. message " should not leave stale code graph nodes")))
  (assert (= (map:edge-count) 0) (.. message " should not leave stale graph edges")))

(fn definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-step]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-step-missing-code-loader-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local before-steps (length (. (runtime.store:get-definition definition.id) :steps)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall node.create-step-from-graph node {:step-name "Should Not Persist"}))
  (assert (not ok) "New Step without code-entity loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing code loader failure should explain the missing graph loader")
  (assert (= (length (. (runtime.store:get-definition definition.id) :steps)) before-steps) "failed New Step should not persist a workflow step")
  (assert (= (length (runtime.code-store:list-entities)) before-code) "failed New Step should not persist a code entity")
  (assert-no-step-or-code-topology map "failed New Step")
  (map:drop)
  (graph:drop))

(fn definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph []
  (with-runtime definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph-case))

(fn definition-new-step-code-load-failure-removes-stale-step-node-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-step :code-entity]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-step-code-load-failure-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local original-load-by-key map.load-by-key)
  (fn fail-code-load [self key]
    (if (= (string.sub key 1 12) "code-entity:") nil (original-load-by-key self key)))
  (set map.load-by-key fail-code-load)
  (local before-steps (length (. (runtime.store:get-definition definition.id) :steps)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall node.create-step-from-graph node {:step-name "Should Roll Back"}))
  (assert (not ok) "New Step should fail loudly when code node loading fails")
  (assert (string.find (tostring err) "failed to load graph node" 1 true) "code load failure should surface graph materialization failure")
  (assert (= (length (. (runtime.store:get-definition definition.id) :steps)) before-steps) "code load failure should roll back the workflow step")
  (assert (= (length (runtime.code-store:list-entities)) before-code) "code load failure should roll back the code entity")
  (assert-no-step-or-code-topology map "code load failure")
  (map:drop)
  (graph:drop))

(fn definition-new-step-code-load-failure-removes-stale-step-node []
  (with-runtime definition-new-step-code-load-failure-removes-stale-step-node-case))

(table.insert tests {:name "workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code" :fn workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code})
(table.insert tests {:name "workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code" :fn workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code})
(table.insert tests {:name "definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph" :fn definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph})
(table.insert tests {:name "definition-new-step-code-load-failure-removes-stale-step-node" :fn definition-new-step-code-load-failure-removes-stale-step-node})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "workflow-graph-action-boundaries" :tests tests})))

{:name "workflow-graph-action-boundaries" :tests tests :main main}
