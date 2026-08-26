(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowDefinitionNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowDefinitionNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn workflow-summary [target]
  (assert (and target target.workflow-summary)
          "Workflow definition preview requires workflow-summary")
  (target:workflow-summary))

(fn summary-value [summary key fallback]
  (local value (. summary key))
  (if (= value nil) fallback value))

(fn overview-label [summary]
  (.. "Definition: " (tostring (summary-value summary :definition-id "unknown"))
      "\nName: " (tostring (summary-value summary :name "Workflow"))
      "\nSteps: " (tostring (summary-value summary :step-count 0))
      "\nRuns: " (tostring (summary-value summary :run-count 0))
      "\nLatest: " (tostring (summary-value summary :latest-run-status "none"))))

(fn summary-label [summary]
  (.. (tostring (summary-value summary :step-count 0)) " steps · "
      (tostring (summary-value summary :run-count 0)) " runs · latest "
      (tostring (summary-value summary :latest-run-status "none"))))

(fn start-from-preview [target]
  (assert (and target target.start-workflow-from-graph)
          "Workflow definition preview requires start-workflow-from-graph")
  (target:start-workflow-from-graph {} {}))

(fn create-step-from-preview [target]
  (assert (and target target.create-step-from-graph)
          "Workflow definition preview requires create-step-from-graph")
  (target:create-step-from-graph {}))

(fn open-step-explorer [target]
  (assert (and target target.open-step-explorer-from-graph)
          "Workflow definition preview requires open-step-explorer-from-graph")
  (target:open-step-explorer-from-graph))

(fn open-run-explorer [target]
  (assert (and target target.open-run-explorer-from-graph)
          "Workflow definition preview requires open-run-explorer-from-graph")
  (target:open-run-explorer-from-graph))

(fn click-handler [f target]
  (fn [_button _event]
    (f target)))

(fn build-button [build-ctx text handler]
  ((Button {:text text
            :variant :ghost
            :padding [0.25 0.2]
            :on-click handler})
   build-ctx))

(fn drop-view [view children flex]
  (assert (not view.__dropped) "WorkflowDefinitionNodePreview dropped twice")
  (set view.__dropped true)
  (each [_ child (ipairs children)]
    (child:drop))
  (set flex.children [])
  (flex:drop))

(fn build-content [target build-ctx]
  (local view {})
  (local summary (workflow-summary target))
  (local title ((Text {:text (tostring (summary-value summary :name "Workflow"))}) build-ctx))
  (local overview-text ((Text {:text (overview-label summary)}) build-ctx))
  (local summary-text ((Text {:text (summary-label summary)}) build-ctx))
  (local open-steps-button
    (build-button build-ctx "Open Steps" (click-handler open-step-explorer target)))
  (local open-runs-button
    (build-button build-ctx "Open Runs" (click-handler open-run-explorer target)))
  (local start-button
    (build-button build-ctx "Start" (click-handler start-from-preview target)))
  (local new-step-button
    (build-button build-ctx "New Step" (click-handler create-step-from-preview target)))
  (local children [title overview-text summary-text open-steps-button open-runs-button start-button new-step-button])
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget overview-text) 0)
                       (FlexChild (existing-widget summary-text) 0)
                       (FlexChild (existing-widget open-steps-button) 0)
                       (FlexChild (existing-widget open-runs-button) 0)
                       (FlexChild (existing-widget start-button) 0)
                       (FlexChild (existing-widget new-step-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.overview-text overview-text)
  (set view.summary-text summary-text)
  (set view.open-steps-button open-steps-button)
  (set view.open-runs-button open-runs-button)
  (set view.start-button start-button)
  (set view.new-step-button new-step-button)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
         (drop-view view children flex)))
  view)

(fn WorkflowDefinitionNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowDefinitionNodePreview
