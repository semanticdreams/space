(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowRunNodePreview requires node")))

(fn resolve-build-ctx [ctx options target]
  (if ctx
      ctx
      options.ctx
      options.ctx
      (and target target.graph target.graph.ctx)
      target.graph.ctx
      (error "WorkflowRunNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn current-run [target]
  (when (and target target.workflow-store target.workflow-run-id)
    (target.workflow-store:get-run target.workflow-run-id)))

(fn current-status [target]
  (local run (current-run target))
  (if (and run run.status) run.status :pending))

(fn toggle-label [target]
  (if (and target target.details-expanded?) "Hide Details" "Show Details"))

(fn toggle-from-preview [target]
  (assert (and target target.toggle-details)
          "Workflow run preview requires toggle-details")
  (target:toggle-details))

(fn toggle-click-handler [target]
  (fn [_button _event]
    (toggle-from-preview target)))

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Workflow run"))
  (local button-label (toggle-label target))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local status-text ((Text {:text (.. "Status: " (tostring (current-status target)))}) build-ctx))
  (local toggle-button
    ((Button {:text button-label
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (toggle-click-handler target)})
     build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget status-text) 0)
                       (FlexChild (existing-widget toggle-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.status-text status-text)
  (set view.toggle-button toggle-button)
  (set view.toggle-button-label button-label)
  (set view.drop
       (fn [_self]
         (title:drop)
         (status-text:drop)
         (toggle-button:drop)
         (flex:drop)))
  view)

(fn WorkflowRunNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx options target))))

WorkflowRunNodePreview
