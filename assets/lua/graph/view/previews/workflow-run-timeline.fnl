(local {: Flex : FlexChild} (require :flex))
(local SearchView (require :search-view))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowRunTimelineNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowRunTimelineNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn timeline-items [target]
  (assert (and target target.event-items)
          "Workflow run timeline preview requires event-items")
  (target:event-items))

(fn select-event [target item]
  (assert (and target target.load-event-from-graph)
          "Workflow run timeline preview requires load-event-from-graph")
  (target:load-event-from-graph (. item 1)))

(fn build-content [target build-ctx]
  (local view {})
  (local items (timeline-items target))
  (local label (if (and target target.label) target.label target.key target.key "Workflow run timeline"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local event-count-text ((Text {:text (.. "Events: " (length items))}) build-ctx))
  (local event-search
    ((SearchView {:items items
                  :name "workflow-run-timeline-search"
                  :placeholder "Search workflow run events"})
     build-ctx))
  (set view.__event-search-listener
       (event-search.submitted:connect
         (fn [item]
           (select-event target item))))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget event-count-text) 0)
                       (FlexChild (existing-widget event-search) 1)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.event-count-text event-count-text)
  (set view.event-search event-search)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
         (when view.__event-search-listener
           (event-search.submitted:disconnect view.__event-search-listener true)
           (set view.__event-search-listener nil))
         (title:drop)
         (event-count-text:drop)
         (event-search:drop)
         (set flex.children [])
         (flex:drop)))
  view)

(fn WorkflowRunTimelineNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowRunTimelineNodePreview
