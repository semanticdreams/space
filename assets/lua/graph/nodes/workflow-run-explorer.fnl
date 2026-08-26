(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local GraphMapContext (require :graph/map-context))
(local WorkflowRunExplorerPreview (require :graph/view/previews/workflow-run-explorer))

(local EXPLORER_PURPLE (glm.vec4 0.56 0.42 0.9 1))
(local EXPLORER_PURPLE_ACCENT (glm.vec4 0.68 0.52 1.0 1))

(fn run-key [run-id]
  (.. "workflow-run:" run-id))

(fn explorer-key [definition-id]
  (.. "workflow-run-explorer:" definition-id))

(fn definition-label [definition definition-id]
  (if (and definition (> (string.len (if definition.name definition.name "")) 0))
      definition.name
      definition-id))

(fn run-label [run]
  (.. (tostring run.id) " (" (tostring (if run.status run.status "pending")) ")"))

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

(fn current-definition [self action]
  (assert self.workflow-store (.. action " requires workflow store"))
  (assert self.workflow-store.get-definition (.. action " requires workflow store:get-definition"))
  (local definition (self.workflow-store:get-definition self.workflow-definition-id))
  (assert definition (.. action " missing workflow definition: " (tostring self.workflow-definition-id)))
  definition)

(fn load-required-node [graph key]
  (assert graph "WorkflowRunExplorerNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowRunExplorerNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowRunExplorerNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowRunExplorerNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowRunExplorerNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label})))

(fn assert-run-graph-dependencies [self action]
  (GraphMapContext.assert-graph-map self.graph action)
  (assert self.graph.load-by-key (.. action " requires graph:load-by-key"))
  (assert self.graph.add-edge (.. action " requires graph:add-edge")))

(fn assert-run-loader [self action]
  (assert-graph-loader self.graph (run-key "__preflight__") action "workflow-run"))

(fn run-id [run-or-id action]
  (if (= (type run-or-id) :table)
      (assert run-or-id.id (.. action " requires run id"))
      (assert run-or-id (.. action " requires run id"))))

(fn load-owned-run-record [self run-or-id action]
  (current-definition self action)
  (assert self.workflow-store (.. action " requires workflow store"))
  (assert self.workflow-store.get-run (.. action " requires workflow store:get-run"))
  (local id (run-id run-or-id action))
  (local run (self.workflow-store:get-run id))
  (assert run (.. action " missing workflow run: " (tostring id)))
  (assert (= run.definition-id self.workflow-definition-id)
          (.. action " workflow run " (tostring id)
              " does not belong to workflow definition " (tostring self.workflow-definition-id)))
  run)

(fn WorkflowRunExplorerNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowRunExplorerNode requires store"))
  (local definition-id (assert options.definition-id "WorkflowRunExplorerNode requires definition-id"))
  (local definition (store:get-definition definition-id))
  (local node (GraphNode {:key (explorer-key definition-id)
                          :label (.. "Run explorer " (definition-label definition definition-id))
                          :color EXPLORER_PURPLE
                          :sub-color EXPLORER_PURPLE_ACCENT
                          :preview WorkflowRunExplorerPreview
                          :size 8.0}))
  (set node.workflow-definition-id definition-id)
  (set node.workflow-store store)
  (set node.run-items
       (fn [self]
         (current-definition self "WorkflowRunExplorerNode.run-items")
         (assert self.workflow-store.list-runs "WorkflowRunExplorerNode.run-items requires workflow store:list-runs")
         (icollect [_ run (ipairs (self.workflow-store:list-runs {:definition-id self.workflow-definition-id}))]
           [run (run-label run)])))
  (set node.load-run-from-graph
       (fn [self run-or-id]
         (assert-run-graph-dependencies self "WorkflowRunExplorerNode.load-run-from-graph")
         (assert-run-loader self "WorkflowRunExplorerNode.load-run-from-graph")
         (local run (load-owned-run-record self run-or-id "WorkflowRunExplorerNode.load-run-from-graph"))
         (local run-node (load-required-node self.graph (run-key run.id)))
         (add-visible-edge self.graph self run-node "run")
         run-node))
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-run-explorer.register-loader requires store"))
  (graph:register-key-loader "workflow-run-explorer"
    (fn [key]
      (local prefix "workflow-run-explorer:")
      (when (= (string.sub key 1 (string.len prefix)) prefix)
        (local definition-id (string.sub key (+ 1 (string.len prefix))))
        (when (and (> (string.len definition-id) 0)
                   (store:get-definition definition-id))
          (WorkflowRunExplorerNode {:definition-id definition-id
                                    :store store}))))))

{:WorkflowRunExplorerNode WorkflowRunExplorerNode
 :register-loader register-loader}
