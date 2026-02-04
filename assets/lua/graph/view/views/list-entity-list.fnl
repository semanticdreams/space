(local SearchView (require :search-view))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(fn ListEntityListNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local items (or options.items []))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "ListEntityListNodeView requires a build context")
    (local view {})

    (local create-button
      ((Button {:icon "add"
                :text "Create"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.create-entity target.add-entity-node)
                              (local entity (target:create-entity {}))
                              (target:add-entity-node entity)))})
       build-ctx))

    (local search
      ((SearchView {:items []
                    :name "list-entity-list-view"
                    :num-per-page 10
                    :builder (fn [item child-ctx]
                               (local label (tostring (. item 2)))
                               ((Button {:text label
                                         :variant :ghost
                                         :on-click (fn [_button _event]
                                                     (when (and target target.add-entity-node)
                                                       (target:add-entity-node (. item 1))))})
                                child-ctx))})
       build-ctx))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] create-button) 0)
                         (FlexChild (fn [_] search) 1)]})
       build-ctx))

    (set view.search search)
    (set view.create-button create-button)
    (set view.layout flex.layout)

    (set view.set-items
         (fn [_self new-items]
           (search:set-items new-items)))

    (set view.refresh-items
         (fn [self]
           (local refreshed
             (if (and target target.emit-items)
                 (target:emit-items)
                 items))
           (self:set-items refreshed)
           (when self.search
             (set self.search.items refreshed))))

    (local items-signal (and target target.items-changed))
    (local items-handler
      (and items-signal
           (fn [new-items]
             (view:set-items new-items))))
    (when items-signal
      (items-signal:connect items-handler))

    (set view.drop
         (fn [_self]
           (when items-signal
             (items-signal:disconnect items-handler true))
           (search:drop)
           (create-button:drop)
           (flex:drop)))

    (search.submitted:connect
      (fn [item]
        (when (and target target.add-entity-node item)
          (target:add-entity-node (. item 1)))))

    (view:refresh-items)
    view))

ListEntityListNodeView
