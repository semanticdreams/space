(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowStepNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowStepNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn show-code-from-preview [target]
  (assert (and target target.show-code-from-graph)
          "Workflow step preview requires show-code-from-graph")
  (target:show-code-from-graph))

(fn show-code-click-handler [target]
  (fn [_button _event]
    (show-code-from-preview target)))

(fn step-code-summary [target]
  (local step (and target target.get-step (target:get-step)))
  (local code-id (and step step.code-entity-id))
  (.. "Code: " (if code-id code-id "missing")))

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Workflow Step"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local code-summary ((Text {:text (step-code-summary target)}) build-ctx))
  (local show-code-button
    ((Button {:text "Show Code"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (show-code-click-handler target)})
     build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget code-summary) 0)
                       (FlexChild (existing-widget show-code-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.code-summary code-summary)
  (set view.show-code-button show-code-button)
  (set view.drop
       (fn [_self]
         (title:drop)
         (code-summary:drop)
         (show-code-button:drop)
         (flex:drop)))
  view)

(fn WorkflowStepNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowStepNodePreview
