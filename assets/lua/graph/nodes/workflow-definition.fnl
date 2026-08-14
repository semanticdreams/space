(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local WorkflowDefinitionNodePreview (require :graph/view/previews/workflow-definition))

(local DEFINITION_BLUE (glm.vec4 0.22 0.4 0.82 1))
(local DEFINITION_BLUE_ACCENT (glm.vec4 0.32 0.52 0.95 1))

(fn find-step [definition step-id]
  (var found nil)
  (when (and definition definition.steps)
    (each [_ step (ipairs definition.steps)]
      (when (= step.id step-id)
        (set found step))))
  found)

(fn resolve-node [graph key]
  (var node nil)
  (when (and graph key graph.lookup)
    (set node (graph:lookup key)))
  (when (and (= node nil) graph key graph.create-node-by-key)
    (set node (graph:create-node-by-key key)))
  (when (and (= node nil) graph key graph.load-by-key)
    (set node (graph:load-by-key key)))
  node)

(fn add-edge [edges source target label opts]
  (when (and source target)
    (local edge (GraphEdge {:source source :target target :label label}))
    (when opts
      (set edge._opts opts))
    (table.insert edges edge)))

(fn copy-array [items]
  (local source (if (= items nil) [] items))
  (local out [])
  (each [_ item (ipairs source)]
    (table.insert out item))
  out)

(fn graph-context [graph context-opts]
  (local context (if (= context-opts nil) {} context-opts))
  (local out {})
  (each [k v (pairs context)]
    (set (. out k) v))
  (when (and graph graph.id)
    (set out.graph-map-id graph.id))
  (when (and graph graph.selected_node_keys)
    (set out.graph-node-keys (copy-array graph.selected_node_keys)))
  out)

(fn edge-label [edge]
  (if edge.kind edge.kind "workflow"))

(fn step-key [definition-id step-id]
  (.. "workflow-step:" definition-id ":" step-id))

(fn cached-or-resolved-step-node [step-nodes graph definition-id step-id]
  (local cached (. step-nodes step-id))
  (if cached
      cached
      (resolve-node graph (step-key definition-id step-id))))

(fn definition-label [definition definition-id]
  (if (and definition (> (string.len (if definition.name definition.name "")) 0))
      definition.name
      definition-id))

(fn WorkflowDefinitionNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowDefinitionNode requires store"))
  (local runner (assert options.runner "WorkflowDefinitionNode requires runner"))
  (local definition-id (assert options.definition-id "WorkflowDefinitionNode requires definition-id"))
  (local definition (store:get-definition definition-id))
  (local label (definition-label definition definition-id))
  (local node (GraphNode {:key (.. "workflow-definition:" definition-id)
                          :label label
                          :color DEFINITION_BLUE
                          :sub-color DEFINITION_BLUE_ACCENT
                          :preview WorkflowDefinitionNodePreview
                          :size 8.5}))
  (set node.workflow-definition-id definition-id)
  (set node.workflow-store store)
  (set node.workflow-runner runner)
  (set node.start-workflow-from-graph
       (fn [self input context-opts]
         (local run-input (if (= input nil) {} input))
         (local run (self.workflow-runner:start-run self.workflow-definition-id
                                                    run-input
                                                    (graph-context self.graph context-opts)))
         (local run-node (and self.graph self.graph.load-by-key
                              (self.graph:load-by-key (.. "workflow-run:" run.id))))
         (when (and run-node self.graph self.graph.add-edge)
           (self.graph:add-edge (GraphEdge {:source self :target run-node :label "run"})))
         run))
  (set node.actions [{:name "Start Run"
                       :icon "play_arrow"
                       :fn (fn [_button _event]
                             (node:start-workflow-from-graph {} {}))}])
  (set node.get-edges
       (fn [self]
         (local current (self.workflow-store:get-definition self.workflow-definition-id))
         (local edges [])
         (when current
           (local step-nodes {})
           (each [_ step (ipairs current.steps)]
             (local step-node (resolve-node self.graph (step-key current.id step.id)))
             (when step-node
               (set (. step-nodes step.id) step-node)
               (add-edge edges self step-node "step"))
             (local code-node (resolve-node self.graph (.. "code-entity:" step.code-entity-id)))
             (add-edge edges (if step-node step-node self) code-node "code"))
           (each [_ edge (ipairs current.edges)]
             (local source (cached-or-resolved-step-node step-nodes self.graph current.id edge.source-step-id))
             (local target (cached-or-resolved-step-node step-nodes self.graph current.id edge.target-step-id))
              (add-edge edges source target (edge-label edge) {:from-workflow-edge edge.id}))
           (each [_ run (ipairs (self.workflow-store:list-runs {:definition-id current.id}))]
             (add-edge edges self (resolve-node self.graph (.. "workflow-run:" run.id)) "run")))
         edges))
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-definition.register-loader requires store"))
  (local runner (assert options.runner "workflow-definition.register-loader requires runner"))
  (graph:register-key-loader "workflow-definition"
    (fn [key]
      (local prefix "workflow-definition:")
      (when (= (string.sub key 1 (string.len prefix)) prefix)
        (local definition-id (string.sub key (+ 1 (string.len prefix))))
        (when (and (> (string.len definition-id) 0)
                   (store:get-definition definition-id))
          (WorkflowDefinitionNode {:definition-id definition-id
                                   :store store
                                   :runner runner}))))))

{:WorkflowDefinitionNode WorkflowDefinitionNode
 :find-step find-step
 :register-loader register-loader}
