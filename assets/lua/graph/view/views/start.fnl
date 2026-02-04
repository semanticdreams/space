(local SearchView (require :search-view))
(local Button (require :button))

(fn StartNodeView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local items (or options.items []))

    (fn build [ctx]
        (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert build-ctx "StartNodeView requires a build context")
        (local view {})
        (local search
            ((SearchView {:items []
                          :name "start-node-view"
                          :num-per-page 5
                          :builder (fn [item child-ctx]
                                        (local label (tostring (. item 2)))
                                        ((Button {:text label
                                                  :variant :ghost
                                                  :on-click (fn [_button _event]
                                                                  (when (and target target.add-target)
                                                                      (target:add-target (. item 1))))})
                                         child-ctx))})
             build-ctx))

        (set view.search search)
        (set view.layout search.layout)
        (set view.set-items (fn [_self new-items]
                                 (search:set-items new-items)))
        (set view.add-edge (fn [_self target-node]
                                (when (and target target.add-target)
                                    (target:add-target target-node))))
        (set view.refresh-items
             (fn [self]
                 (local refreshed
                        (if (and target target.emit-targets)
                            (target:emit-targets)
                            items))
                 (self:set-items refreshed)
                 (when self.search
                     (set self.search.items refreshed))))

        (local targets-signal (and target target.targets-changed))
        (local targets-handler (and targets-signal
                                    (fn [new-items]
                                        (view:set-items new-items))))
        (when targets-signal
            (targets-signal:connect targets-handler))

        (set view.drop (fn [_self]
                            (when targets-signal
                                (targets-signal:disconnect targets-handler true))
                            (search:drop)))

        (search.submitted:connect
            (fn [item]
                (when (and target target.add-target item)
                    (target:add-target (. item 1)))))

        (view:refresh-items)
        view))

StartNodeView
