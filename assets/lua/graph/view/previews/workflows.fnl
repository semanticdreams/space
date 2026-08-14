(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowsNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowsNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn create-workflow-from-preview [target]
  (assert (and target target.create-workflow-from-graph)
          "Workflows preview requires create-workflow-from-graph")
  (target:create-workflow-from-graph {}))

(fn new-workflow-click-handler [target]
  (fn [_button _event]
    (create-workflow-from-preview target)))

(fn build-content [target build-ctx]
  (local view {})
  (local title ((Text {:text "Workflows"}) build-ctx))
  (local new-workflow-button
    ((Button {:text "New Workflow"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (new-workflow-click-handler target)})
     build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget new-workflow-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.new-workflow-button new-workflow-button)
  (set view.drop
       (fn [_self]
         (title:drop)
         (new-workflow-button:drop)
         (flex:drop)))
  view)

(fn WorkflowsNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowsNodePreview
