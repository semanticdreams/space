(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowRunNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowRunNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn current-run [target]
  (when (and target target.workflow-store target.workflow-run-id)
    (target.workflow-store:get-run target.workflow-run-id)))

(fn current-status [target]
  (local run (current-run target))
  (if (and run run.status) run.status :pending))

(fn details-label [target]
  (if (and target target.details-expanded?) "Hide Details" "Show Details"))

(fn show-details-from-preview [target]
  (assert (and target target.load-details-from-graph)
          "Workflow run preview requires load-details-from-graph")
  (if target.details-expanded?
      (target:hide-details)
      (target:load-details-from-graph)))

(fn update-details-label [view target]
  (local label (details-label target))
  (set view.show-details-button-label label)
  (when (and view.show-details-button view.show-details-button.text view.show-details-button.text.set-text)
    (view.show-details-button.text:set-text label))
  label)

(fn details-click-handler [target view]
  (fn [_button _event]
    (show-details-from-preview target)
    (update-details-label view target)))

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Workflow run"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local status-text ((Text {:text (.. "Status: " (tostring (current-status target)))}) build-ctx))
  (local button-label (update-details-label view target))
  (local show-details-button
    ((Button {:text button-label
               :variant :ghost
               :padding [0.25 0.2]
               :on-click (details-click-handler target view)})
      build-ctx))
  (set view.show-details-button show-details-button)
  (update-details-label view target)
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                        (FlexChild (existing-widget status-text) 0)
                        (FlexChild (existing-widget show-details-button) 0)]})
      build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.status-text status-text)
  (set view.drop
       (fn [_self]
          (title:drop)
          (status-text:drop)
          (show-details-button:drop)
          (flex:drop)))
  view)

(fn WorkflowRunNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowRunNodePreview
