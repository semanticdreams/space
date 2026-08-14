(local fs (require :fs))
(local GraphMap (require :graph/map))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Templates (require :workflows/templates))

(local _main (require :main))

(local BuildContext (require :build-context))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))

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

(fn action-named? [actions name]
  (var found false)
  (each [_ action (ipairs (if actions actions []))]
    (when (= action.name name)
      (set found true)))
  found)

(fn action-named [actions name]
  (var found nil)
  (each [_ action (ipairs (if actions actions []))]
    (when (= action.name name)
      (set found action)))
  found)

(fn assert-edge-target [edges key message]
  (local keys (edge-target-key-set edges))
  (assert (. keys key) message))

(fn make-preview-ctx []
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local intersectables (Intersectables))
  (local clickables (assert (Clickables {:intersectables intersectables})
                            "workflow graph preview test requires clickables"))
  (local hoverables (assert (Hoverables {:intersectables intersectables})
                            "workflow graph preview test requires hoverables"))
  (BuildContext {:clickables clickables
                 :hoverables hoverables}))

(fn assert-missing-build-context [builder message]
  (local (ok _result) (pcall builder))
  (assert (not ok) message))

(fn assert-missing-build-context-with-fallbacks [Preview node message]
  (local fallback-ctx (make-preview-ctx))
  (local previous-graph-ctx (and node node.graph node.graph.ctx))
  (when (and node node.graph)
    (set node.graph.ctx fallback-ctx))
  (local builder (Preview node {:node node :ctx fallback-ctx}))
  (local (ok result) (pcall builder))
  (when (and node node.graph)
    (set node.graph.ctx previous-graph-ctx))
  (assert (not ok) message)
  (assert (string.find (tostring result) "requires a build context")
          "missing build context failure should mention build context"))

(fn target-node-by-key [targets key]
  (var found nil)
  (each [_ target (ipairs (assert targets "target-node-by-key requires targets"))]
    (local node (. target 1))
    (when (and node (= node.key key))
      (set found node)))
  found)

(fn with-app-workflow-runtime [runtime f]
  (local previous-workflow-store (and app app.workflow-store))
  (local previous-workflow-runner (and app app.workflow-runner))
  (local previous-code-store (and app app.code-store))
  (set app.workflow-store runtime.store)
  (set app.workflow-runner runtime.runner)
  (set app.code-store runtime.code-store)
  (local (ok result) (pcall f))
  (set app.workflow-store previous-workflow-store)
  (set app.workflow-runner previous-workflow-runner)
  (set app.code-store previous-code-store)
  (if ok result (error result)))

(fn start-node-includes-workflows-when-workflow-store-exists-case [runtime]
  (with-app-workflow-runtime runtime
    (fn []
      (local StartNode (require :graph/nodes/start))
      (local node (StartNode))
      (local targets (node:collect-targets))
      (local workflows-node (target-node-by-key targets "workflows"))
      (assert workflows-node "Start node should include Workflows target when workflow store exists")
      (assert (= workflows-node.label "Workflows") "Workflows target should use Workflows label"))))

(fn start-node-includes-workflows-when-workflow-store-exists []
  (with-runtime start-node-includes-workflows-when-workflow-store-exists-case))

(fn workflows-root-new-workflow-creates-and-loads-graph-nodes-case [runtime]
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "new-workflow-map"}))
  (local root (map:load-by-key "workflows"))
  (assert root "workflows root should load through key loader")
  (local action (action-named root.actions "New Workflow"))
  (assert action "workflows root should expose New Workflow action")
  (local result (root:create-workflow-from-graph {:name "Graph Created Workflow"}))
  (assert result.definition "New Workflow should create a workflow definition")
  (assert result.step "New Workflow should create a starter step")
  (assert result.code-entity "New Workflow should create a code entity")
  (assert (runtime.store:get-definition result.definition.id) "created workflow definition should be durable")
  (assert (runtime.code-store:get-entity result.code-entity.id) "created step code should be durable")
  (local definition-key (.. "workflow-definition:" result.definition.id))
  (local step-key (.. "workflow-step:" result.definition.id ":" result.step.id))
  (local code-key (.. "code-entity:" result.code-entity.id))
  (assert (map:lookup definition-key) "New Workflow should load definition node into graph map")
  (assert (map:lookup step-key) "New Workflow should load starter step node into graph map")
  (assert (map:lookup code-key) "New Workflow should load code entity node into graph map")
  (assert-edge-target map.edges definition-key "New Workflow should add definition edge")
  (assert-edge-target map.edges step-key "New Workflow should add starter step edge")
  (assert-edge-target map.edges code-key "New Workflow should add code edge")
  (map:drop))

(fn workflows-root-new-workflow-creates-and-loads-graph-nodes []
  (with-runtime workflows-root-new-workflow-creates-and-loads-graph-nodes-case))

(fn workflows-preview-builds-with-new-workflow-action-case [runtime]
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "workflow-preview-map"}))
  (local node (map:load-by-key "workflows"))
  (local (loaded? Preview) (pcall require :graph/view/previews/workflows))
  (assert loaded? "workflows preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "workflows preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview node {:node node}))
  (assert-missing-build-context builder "workflows preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget "workflows preview should build a widget")
  (assert widget.new-workflow-button "workflows preview should expose a New Workflow button")
  (local before (length (runtime.store:list-definitions)))
  (widget.new-workflow-button:on-click {:source :test})
  (assert (= (length (runtime.store:list-definitions)) (+ before 1))
          "New Workflow preview button should create a definition")
  (widget:drop)
  (map:drop))

(fn workflows-preview-builds-with-new-workflow-action []
  (with-runtime workflows-preview-builds-with-new-workflow-action-case))

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

(fn workflow-definition-preview-builds-with-start-action-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local node (graph:load-by-key (.. "workflow-definition:" seeded.definition.id)))
  (local (loaded? Preview) (pcall require :graph/view/previews/workflow-definition))
  (assert loaded? "workflow definition preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "definition preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview node {:node node}))
  (assert-missing-build-context builder "definition preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget "definition preview should build a widget")
  (assert widget.start-button "definition preview should expose a Start button")
  (local before (length runtime.runner.started))
  (widget.start-button:on-click {:source :test})
  (assert (= (length runtime.runner.started) (+ before 1))
          "Start button should call start-workflow-from-graph")
  (widget:drop))

(fn workflow-definition-preview-builds-with-start-action []
  (with-runtime workflow-definition-preview-builds-with-start-action-case))

(fn workflow-run-preview-builds-with-toggle-action-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local node (graph:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local (loaded? Preview) (pcall require :graph/view/previews/workflow-run))
  (assert loaded? "workflow run preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "run preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview node {:node node}))
  (assert-missing-build-context builder "run preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget.toggle-button "run preview should expose a details toggle button")
  (assert (= widget.toggle-button-label "Show Details") "collapsed run preview should show Show Details")
  (widget.toggle-button:on-click {:source :test})
  (assert node.details-expanded? "toggle button should expand run details")
  (assert (= widget.toggle-button-label "Hide Details")
          "same run preview widget should update to Hide Details after expanding")
  (widget:drop)
  (local expanded-widget (builder (make-preview-ctx)))
  (assert (= expanded-widget.toggle-button-label "Hide Details") "expanded run preview should show Hide Details")
  (expanded-widget:drop))

(fn workflow-run-preview-builds-with-toggle-action []
  (with-runtime workflow-run-preview-builds-with-toggle-action-case))

(fn workflow-run-details-toggle-changes-expanded-edge-projection-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local node (graph:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local collapsed-keys (edge-target-key-set (node:get-edges)))
  (assert (= (. collapsed-keys (.. "workflow-run-step:" seeded.run.id ":step-a")) nil)
          "run details should default collapsed")
  (node:toggle-details)
  (local expanded-keys (edge-target-key-set (node:get-edges)))
  (assert (. expanded-keys (.. "workflow-run-step:" seeded.run.id ":step-a"))
          "expanded run should include run-step edges")
  (assert (. expanded-keys (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id))
          "expanded run should include run event edges")
  (node:toggle-details)
  (local recollapsed-keys (edge-target-key-set (node:get-edges)))
  (assert (= (. recollapsed-keys (.. "workflow-run-step:" seeded.run.id ":step-a")) nil)
          "collapsed run should hide run-step edges again"))

(fn workflow-run-details-toggle-changes-expanded-edge-projection []
  (with-runtime workflow-run-details-toggle-changes-expanded-edge-projection-case))

(fn workflow-run-node-omits-cancel-action-for-succeeded-run-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (runtime.store:update-run seeded.run.id {:status :succeeded :finished-at (os.time)})
  (local node (runtime.graph:load-by-key (.. "workflow-run:" seeded.run.id)))
  (assert node "workflow run node should load")
  (assert (action-named? (node:actions) "Show Details") "terminal run should still expose detail toggle")
  (assert (not (action-named? (node:actions) "Cancel Run")) "terminal run should omit cancel action"))

(fn workflow-run-node-omits-cancel-action-for-succeeded-run []
  (with-runtime workflow-run-node-omits-cancel-action-for-succeeded-run-case))

(fn workflow-run-step-status-colors-cover-all-run-step-statuses []
  (local WorkflowRunStepNode (require :graph/nodes/workflow-run-step))
  (local statuses [:pending :queued :ready :running :waiting :failed :succeeded :skipped :cancelled])
  (each [_ status (ipairs statuses)]
    (local color (WorkflowRunStepNode.status-color status))
    (assert color (.. "run step status color should exist for " (tostring status)))
    (assert (= (type color) :userdata) (.. "run step status color should be vec4 for " (tostring status)))))

(fn seed-definition-for-authoring [runtime]
  (local code-a (runtime.code-store:create-entity {:id "code-a" :name "A" :source "(+ 1 1)"}))
  (local code-b (runtime.code-store:create-entity {:id "code-b" :name "B" :source "(+ 2 2)"}))
  (runtime.store:create-definition {:id "wf-author"
                                    :name "Author workflow"
                                    :steps [{:id "step-a" :name "A" :code-entity-id code-a.id}
                                            {:id "step-b" :name "B" :code-entity-id code-b.id}]
                                    :edges []}))

(fn workflow-edge-count [runtime definition-id]
  (local definition (runtime.store:get-definition definition-id))
  (local edges (if (and definition definition.edges) definition.edges []))
  (length edges))

(fn graph-step-connection-creates-canonical-workflow-control-edge-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "author-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (local edge (map:add-edge (GraphEdge {:source step-a :target step-b})))
  (local current (runtime.store:get-definition definition.id))
  (assert (= (length current.edges) 1) "graph step connection should create one canonical workflow edge")
  (local workflow-edge (. current.edges 1))
  (assert (= workflow-edge.kind :control) "authored workflow edge should default to control")
  (assert (= workflow-edge.source-step-id "step-a") "authored workflow edge should use source step")
  (assert (= workflow-edge.target-step-id "step-b") "authored workflow edge should use target step")
  (assert (and edge edge._opts edge._opts.from-workflow-edge) "display edge should reference canonical workflow edge")
  (map:drop))

(fn graph-step-connection-creates-canonical-workflow-control-edge []
  (with-runtime graph-step-connection-creates-canonical-workflow-control-edge-case))

(fn graph-map-capture-skips-workflow-derived-edges-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "capture-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (map:add-edge (GraphEdge {:source step-a :target step-b}))
  (local state (map:capture-state))
  (assert (= (length state.edges) 0) "workflow-derived graph edges should not be captured as map topology")
  (map:drop))

(fn graph-map-capture-skips-workflow-derived-edges []
  (with-runtime graph-map-capture-skips-workflow-derived-edges-case))

(fn graph-remove-edge-deletes-canonical-workflow-edge-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "remove-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (local edge (map:add-edge (GraphEdge {:source step-a :target step-b})))
  (assert (= (workflow-edge-count runtime definition.id) 1) "workflow edge should exist before graph removal")
  (local removed (map:remove-edge edge))
  (assert removed "GraphMap.remove-edge should return removed edge")
  (assert (= (map:edge-count) 0) "displayed workflow edge should be removed from graph map")
  (assert (= (workflow-edge-count runtime definition.id) 0) "removing displayed workflow edge should delete canonical edge")
  (map:drop))

(fn graph-remove-edge-deletes-canonical-workflow-edge []
  (with-runtime graph-remove-edge-deletes-canonical-workflow-edge-case))

(fn graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "remove-derived-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (local edge (map:add-edge (GraphEdge {:source step-a :target step-b})))
  (local workflow-edge-id edge._opts.from-workflow-edge)
  (local derived-key (.. step-a.key "->" step-b.key "#link:" workflow-edge-id))
  (assert (. map.edge-map derived-key) "workflow-derived edge should be indexed by derived workflow key before removal")
  (local removed (map:remove-edge edge {:cause "user"}))
  (assert (= removed edge) "GraphMap.remove-edge should return the displayed workflow edge")
  (assert (= (workflow-edge-count runtime definition.id) 0)
          "removing with caller opts should delete canonical workflow edge using edge identity metadata")
  (assert (= (. map.edge-map derived-key) nil)
          "removing with caller opts should clear the derived workflow edge-map entry")
  (assert (= (map:edge-count) 0) "removing with caller opts should remove displayed workflow edge")
  (map:drop))

(fn graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes []
  (with-runtime graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes-case))

(fn trigger-definition-node-creates-visible-run-node-and-definition-run-edge-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "trigger-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local run (node:start-workflow-from-graph {:prompt "go"} {}))
  (assert run "starting workflow from graph should return run")
  (assert (runtime.store:get-run run.id) "run should be durable immediately")
  (assert (map:lookup (.. "workflow-run:" run.id)) "run node should be visible in active graph map")
  (assert-edge-target map.edges (.. "workflow-run:" run.id) "definition-to-run edge should be inserted in graph map")
  (map:drop))

(fn trigger-definition-node-creates-visible-run-node-and-definition-run-edge []
  (with-runtime trigger-definition-node-creates-visible-run-node-and-definition-run-edge-case))

(fn trigger-context-captures-graph-map-and-selected-node-keys-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "context-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (map:load-by-key (.. "workflow-step:" definition.id ":step-a"))
  (set map.selected_node_keys [node.key (.. "workflow-step:" definition.id ":step-a")])
  (node:start-workflow-from-graph {:prompt "go"} {})
  (local started (. runtime.runner.started 1))
  (assert (= started.context.graph-map-id "context-map") "run context should include active graph map id")
  (assert (= (. started.context.graph-node-keys 1) node.key) "run context should include first selected node key")
  (assert (= (. started.context.graph-node-keys 2) (.. "workflow-step:" definition.id ":step-a"))
          "run context should include selected workflow step key")
  (map:drop))

(fn trigger-context-captures-graph-map-and-selected-node-keys []
  (with-runtime trigger-context-captures-graph-map-and-selected-node-keys-case))

(fn workflow-step-source [value]
  (.. "{:run (fn [_self _context _input _state] {:status :succeeded :output {:value " value "}})}"))

(fn graph-code-entity-edits-feed-cached-workflow-executor-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local {:WorkflowCodeExecutor WorkflowCodeExecutor} (require :workflows/code-executor))
  (local {:WorkflowRunner WorkflowRunner} (require :workflows/runner))
  (local CodeEntityStore (require :entities/code))
  (local Graph (require :graph/init))
  (local GraphKeyLoaders (require :graph/key-loaders))
  (local previous-code-store (and app app.code-store))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-shared-code")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-shared")}))
  (set app.code-store code-store)
  (local executor (WorkflowCodeExecutor {:code-store app.code-store :app app}))
  (local runner (WorkflowRunner {:store workflow-store :executor executor :app app}))
  (local graph (Graph {:with-start false}))
  (GraphKeyLoaders.register graph {:workflow-store workflow-store :workflow-runner runner})
  (local code (code-store:create-entity {:id "step-code" :name "Step" :source (workflow-step-source 1)}))
  (local definition (workflow-store:create-definition {:id "wf-shared-code"
                                                       :name "Shared code"
                                                       :steps [{:id "step" :code-entity-id code.id}]
                                                       :edges []}))
  (local first-run (runner:start-run definition.id {} {}))
  (runner:tick-run first-run.id {})
  (assert (= (. (workflow-store:get-run first-run.id) :output :step :value) 1)
          "first workflow run should use initial source")
  (local code-node (graph:create-node-by-key "code-entity:step-code"))
  (assert code-node "graph should resolve the app-scoped code entity")
  (code-node:update-source (workflow-step-source 2))
  (local second-run (runner:start-run definition.id {} {}))
  (runner:tick-run second-run.id {})
  (assert (= (. (workflow-store:get-run second-run.id) :output :step :value) 2)
          "workflow execution should observe graph-authored code edits after executor cached the entity")
  (graph:drop)
  (set app.code-store previous-code-store))

(fn graph-code-entity-edits-feed-cached-workflow-executor []
  (with-temp-dir graph-code-entity-edits-feed-cached-workflow-executor-case))

(fn template-helper-creates-durable-workflow-step-and-code-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local {:WorkflowCodeExecutor WorkflowCodeExecutor} (require :workflows/code-executor))
  (local {:WorkflowRunner WorkflowRunner} (require :workflows/runner))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-template")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-template")}))
  (local result (Templates.create-template-workflow workflow-store code-store {:name "Created from graph"}))
  (assert result.definition "template helper should return a workflow definition")
  (assert result.step "template helper should return a workflow step")
  (assert result.code-entity "template helper should return a code entity")
  (assert (workflow-store:get-definition result.definition.id) "created workflow definition should be durable")
  (local reloaded-definition (workflow-store:get-definition result.definition.id))
  (assert (= (length reloaded-definition.steps) 1) "created workflow should have one starter step")
  (local reloaded-step (. reloaded-definition.steps 1))
  (assert (= reloaded-step.code-entity-id result.code-entity.id)
          "starter step should reference the created code entity")
  (assert (= reloaded-step.source nil) "starter step should not embed source")
  (local reloaded-code (code-store:get-entity result.code-entity.id))
  (assert reloaded-code "created code entity should be durable")
  (assert (= reloaded-code.language "fnl") "template code entity should be Fennel")
  (assert (string.find reloaded-code.source "workflow step completed")
          "template source should include completion message")
  (local executor (WorkflowCodeExecutor {:code-store code-store :app app}))
  (local runner (WorkflowRunner {:store workflow-store :executor executor :app app}))
  (local run (runner:start-run result.definition.id {:echo "input"} {:source :test}))
  (local finished (runner:tick-run run.id {:max-steps 5}))
  (assert (= finished.status :succeeded) "template workflow should run successfully")
  (local output (. finished.output result.step.id))
  (assert output "template run should include starter step output")
  (assert (= output.message "workflow step completed") "template output should include completion message")
  (assert (= output.input.echo "input") "template output should echo workflow input"))

(fn template-helper-creates-durable-workflow-step-and-code []
  (with-temp-dir template-helper-creates-durable-workflow-step-and-code-case))

(fn template-helper-keeps-code-entity-when-add-step-fails-after-commit-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-template-post-commit-fail")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-template-post-commit-fail")}))
  (local definition (workflow-store:create-definition {:name "Post commit failure" :steps [] :edges []}))
  (local failing-handler
    (workflow-store.definition-updated:connect
      (fn [_definition]
        (error "simulated definition-updated failure"))))
  (local (ok err) (pcall Templates.create-template-step workflow-store code-store definition.id {:name "After commit"}))
  (workflow-store.definition-updated:disconnect failing-handler true)
  (assert (not ok) "simulated post-commit add-step failure should be surfaced")
  (assert (string.find (tostring err) "simulated definition-updated failure" 1 true)
          "create-template-step should rethrow the add-step failure")
  (local reloaded-definition (workflow-store:get-definition definition.id))
  (assert (= (length reloaded-definition.steps) 1)
          "test setup should leave the add-step mutation committed before the signal failure")
  (local committed-step (. reloaded-definition.steps 1))
  (assert committed-step.code-entity-id "committed step should reference template code")
  (assert (code-store:get-entity committed-step.code-entity-id)
          "committed workflow step must not point at a deleted template code entity"))

(fn template-helper-keeps-code-entity-when-add-step-fails-after-commit []
  (with-temp-dir template-helper-keeps-code-entity-when-add-step-fails-after-commit-case))

(fn template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-template-workflow-rollback")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-template-workflow-rollback")}))
  (local failing-handler
    (workflow-store.definition-updated:connect
      (fn [_definition]
        (error "simulated definition-updated failure"))))
  (local (ok err) (pcall Templates.create-template-workflow workflow-store code-store {:name "Rollback workflow"}))
  (workflow-store.definition-updated:disconnect failing-handler true)
  (assert (not ok) "simulated post-commit starter-step failure should be surfaced")
  (assert (string.find (tostring err) "simulated definition-updated failure" 1 true)
          "create-template-workflow should rethrow the starter-step failure")
  (assert (= (length (workflow-store:list-definitions)) 0)
          "failed template workflow creation should delete the new definition")
  (assert (= (length (code-store:list-entities)) 0)
          "failed template workflow creation should delete the starter step code entity"))

(fn template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit []
  (with-temp-dir template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit-case))

(table.insert tests {:name "workflow key loaders resolve all workflow keys"
                     :fn workflow-key-loaders-resolve-all-workflow-keys})
(table.insert tests {:name "workflow key loaders return nil for missing records"
                      :fn workflow-key-loaders-return-nil-for-missing-records})
(table.insert tests {:name "start-node-includes-workflows-when-workflow-store-exists"
                     :fn start-node-includes-workflows-when-workflow-store-exists})
(table.insert tests {:name "workflows-root-new-workflow-creates-and-loads-graph-nodes"
                     :fn workflows-root-new-workflow-creates-and-loads-graph-nodes})
(table.insert tests {:name "workflows-preview-builds-with-new-workflow-action"
                     :fn workflows-preview-builds-with-new-workflow-action})
(table.insert tests {:name "workflow definition node expands to step code and run edges"
                      :fn workflow-definition-node-expands-to-step-code-and-run-edges})
(table.insert tests {:name "workflow run node expands to definition run step and event edges"
                     :fn workflow-run-node-expands-to-definition-run-step-and-event-edges})
(table.insert tests {:name "workflow status color mapping covers all statuses"
                       :fn workflow-status-color-mapping-covers-all-statuses})
(table.insert tests {:name "workflow definition preview builds with start action"
                     :fn workflow-definition-preview-builds-with-start-action})
(table.insert tests {:name "workflow run preview builds with toggle action"
                     :fn workflow-run-preview-builds-with-toggle-action})
(table.insert tests {:name "workflow run details toggle changes expanded edge projection"
                      :fn workflow-run-details-toggle-changes-expanded-edge-projection})
(table.insert tests {:name "workflow run node omits cancel action for succeeded run"
                      :fn workflow-run-node-omits-cancel-action-for-succeeded-run})
(table.insert tests {:name "workflow run step status colors cover all run step statuses"
                      :fn workflow-run-step-status-colors-cover-all-run-step-statuses})
(table.insert tests {:name "graph step connection creates canonical workflow control edge"
                     :fn graph-step-connection-creates-canonical-workflow-control-edge})
(table.insert tests {:name "graph map capture skips workflow derived edges"
                     :fn graph-map-capture-skips-workflow-derived-edges})
(table.insert tests {:name "graph remove edge deletes canonical workflow edge"
                      :fn graph-remove-edge-deletes-canonical-workflow-edge})
(table.insert tests {:name "graph remove derived workflow edge with caller opts clears domain and indexes"
                     :fn graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes})
(table.insert tests {:name "trigger definition node creates visible run node and definition run edge"
                      :fn trigger-definition-node-creates-visible-run-node-and-definition-run-edge})
(table.insert tests {:name "trigger context captures graph map and selected node keys"
                      :fn trigger-context-captures-graph-map-and-selected-node-keys})
(table.insert tests {:name "graph code entity edits feed cached workflow executor"
                     :fn graph-code-entity-edits-feed-cached-workflow-executor})
(table.insert tests {:name "template-helper-creates-durable-workflow-step-and-code"
                      :fn template-helper-creates-durable-workflow-step-and-code})
(table.insert tests {:name "template-helper-keeps-code-entity-when-add-step-fails-after-commit"
                      :fn template-helper-keeps-code-entity-when-add-step-fails-after-commit})
(table.insert tests {:name "template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit"
                     :fn template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "workflow-graph"
                       :tests tests})))

{:name "workflow-graph"
 :tests tests
 :main main}
