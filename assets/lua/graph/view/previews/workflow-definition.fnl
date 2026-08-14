(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowDefinitionNodePreview requires node")))

(fn resolve-build-ctx [ctx options target]
  (if ctx
      ctx
      options.ctx
      options.ctx
      (and target target.graph target.graph.ctx)
      target.graph.ctx
      (error "WorkflowDefinitionNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn start-from-preview [target]
  (assert (and target target.start-workflow-from-graph)
          "Workflow definition preview requires start-workflow-from-graph")
  (target:start-workflow-from-graph {} {}))

(fn start-click-handler [target]
  (fn [_button _event]
    (start-from-preview target)))

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Workflow"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local start-button
    ((Button {:text "Start"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (start-click-handler target)})
     build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget start-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.start-button start-button)
  (set view.drop
       (fn [_self]
         (title:drop)
         (start-button:drop)
         (flex:drop)))
  view)

(fn WorkflowDefinitionNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx options target))))

WorkflowDefinitionNodePreview
