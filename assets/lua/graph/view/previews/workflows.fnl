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

(fn show-existing-from-preview [target]
  (assert (and target target.load-existing-workflows)
          "Workflows preview requires load-existing-workflows")
  (target:load-existing-workflows))

(fn workflow-counts [target]
  (assert (and target target.workflow-store) "Workflows preview requires workflow store")
  (local store target.workflow-store)
  (assert store.list-definitions "Workflows preview requires workflow-store:list-definitions")
  (assert store.list-runs "Workflows preview requires workflow-store:list-runs")
  {:definitions (length (store:list-definitions))
   :runs (length (store:list-runs {}))})

(fn workflow-summary-text [target]
  (local counts (workflow-counts target))
  (.. "Definitions: " counts.definitions "\nRuns: " counts.runs))

(fn new-workflow-click-handler [target]
  (fn [_button _event]
    (create-workflow-from-preview target)))

(fn show-existing-click-handler [target]
  (fn [_button _event]
    (show-existing-from-preview target)))

(fn build-content [target build-ctx]
  (local view {})
  (local title ((Text {:text "Workflows"}) build-ctx))
  (local summary-text ((Text {:text (workflow-summary-text target)}) build-ctx))
  (local new-workflow-button
    ((Button {:text "New Workflow"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (new-workflow-click-handler target)})
     build-ctx))
  (local show-existing-button
    ((Button {:text "Show Existing Workflows"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (show-existing-click-handler target)})
     build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget summary-text) 0)
                       (FlexChild (existing-widget show-existing-button) 0)
                       (FlexChild (existing-widget new-workflow-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.summary-text summary-text)
  (set view.show-existing-button show-existing-button)
  (set view.new-workflow-button new-workflow-button)
  (set view.drop
       (fn [_self]
         (title:drop)
         (summary-text:drop)
         (show-existing-button:drop)
         (new-workflow-button:drop)
         (flex:drop)))
  view)

(fn WorkflowsNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowsNodePreview
