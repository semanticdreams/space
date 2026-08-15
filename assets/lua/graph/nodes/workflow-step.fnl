(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local GraphAuthoring (require :workflows/graph-authoring))
(local WorkflowStepNodePreview (require :graph/view/previews/workflow-step))

(local STEP_GREEN (glm.vec4 0.18 0.58 0.34 1))
(local STEP_GREEN_ACCENT (glm.vec4 0.28 0.72 0.46 1))

(fn split-key-parts [text]
  (assert text "split-key-parts requires text")
  (local parts [])
  (each [part (string.gmatch text "[^:]+")]
    (table.insert parts part))
  parts)

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

(fn step-key [definition-id step-id]
  (.. "workflow-step:" definition-id ":" step-id))

(fn add-edge [edges source target label opts]
  (when (and source target)
    (local edge (GraphEdge {:source source :target target :label label}))
    (when opts
      (set edge._opts opts))
    (table.insert edges edge)))

(fn load-required-node [graph key]
  (assert graph "WorkflowStepNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowStepNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowStepNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowStepNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowStepNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label})))

(fn edge-label [edge]
  (if edge.kind edge.kind "workflow"))

(fn step-label [step step-id]
  (if (and step (> (string.len (if step.name step.name "")) 0))
      step.name
      step-id))

(fn WorkflowStepNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowStepNode requires store"))
  (local definition-id (assert options.definition-id "WorkflowStepNode requires definition-id"))
  (local step-id (assert options.step-id "WorkflowStepNode requires step-id"))
  (local definition (store:get-definition definition-id))
  (local step (find-step definition step-id))
  (local label (step-label step step-id))
  (local node (GraphNode {:key (step-key definition-id step-id)
                          :label label
                          :color STEP_GREEN
                          :sub-color STEP_GREEN_ACCENT
                          :preview WorkflowStepNodePreview
                          :size 7.5}))
  (set node.workflow-definition-id definition-id)
  (set node.workflow-step-id step-id)
  (set node.workflow-store store)
  (set node.author-domain-edge
       (fn [self edge edge-opts]
         (GraphAuthoring.author-edge self (and edge edge.target) edge-opts)))
  (set node.remove-domain-edge
       (fn [_self edge edge-opts]
         (GraphAuthoring.delete-authored-edge edge edge-opts)))
  (set node.get-step (fn [self]
                        (find-step (self.workflow-store:get-definition self.workflow-definition-id)
                                   self.workflow-step-id)))
  (set node.show-code-from-graph
       (fn [self]
         (local current-step (assert (self:get-step)
                                     "WorkflowStepNode.show-code-from-graph requires an existing workflow step"))
         (local code-entity-id (assert current-step.code-entity-id
                                       "WorkflowStepNode.show-code-from-graph requires step.code-entity-id"))
         (local code-node (load-required-node self.graph (.. "code-entity:" code-entity-id)))
         (add-visible-edge self.graph self code-node "code")
         code-node))
  (set node.actions [{:name "Show Code"
                      :icon "code"
                      :fn (fn [_button _event]
                            (node:show-code-from-graph))}])
  (set node.get-edges
       (fn [self]
         (local current (self.workflow-store:get-definition self.workflow-definition-id))
         (local current-step (find-step current self.workflow-step-id))
         (local edges [])
         (when current-step
           (add-edge edges self (resolve-node self.graph (.. "code-entity:" current-step.code-entity-id)) "code")
           (each [_ edge (ipairs current.edges)]
             (when (= edge.source-step-id self.workflow-step-id)
                (add-edge edges self
                          (resolve-node self.graph (step-key self.workflow-definition-id edge.target-step-id))
                          (edge-label edge)
                          {:from-workflow-edge edge.id}))))
         edges))
  node)

(fn parse-key [key]
  (local prefix "workflow-step:")
  (when (= (string.sub key 1 (string.len prefix)) prefix)
    (local parts (split-key-parts (string.sub key (+ 1 (string.len prefix)))))
    (when (= (length parts) 2)
      (values (. parts 1) (. parts 2)))))

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-step.register-loader requires store"))
  (graph:register-key-loader "workflow-step"
    (fn [key]
      (local (definition-id step-id) (parse-key key))
      (when (and definition-id step-id)
        (local definition (store:get-definition definition-id))
        (when (find-step definition step-id)
          (WorkflowStepNode {:definition-id definition-id
                             :step-id step-id
                             :store store}))))))

{:WorkflowStepNode WorkflowStepNode
 :parse-key parse-key
 :register-loader register-loader}
