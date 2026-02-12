(local SearchView (require :search-view))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(fn CodeDirNodeView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local items (or options.items []))

    (fn build [ctx]
        (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert build-ctx "CodeDirNodeView requires a build context")
        (local view {})

        (local refresh-button
            ((Button {:icon "refresh"
                      :text "Refresh"
                      :variant :ghost
                      :on-click (fn [_button _event]
                                    (when (and target target.emit-items)
                                        (target:emit-items)))})
             build-ctx))

        (local search
            ((SearchView {:items []
                          :name "code-dir-node-view"
                          :num-per-page 12
                          :builder (fn [item child-ctx]
                                       (local label (tostring (. item 2)))
                                       ((Button {:text label
                                                 :variant :ghost
                                                 :on-click (fn [_button _event]
                                                               (when (and target target.open-entry)
                                                                   (target:open-entry (. item 1))))})
                                        child-ctx))})
             build-ctx))

        (local flex
            ((Flex {:axis 2
                    :xalign :stretch
                    :yspacing 0.3
                    :children [(FlexChild (fn [_] refresh-button) 0)
                               (FlexChild (fn [_] search) 1)]})
             build-ctx))

        (set view.search search)
        (set view.refresh-button refresh-button)
        (set view.layout flex.layout)
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
                 (set self.search.items refreshed)))

        (local items-signal (and target target.items-changed))
        (local items-handler (and items-signal
                                  (fn [new-items]
                                      (view:set-items new-items))))
        (when items-signal
            (items-signal:connect items-handler))

        (set view.drop
             (fn [_self]
                 (when items-signal
                     (items-signal:disconnect items-handler true))
                 (search:drop)
                 (refresh-button:drop)
                 (flex:drop)))

        (search.submitted:connect
            (fn [item]
                (when (and target target.open-entry item)
                    (target:open-entry (. item 1)))))

        (view:refresh-items)
        view))

CodeDirNodeView
