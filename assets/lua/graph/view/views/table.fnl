(local SearchView (require :search-view))

(fn TableNodeView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local items (or options.items []))

    (fn build [ctx]
        (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert build-ctx "TableNodeView requires a build context")
        (local view {:entries []})

        (local search
            ((SearchView {:items []
                          :name "table-node-view"
                          :num-per-page 10})
             build-ctx))

        (set view.search search)
        (set view.layout search.layout)
        (set view.set-items (fn [_self new-items]
                                 (search:set-items new-items)))
        (set view.add-node (fn [_self entry]
                                (when (and target target.open-entry)
                                    (target:open-entry entry))))
        (set view.open-entry (fn [self entry]
                                  (when entry
                                      (self:add-node entry))))
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
        (local items-handler (and items-signal
                                  (fn [new-items]
                                      (view:set-items new-items))))
        (when items-signal
            (items-signal:connect items-handler))
        (set view.drop (fn [_self]
                            (when items-signal
                                (items-signal:disconnect items-handler true))
                            (when search
                                (search:drop))))

        (search.submitted:connect
            (fn [item]
                (when (and target target.open-entry item)
                    (target:open-entry (. item 1)))))

        (view:refresh-items)
        view))

TableNodeView
