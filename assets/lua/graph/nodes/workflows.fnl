(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local WorkflowTemplates (require :workflows/templates))
(local WorkflowsNodePreview (require :graph/view/previews/workflows))

(local WORKFLOW_PURPLE (glm.vec4 0.45 0.25 0.75 1))
(local WORKFLOW_PURPLE_ACCENT (glm.vec4 0.58 0.38 0.88 1))

(fn resolve-node [graph key]
  (var node nil)
  (when (and graph key graph.lookup)
    (set node (graph:lookup key)))
  (when (and (= node nil) graph key graph.create-node-by-key)
    (set node (graph:create-node-by-key key)))
  (when (and (= node nil) graph key graph.load-by-key)
    (set node (graph:load-by-key key)))
  node)

(fn add-edge-to-key [edges source graph key label]
  (local target (resolve-node graph key))
  (when target
    (table.insert edges (GraphEdge {:source source :target target :label label}))))

(fn load-required-node [graph key]
  (assert graph "WorkflowsNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowsNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowsNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowsNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowsNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label})))

(fn list-required-definitions [store]
  (assert store "WorkflowsNode.load-existing-workflows requires workflow store")
  (assert store.list-definitions "WorkflowsNode.load-existing-workflows requires workflow-store:list-definitions")
  (store:list-definitions))

(fn list-required-runs [store]
  (assert store "WorkflowsNode.load-existing-workflows requires workflow store")
  (assert store.list-runs "WorkflowsNode.load-existing-workflows requires workflow-store:list-runs")
  (store:list-runs {}))

(fn load-workflow-record-node [graph key]
  (assert graph "WorkflowsNode.load-existing-workflows requires a graph map")
  (assert graph.load-by-key "WorkflowsNode.load-existing-workflows requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowsNode.load-existing-workflows failed to load graph node: " key))
  node)

(fn WorkflowsNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowsNode requires store"))
  (local node (GraphNode {:key "workflows"
                          :label "Workflows"
                          :color WORKFLOW_PURPLE
                          :sub-color WORKFLOW_PURPLE_ACCENT
                          :preview WorkflowsNodePreview
                          :size 9.0}))
  (set node.workflow-store store)
  (set node.runner options.runner)
  (set node.code-store options.code-store)
  (set node.create-workflow-from-graph
       (fn [self opts]
         (assert self.workflow-store "WorkflowsNode.create-workflow-from-graph requires workflow store")
         (assert self.runner "WorkflowsNode.create-workflow-from-graph requires workflow runner")
         (assert self.code-store "WorkflowsNode.create-workflow-from-graph requires code store")
         (local result (WorkflowTemplates.create-template-workflow self.workflow-store self.code-store (or opts {})))
         (local definition-key (.. "workflow-definition:" result.definition.id))
         (local step-key (.. "workflow-step:" result.definition.id ":" result.step.id))
         (local code-key (.. "code-entity:" result.code-entity.id))
         (local definition-node (load-required-node self.graph definition-key))
         (local step-node (load-required-node self.graph step-key))
         (local code-node (load-required-node self.graph code-key))
         (add-visible-edge self.graph self definition-node "definition")
         (add-visible-edge self.graph definition-node step-node "step")
          (add-visible-edge self.graph step-node code-node "code")
          result))
  (set node.load-existing-workflows
       (fn [self]
         (local definitions (list-required-definitions self.workflow-store))
         (local runs (list-required-runs self.workflow-store))
         (local loaded-definitions [])
         (local loaded-runs [])
         (each [_ definition (ipairs definitions)]
           (local definition-node
             (load-workflow-record-node self.graph (.. "workflow-definition:" definition.id)))
           (add-visible-edge self.graph self definition-node "definition")
           (table.insert loaded-definitions definition-node))
         (each [_ run (ipairs runs)]
           (local run-node
             (load-workflow-record-node self.graph (.. "workflow-run:" run.id)))
           (add-visible-edge self.graph self run-node "run")
           (table.insert loaded-runs run-node))
         {:definition-count (length loaded-definitions)
          :run-count (length loaded-runs)
          :definitions loaded-definitions
          :runs loaded-runs}))
  (set node.actions [{:name "New Workflow"
                       :icon "add"
                       :fn (fn [_button _event]
                             (node:create-workflow-from-graph {}))}
                      {:name "Show Existing Workflows"
                       :icon "account_tree"
                       :fn (fn [_button _event]
                             (node:load-existing-workflows))}])
  (set node.get-edges
       (fn [self]
         (local edges [])
         (each [_ definition (ipairs (self.workflow-store:list-definitions))]
           (add-edge-to-key edges self self.graph (.. "workflow-definition:" definition.id) "definition"))
         (each [_ run (ipairs (self.workflow-store:list-runs {}))]
           (add-edge-to-key edges self self.graph (.. "workflow-run:" run.id) "run"))
         edges))
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflows.register-loader requires store"))
  (graph:register-key-loader "workflows"
    (fn [key]
      (when (= key "workflows")
        (WorkflowsNode {:store store
                        :runner options.runner
                        :code-store options.code-store})))))

{:WorkflowsNode WorkflowsNode
 :register-loader register-loader}
