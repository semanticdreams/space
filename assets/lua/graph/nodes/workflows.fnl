(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))

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

(fn WorkflowsNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowsNode requires store"))
  (local node (GraphNode {:key "workflows"
                         :label "Workflows"
                         :color WORKFLOW_PURPLE
                         :sub-color WORKFLOW_PURPLE_ACCENT
                         :size 9.0}))
  (set node.workflow-store store)
  (set node.runner options.runner)
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
        (WorkflowsNode {:store store :runner options.runner})))))

{:WorkflowsNode WorkflowsNode
 :register-loader register-loader}
