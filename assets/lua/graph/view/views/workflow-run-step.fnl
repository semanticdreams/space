(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local JsonUtils (require :json-utils))
(local ScrollView (require :scroll-view))
(local Text (require :text))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn render-value [value]
  (if (= value nil)
      "nil"
      (= (type value) :table)
      (JsonUtils.stable-json value)
      (tostring value)))

(fn payload-text [run-step]
  (local step (assert run-step "WorkflowRunStepNodeView requires run step"))
  (table.concat [(.. "Status: " (render-value step.status))
                 (.. "Attempt: " (render-value step.attempt))
                 (.. "Output: " (render-value step.output))
                 (.. "Wait: " (render-value step.wait))
                 (.. "Error: " (render-value step.error))]
                "\n"))

(fn WorkflowRunStepNodeView [node opts]
  (local options (or opts {}))
  (local target (assert (or node options.node) "WorkflowRunStepNodeView requires node"))
  (fn build [ctx]
    (local build-ctx (assert ctx "WorkflowRunStepNodeView requires a build context"))
    (local view {})
    (assert target.get-run-step "WorkflowRunStepNodeView requires node:get-run-step")
    (local run-step (assert (target:get-run-step) "WorkflowRunStepNodeView requires run step"))
    (local label (if target.label target.label target.key target.key "Workflow run step"))
    (local title ((Text {:text (tostring label)}) build-ctx))
    (local payload-input
      ((Input {:text (payload-text run-step)
               :multiline? true
               :focusable? false
               :min-lines 6
               :max-lines 16
               :min-columns 24
               :max-columns 80})
       build-ctx))
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (existing-widget title) 0)
                         (FlexChild (existing-widget payload-input) 1)]})
       build-ctx))
    (local scroll-view
      ((ScrollView {:child (existing-widget flex)
                    :padding false
                    :scrollbar-policy :as-needed})
       build-ctx))
    (set view.layout scroll-view.layout)
    (set view.title title)
    (set view.payload-input payload-input)
    (set view.flex flex)
    (set view.scroll-view scroll-view)
    (set view.drop
         (fn [_self]
           (scroll-view:drop)))
    view))

WorkflowRunStepNodeView
