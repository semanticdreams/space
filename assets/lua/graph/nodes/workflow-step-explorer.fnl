(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local GraphMapContext (require :graph/map-context))
(local WorkflowStepExplorerPreview (require :graph/view/previews/workflow-step-explorer))

(local EXPLORER_ORANGE (glm.vec4 0.82 0.46 0.18 1))
(local EXPLORER_ORANGE_ACCENT (glm.vec4 0.95 0.58 0.28 1))

(fn step-key [definition-id step-id]
  (.. "workflow-step:" definition-id ":" step-id))

(fn explorer-key [definition-id]
  (.. "workflow-step-explorer:" definition-id))

(fn find-step [definition step-id]
  (var found nil)
  (when (and definition definition.steps)
    (each [_ step (ipairs definition.steps)]
      (when (= step.id step-id)
        (set found step))))
  found)

(fn definition-label [definition definition-id]
  (if (and definition (> (string.len (if definition.name definition.name "")) 0))
      definition.name
      definition-id))

(fn step-label [step]
  (local name (if step.name step.name step.id))
  (if (= name step.id)
      (tostring name)
      (.. name " (" step.id ")")))

(fn load-required-node [graph key]
  (assert graph "WorkflowStepExplorerNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowStepExplorerNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowStepExplorerNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label edge-opts]
  (assert graph "WorkflowStepExplorerNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowStepExplorerNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label}) edge-opts))

(fn loader-graph [graph]
  (if (and graph graph.graph graph.graph.has-key-loader-for-key)
      graph.graph
      (if (and graph graph.has-key-loader-for-key)
          graph
          nil)))

(fn assert-graph-loader [graph key action label]
  (local provider (loader-graph graph))
  (assert (and provider (provider:has-key-loader-for-key key))
          (.. action " requires graph loader for " label)))

(fn assert-step-graph-dependencies [self action]
  (GraphMapContext.assert-graph-map self.graph action)
  (assert self.graph.load-by-key (.. action " requires graph:load-by-key"))
  (assert self.graph.add-edge (.. action " requires graph:add-edge")))

(fn current-definition [self action]
  (assert self.workflow-store (.. action " requires workflow store"))
  (assert self.workflow-store.get-definition (.. action " requires workflow store:get-definition"))
  (local definition (self.workflow-store:get-definition self.workflow-definition-id))
  (assert definition (.. action " missing workflow definition: " (tostring self.workflow-definition-id)))
  definition)

(fn step-id [step-or-id action]
  (if (= (type step-or-id) :table)
      (assert step-or-id.id (.. action " requires step id"))
      (assert step-or-id (.. action " requires step id"))))

(fn load-owned-step-record [self step-or-id action]
  (local id (step-id step-or-id action))
  (local definition (current-definition self action))
  (local step (find-step definition id))
  (assert step (.. action " step " (tostring id)
                " does not belong to workflow definition " (tostring self.workflow-definition-id)))
  step)

(fn load-step-node [self step]
  (local step-node (load-required-node self.graph (step-key self.workflow-definition-id step.id)))
  (add-visible-edge self.graph self step-node "step")
  step-node)

(fn reveal-workflow-step-edge [self loaded-steps workflow-edge]
  (local source-node (. loaded-steps workflow-edge.source-step-id))
  (local target-node (. loaded-steps workflow-edge.target-step-id))
  (when (and source-node target-node)
    (local workflow-edge-id (assert workflow-edge.id "WorkflowStepExplorerNode.reveal-all-steps-from-graph requires workflow edge id"))
    (add-visible-edge self.graph
                      source-node
                      target-node
                      (tostring (if workflow-edge.kind workflow-edge.kind "workflow"))
                      {:from-workflow-edge workflow-edge-id})))

(fn reveal-all [self action]
  (assert-step-graph-dependencies self action)
  (assert-graph-loader self.graph
                       (step-key self.workflow-definition-id "__preflight__")
                       action
                       "workflow-step")
  (local definition (current-definition self action))
  (local loaded-steps {})
  (local steps (assert definition.steps (.. action " requires definition.steps")))
  (local edges (assert definition.edges (.. action " requires definition.edges")))
  (each [_ step (ipairs steps)]
    (set (. loaded-steps step.id) (load-step-node self step)))
  (each [_ workflow-edge (ipairs edges)]
    (reveal-workflow-step-edge self loaded-steps workflow-edge))
  {:step-count (length steps)
   :edge-count (length edges)
   :steps loaded-steps})

(fn WorkflowStepExplorerNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowStepExplorerNode requires store"))
  (local definition-id (assert options.definition-id "WorkflowStepExplorerNode requires definition-id"))
  (local definition (store:get-definition definition-id))
  (local node (GraphNode {:key (explorer-key definition-id)
                          :label (.. "Step explorer " (definition-label definition definition-id))
                          :color EXPLORER_ORANGE
                          :sub-color EXPLORER_ORANGE_ACCENT
                          :preview WorkflowStepExplorerPreview
                          :size 8.0}))
  (set node.workflow-definition-id definition-id)
  (set node.workflow-store store)
  (set node.step-items
       (fn [self]
         (local current (current-definition self "WorkflowStepExplorerNode.step-items"))
         (local steps (assert current.steps "WorkflowStepExplorerNode.step-items requires definition.steps"))
         (icollect [_ step (ipairs steps)]
           [step (step-label step)])))
  (set node.load-step-from-graph
       (fn [self step-or-id]
         (assert-step-graph-dependencies self "WorkflowStepExplorerNode.load-step-from-graph")
         (local step (load-owned-step-record self step-or-id "WorkflowStepExplorerNode.load-step-from-graph"))
         (load-step-node self step)))
  (set node.reveal-all-steps-from-graph
       (fn [self]
         (reveal-all self "WorkflowStepExplorerNode.reveal-all-steps-from-graph")))
  (set node.actions [{:name "Reveal Steps"
                      :icon "account_tree"
                      :fn (fn [_button _event]
                            (node:reveal-all-steps-from-graph))}])
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-step-explorer.register-loader requires store"))
  (graph:register-key-loader "workflow-step-explorer"
    (fn [key]
      (local prefix "workflow-step-explorer:")
      (when (= (string.sub key 1 (string.len prefix)) prefix)
        (local definition-id (string.sub key (+ 1 (string.len prefix))))
        (when (and (> (string.len definition-id) 0)
                   (store:get-definition definition-id))
          (WorkflowStepExplorerNode {:definition-id definition-id
                                     :store store}))))))

{:WorkflowStepExplorerNode WorkflowStepExplorerNode
 :register-loader register-loader}
