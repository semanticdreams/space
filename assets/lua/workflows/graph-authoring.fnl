(fn workflow-step-node? [node]
  (and node node.workflow-store node.workflow-definition-id node.workflow-step-id))

(fn author-edge [source-node target-node opts]
  (local options (or opts {}))
  (when (and (workflow-step-node? source-node)
             (workflow-step-node? target-node))
    (when (not (= source-node.workflow-definition-id target-node.workflow-definition-id))
      (error "workflow step graph edge must stay within one workflow definition"))
    (local workflow-edge
      (source-node.workflow-store:add-edge source-node.workflow-definition-id
                                          {:kind (or options.kind :control)
                                           :source-step-id source-node.workflow-step-id
                                           :target-step-id target-node.workflow-step-id
                                           :condition options.condition}))
    {:from-workflow-edge workflow-edge.id}))

(fn delete-authored-edge [edge opts]
  (local options (or opts (and edge edge._opts) {}))
  (local workflow-edge-id options.from-workflow-edge)
  (when workflow-edge-id
    (local source (assert (and edge edge.source)
                          "delete-authored-edge requires edge.source"))
    (local store (assert source.workflow-store
                         "delete-authored-edge requires workflow source store"))
    (local definition-id (assert source.workflow-definition-id
                                 "delete-authored-edge requires workflow definition id"))
    (store:delete-edge definition-id workflow-edge-id)))

{:author-edge author-edge
 :delete-authored-edge delete-authored-edge}
