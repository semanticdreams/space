(local SearchView (require :search-view))
(local Button (require :button))

(fn EntitiesNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local items (or options.items []))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "EntitiesNodeView requires a build context")
    (local view {})

    (local search
      ((SearchView {:items []
                    :name "entities-view"
                    :num-per-page 10
                    :builder (fn [item child-ctx]
                               (local label (tostring (. item 2)))
                               ((Button {:text label
                                         :variant :ghost
                                         :on-click (fn [_button _event]
                                                     (when (and target target.add-type-node)
                                                       (target:add-type-node (. item 1))))})
                                child-ctx))})
       build-ctx))

    (set view.search search)
    (set view.layout search.layout)

    (set view.set-items
         (fn [_self new-items]
           (search:set-items new-items)))

    (set view.refresh-items
         (fn [self]
           (local refreshed
             (if (and target target.emit-types)
                 (target:emit-types)
                 items))
           (self:set-items refreshed)
           (when self.search
             (set self.search.items refreshed))))

    (local types-signal (and target target.types-changed))
    (local types-handler
      (and types-signal
           (fn [new-items]
             (view:set-items new-items))))
    (when types-signal
      (types-signal:connect types-handler))

    (set view.drop
         (fn [_self]
           (when types-signal
             (types-signal:disconnect types-handler true))
           (search:drop)))

    (search.submitted:connect
      (fn [item]
        (when (and target target.add-type-node item)
          (target:add-type-node (. item 1)))))

    (view:refresh-items)
    view))

EntitiesNodeView
