(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local SearchView (require :search-view))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowDefinitionNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
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

(fn create-step-from-preview [target]
  (assert (and target target.create-step-from-graph)
          "Workflow definition preview requires create-step-from-graph")
  (target:create-step-from-graph {}))

(fn new-step-click-handler [target]
  (fn [_button _event]
    (create-step-from-preview target)))

(fn run-items [target]
  (assert (and target target.run-items)
          "Workflow definition preview requires run-items")
  (target:run-items))

(fn run-count-label [items]
  (.. "Runs: " (length items)))

(fn select-run [target item]
  (assert (and target target.load-run-from-graph)
          "Workflow definition preview requires load-run-from-graph")
  (target:load-run-from-graph (. item 1)))

(fn build-content [target build-ctx]
  (local view {})
  (local items (run-items target))
  (local label (if (and target target.label) target.label target.key target.key "Workflow"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local run-count-text ((Text {:text (run-count-label items)}) build-ctx))
  (local start-button
    ((Button {:text "Start"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (start-click-handler target)})
     build-ctx))
  (local new-step-button
    ((Button {:text "New Step"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (new-step-click-handler target)})
     build-ctx))
  (local run-search
    ((SearchView {:items items
                  :name "workflow-definition-run-search"
                  :placeholder "Search workflow runs"})
     build-ctx))
  (set view.__run-search-listener
       (run-search.submitted:connect
         (fn [item]
           (select-run target item))))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget run-count-text) 0)
                       (FlexChild (existing-widget run-search) 1)
                       (FlexChild (existing-widget start-button) 0)
                       (FlexChild (existing-widget new-step-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.summary-text run-count-text)
  (set view.run-count-text run-count-text)
  (set view.run-search run-search)
  (set view.start-button start-button)
  (set view.new-step-button new-step-button)
  (set view.flex flex)
  (set view.drop
        (fn [_self]
          (when view.__run-search-listener
            (run-search.submitted:disconnect view.__run-search-listener true)
            (set view.__run-search-listener nil))
          (title:drop)
          (run-count-text:drop)
          (run-search:drop)
          (start-button:drop)
          (new-step-button:drop)
          (set flex.children [])
          (flex:drop)))
  view)

(fn WorkflowDefinitionNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowDefinitionNodePreview
