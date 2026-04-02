(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local SearchView (require :search-view))
(local ExternalEditor (require :external-editor))
(local FsRipgrepDialog (require :graph/view/views/fs-ripgrep-dialog))
(local fs (require :fs))

(fn FsNodeView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local items (or options.items []))

    (fn build [ctx]
        (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert build-ctx "FsNodeView requires a build context")
        (local view {})
        (local panel-target (or options.target
                                (and build-ctx build-ctx.panel-target)))
        (local target-path (and target target.path))
        (local resolved-path (and target-path fs.absolute (fs.absolute target-path)))
        (local stat (and resolved-path fs.stat (fs.stat resolved-path)))
        (local edit-enabled? (and stat stat.exists stat.is-file))

        (local edit-button
            ((Button {:icon "edit"
                      :text "Edit"
                      :variant :ghost
                      :enabled? edit-enabled?
                      :on-click (fn [_button _event]
                                    (when edit-enabled?
                                        (ExternalEditor.open-file resolved-path (fn [] nil))))})
             build-ctx))

        (fn open-ripgrep-panel []
          (assert (and panel-target panel-target.add-panel-child)
                  "FsNodeView ripgrep action requires panel target:add-panel-child")
          (when resolved-path
            (FsRipgrepDialog.open-panel {:target panel-target
                                         :path resolved-path
                                         :label (or target.label resolved-path)})))

        (local ripgrep-button
          ((Button {:text "Ripgrep"
                    :variant :ghost
                    :enabled? (not (= resolved-path nil))
                    :on-click (fn [_button _event]
                                (open-ripgrep-panel))})
           build-ctx))

        (local action-row
            ((Flex {:axis 1
                    :xspacing 0.3
                    :yalign :center
                    :children [(FlexChild (fn [_] edit-button) 0)
                               (FlexChild (fn [_] ripgrep-button) 0)]})
             build-ctx))

        (local search
            ((SearchView {:items []
                          :name "fs-node-view"
                          :num-per-page 10})
             build-ctx))

        (local layout
            ((Flex {:axis 2
                    :xalign :stretch
                    :yspacing 0.4
                    :children [(FlexChild (fn [_] action-row) 0)
                               (FlexChild (fn [_] search) 1)]})
             build-ctx))

        (set view.search search)
        (set view.action-row action-row)
        (set view.ripgrep-button ripgrep-button)
        (set view.open-ripgrep-panel (fn [_self] (open-ripgrep-panel)))
        (set view.layout layout.layout)
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
                                (search:drop))
                            (action-row:drop)
                            (ripgrep-button:drop)
                            (edit-button:drop)
                            (layout:drop)))

        (search.submitted:connect
            (fn [item]
                (when (and target target.open-entry item)
                    (target:open-entry (. item 1)))))

        (view:refresh-items)
        view))

FsNodeView
