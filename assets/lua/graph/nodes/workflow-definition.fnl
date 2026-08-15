(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local WorkflowTemplates (require :workflows/templates))
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

(fn load-required-node [graph key]
  (assert graph "WorkflowDefinitionNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowDefinitionNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowDefinitionNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowDefinitionNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowDefinitionNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label})))

(fn step-key [definition-id step-id]
  (.. "workflow-step:" definition-id ":" step-id))

(fn run-key [run-id]
  (.. "workflow-run:" run-id))

(fn run-label [run]
  (local status (if (and run run.status) run.status :pending))
  (.. "Workflow run " run.id " (" (tostring status) ")"))

(fn load-owned-run-record [self run-or-id]
  (assert self.workflow-store "WorkflowDefinitionNode.load-run-from-graph requires workflow store")
  (assert self.workflow-store.get-run "WorkflowDefinitionNode.load-run-from-graph requires workflow store:get-run")
  (local run-id (if (= (type run-or-id) :table)
                    (assert run-or-id.id "WorkflowDefinitionNode.load-run-from-graph requires run id")
                    (assert run-or-id "WorkflowDefinitionNode.load-run-from-graph requires run id")))
  (local run (self.workflow-store:get-run run-id))
  (assert run (.. "WorkflowDefinitionNode.load-run-from-graph missing workflow run: " (tostring run-id)))
  (assert (= run.definition-id self.workflow-definition-id)
          (.. "WorkflowDefinitionNode.load-run-from-graph run " (tostring run-id)
              " does not belong to workflow definition " (tostring self.workflow-definition-id)))
  run)

(fn assert-create-step-graph-dependencies [self]
  (assert self.graph "WorkflowDefinitionNode.create-step-from-graph requires a graph map")
  (assert self.graph.load-by-key "WorkflowDefinitionNode.create-step-from-graph requires graph:load-by-key")
  (assert self.graph.add-edge "WorkflowDefinitionNode.create-step-from-graph requires graph:add-edge")
  (assert self.workflow-store.delete-step
          "WorkflowDefinitionNode.create-step-from-graph rollback requires workflow store:delete-step")
  (assert self.code-store.delete-entity
          "WorkflowDefinitionNode.create-step-from-graph rollback requires code store:delete-entity"))

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

(fn assert-create-step-loaders [self]
  (assert-graph-loader self.graph "workflow-step:__preflight__:__step__"
                       "WorkflowDefinitionNode.create-step-from-graph"
                       "workflow-step")
  (assert-graph-loader self.graph "code-entity:__preflight__"
                       "WorkflowDefinitionNode.create-step-from-graph"
                       "code-entity"))

(fn assert-load-run-graph-dependencies [self]
  (assert self.graph "WorkflowDefinitionNode.load-run-from-graph requires a graph map")
  (assert self.graph.load-by-key "WorkflowDefinitionNode.load-run-from-graph requires graph:load-by-key")
  (assert self.graph.add-edge "WorkflowDefinitionNode.load-run-from-graph requires graph:add-edge"))

(fn assert-start-graph-dependencies [self]
  (assert self.graph "WorkflowDefinitionNode.start-workflow-from-graph requires a graph map")
  (assert self.graph.load-by-key "WorkflowDefinitionNode.start-workflow-from-graph requires graph:load-by-key")
  (assert self.graph.add-edge "WorkflowDefinitionNode.start-workflow-from-graph requires graph:add-edge")
  (local provider (loader-graph self.graph))
  (assert (and provider
               (provider:has-key-loader-for-key "workflow-run:__preflight__"))
           "WorkflowDefinitionNode.start-workflow-from-graph requires graph loader for workflow-run"))

(fn remove-graph-nodes-by-key! [graph keys]
  (when (and graph graph.lookup graph.remove-nodes)
    (local nodes [])
    (each [_ key (ipairs keys)]
      (local node (graph:lookup key))
      (when node
        (table.insert nodes node)))
    (when (> (length nodes) 0)
      (graph:remove-nodes nodes {:cause "workflow-step-create-rollback"}))))

(fn rollback-created-step! [self result cause]
  (local rollback-errors [])
  (when (and result result.step result.step.id)
    (remove-graph-nodes-by-key! self.graph [(step-key self.workflow-definition-id result.step.id)
                                            (and result.code-entity
                                                 result.code-entity.id
                                                 (.. "code-entity:" result.code-entity.id))]))
  (when (and result result.step result.step.id)
    (local (ok err) (pcall self.workflow-store.delete-step
                           self.workflow-store
                           self.workflow-definition-id
                           result.step.id
                           {:delete-dependent-edges? true}))
    (when (not ok)
      (table.insert rollback-errors (tostring err))))
  (when (and result result.code-entity result.code-entity.id)
    (local (ok err) (pcall self.code-store.delete-entity self.code-store result.code-entity.id))
    (when (not ok)
      (table.insert rollback-errors (tostring err))))
  (if (> (length rollback-errors) 0)
      (error (.. (tostring cause) " (rollback failed: " (table.concat rollback-errors "; ") ")"))
      (error cause)))

(fn load-created-step-into-graph! [self result]
  (local step-key (step-key self.workflow-definition-id result.step.id))
  (local code-key (.. "code-entity:" result.code-entity.id))
  (local step-node (load-required-node self.graph step-key))
  (local code-node (load-required-node self.graph code-key))
  (add-visible-edge self.graph self step-node "step")
  (add-visible-edge self.graph step-node code-node "code"))

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
  (set node.code-store options.code-store)
  (set node.start-workflow-from-graph
       (fn [self input context-opts]
          (assert-start-graph-dependencies self)
          (local run-input (if (= input nil) {} input))
          (local run (self.workflow-runner:start-run self.workflow-definition-id
                                                     run-input
                                                     (graph-context self.graph context-opts)))
          (local run-node (load-required-node self.graph (run-key run.id)))
          (add-visible-edge self.graph self run-node "run")
          run))
  (set node.create-step-from-graph
        (fn [self opts]
           (assert self.workflow-store "WorkflowDefinitionNode.create-step-from-graph requires workflow store")
           (assert self.code-store "WorkflowDefinitionNode.create-step-from-graph requires code store")
           (assert-create-step-graph-dependencies self)
           (assert-create-step-loaders self)
           (local result (WorkflowTemplates.create-template-step self.workflow-store
                                                                self.code-store
                                                                self.workflow-definition-id
                                                                (or opts {})))
          (local (ok graph-err)
            (pcall load-created-step-into-graph! self result))
          (if ok
               result
               (rollback-created-step! self result graph-err))))
  (set node.run-items
       (fn [self]
         (assert self.workflow-store "WorkflowDefinitionNode.run-items requires workflow store")
         (icollect [_ run (ipairs (self.workflow-store:list-runs {:definition-id self.workflow-definition-id}))]
           [run (run-label run)])))
  (set node.load-run-from-graph
        (fn [self run-or-id]
          (assert-load-run-graph-dependencies self)
          (local run (load-owned-run-record self run-or-id))
          (local run-id run.id)
          (local run-node (load-required-node self.graph (run-key run-id)))
          (add-visible-edge self.graph self run-node "run")
          run-node))
  (set node.actions [{:name "Start Run"
                        :icon "play_arrow"
                        :fn (fn [_button _event]
                              (node:start-workflow-from-graph {} {}))}
                     {:name "New Step"
                      :icon "add"
                      :fn (fn [_button _event]
                            (node:create-step-from-graph {}))}])
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
                                    :runner runner
                                    :code-store options.code-store}))))))

{:WorkflowDefinitionNode WorkflowDefinitionNode
 :find-step find-step
 :register-loader register-loader}
