(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local PreviewSummary (require :workflows/preview-summary))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowRunStepNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowRunStepNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn current-run-step [target]
  (local store (assert target.workflow-store "WorkflowRunStepNodePreview requires workflow store"))
  (local run-id (assert target.workflow-run-id "WorkflowRunStepNodePreview requires workflow run id"))
  (local step-id (assert target.workflow-step-id "WorkflowRunStepNodePreview requires workflow step id"))
  (assert (store:get-run-step run-id step-id)
          (.. "WorkflowRunStepNodePreview requires an existing run step: " run-id ":" step-id)))

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Workflow run step"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local summary (PreviewSummary.run-step-summary (current-run-step target)))
  (local summary-text ((Text {:text summary}) build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget summary-text) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.summary-text summary-text)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
         (title:drop)
         (summary-text:drop)
         (flex:drop)))
  view)

(fn WorkflowRunStepNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowRunStepNodePreview
