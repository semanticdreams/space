(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local SearchView (require :search-view))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowStepExplorerNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowStepExplorerNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn step-items [target]
  (assert (and target target.step-items)
          "Workflow step explorer preview requires step-items")
  (target:step-items))

(fn step-count-label [items]
  (.. "Steps: " (length items)))

(fn select-step [target item]
  (assert (and target target.load-step-from-graph)
          "Workflow step explorer preview requires load-step-from-graph")
  (target:load-step-from-graph (. item 1)))

(fn reveal-all-steps [target]
  (assert (and target target.reveal-all-steps-from-graph)
          "Workflow step explorer preview requires reveal-all-steps-from-graph")
  (target:reveal-all-steps-from-graph))

(fn reveal-all-click-handler [target]
  (fn [_button _event]
    (reveal-all-steps target)))

(fn build-content [target build-ctx]
  (local view {})
  (local items (step-items target))
  (local label (if (and target target.label) target.label target.key target.key "Step explorer"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local step-count-text ((Text {:text (step-count-label items)}) build-ctx))
  (local step-search
    ((SearchView {:items items
                  :name "workflow-step-explorer-search"
                  :placeholder "Search workflow steps"})
     build-ctx))
  (local reveal-all-steps-button
    ((Button {:text "Reveal All Steps"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (reveal-all-click-handler target)})
     build-ctx))
  (set view.__step-search-listener
       (step-search.submitted:connect
         (fn [item]
           (select-step target item))))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget step-count-text) 0)
                       (FlexChild (existing-widget step-search) 1)
                       (FlexChild (existing-widget reveal-all-steps-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.summary-text step-count-text)
  (set view.step-count-text step-count-text)
  (set view.step-search step-search)
  (set view.reveal-all-steps-button reveal-all-steps-button)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
         (when view.__step-search-listener
           (step-search.submitted:disconnect view.__step-search-listener true)
           (set view.__step-search-listener nil))
         (title:drop)
         (step-count-text:drop)
         (step-search:drop)
         (reveal-all-steps-button:drop)
         (set flex.children [])
         (flex:drop)))
  view)

(fn WorkflowStepExplorerNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowStepExplorerNodePreview
