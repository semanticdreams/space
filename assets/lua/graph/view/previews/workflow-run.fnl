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

(fn action-click-handler [target method-name message]
  (fn [_button _event]
    (assert (and target (. target method-name)) message)
    ((. target method-name) target)))

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Workflow run"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local status-text ((Text {:text (.. "Status: " (tostring (current-status target)))}) build-ctx))
  (local show-run-steps-button
    ((Button {:text "Show Run Steps"
                :variant :ghost
                :padding [0.25 0.2]
                :on-click (action-click-handler target :load-run-steps-from-graph
                                                "Workflow run preview requires load-run-steps-from-graph")})
      build-ctx))
  (local reveal-failed-steps-button
    ((Button {:text "Reveal Failed Steps"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (action-click-handler target :reveal-failed-run-steps-from-graph
                                              "Workflow run preview requires reveal-failed-run-steps-from-graph")})
      build-ctx))
  (local open-timeline-button
    ((Button {:text "Open Timeline"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (action-click-handler target :open-timeline-from-graph
                                              "Workflow run preview requires open-timeline-from-graph")})
      build-ctx))
  (set view.show-run-steps-button show-run-steps-button)
  (set view.reveal-failed-steps-button reveal-failed-steps-button)
  (set view.open-timeline-button open-timeline-button)
  (local flex
    ((Flex {:axis 2
             :xalign :stretch
             :yspacing 0.25
             :children [(FlexChild (existing-widget title) 0)
                         (FlexChild (existing-widget status-text) 0)
                         (FlexChild (existing-widget show-run-steps-button) 0)
                         (FlexChild (existing-widget reveal-failed-steps-button) 0)
                         (FlexChild (existing-widget open-timeline-button) 0)]})
      build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.status-text status-text)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
           (title:drop)
           (status-text:drop)
           (show-run-steps-button:drop)
           (reveal-failed-steps-button:drop)
           (open-timeline-button:drop)
           (set flex.children [])
           (flex:drop)))
  view)

(fn WorkflowRunNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowRunNodePreview
