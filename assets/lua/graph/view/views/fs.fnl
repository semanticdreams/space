(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local SearchView (require :search-view))
(local ExternalEditor (require :external-editor))
(local FsRipgrepDialog (require :graph/view/views/fs-ripgrep-dialog))
(local fs (require :fs))

(fn constant-child [element]
    (fn [_]
        element))

(fn resolve-target-path [target]
    (local target-path (and target target.path))
    (and target-path fs.absolute (fs.absolute target-path)))

(fn file-mode? [resolved-path]
    (local stat (and resolved-path fs.stat (fs.stat resolved-path)))
    (and stat stat.exists stat.is-file))

(fn make-edit-button [build-ctx hidden? edit-enabled? resolved-path]
    (fn open-edit [_button _event]
        (when edit-enabled?
            (ExternalEditor.open-file resolved-path (fn [] nil))))
    (when (not hidden?)
        ((Button {:icon "edit"
                  :text "Edit"
                  :variant :ghost
                  :enabled? edit-enabled?
                  :on-click open-edit})
         build-ctx)))

(fn make-ripgrep-button [build-ctx hidden? resolved-path open-ripgrep-panel]
    (fn open-ripgrep [_button _event]
        (open-ripgrep-panel))
    (when (not hidden?)
        ((Button {:text "Ripgrep"
                  :variant :ghost
                  :enabled? (not (= resolved-path nil))
                  :on-click open-ripgrep})
         build-ctx)))

(fn make-action-row [build-ctx hidden? edit-button ripgrep-button]
    (when (not hidden?)
        ((Flex {:axis 1
                :xspacing 0.3
                :yalign :center
                :children [(FlexChild (constant-child edit-button) 0)
                           (FlexChild (constant-child ripgrep-button) 0)]})
         build-ctx)))

(fn make-layout [build-ctx file-mode search action-row]
    (local children
        (if file-mode
            [(FlexChild (constant-child search) 1)]
            [(FlexChild (constant-child action-row) 0)
             (FlexChild (constant-child search) 1)]))
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.4
            :children children})
     build-ctx))

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
        (local resolved-path (resolve-target-path target))
        (local file-mode (file-mode? resolved-path))
        (local edit-enabled? file-mode)

        (fn open-ripgrep-panel []
          (assert (and panel-target panel-target.add-panel-child)
                  "FsNodeView ripgrep action requires panel target:add-panel-child")
          (when resolved-path
            (FsRipgrepDialog.open-panel {:target panel-target
                                         :path resolved-path
                                         :label (or target.label resolved-path)})))

        (local edit-button (make-edit-button build-ctx file-mode edit-enabled? resolved-path))
        (local ripgrep-button (make-ripgrep-button build-ctx file-mode resolved-path open-ripgrep-panel))
        (local action-row (make-action-row build-ctx file-mode edit-button ripgrep-button))

        (local search
            ((SearchView {:items []
                          :name "fs-node-view"
                          :num-per-page 10})
             build-ctx))

        (local layout (make-layout build-ctx file-mode search action-row))

        (set view.search search)
        (set view.action-row action-row)
        (set view.edit-button edit-button)
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
                            (layout:drop)))

        (search.submitted:connect
            (fn [item]
                (when (and target target.open-entry item)
                    (target:open-entry (. item 1)))))

        (view:refresh-items)
        view))

FsNodeView
