(local glm (require :glm))
(local logging (require :logging))
(local PanelUtils (require :target-panel-utils))
(local NodeViewDialogBuilder (require :graph/view/node-view-dialog-builder))

(fn GraphViewNodeViews [opts]
    (local options (or opts {}))
    (local graph options.graph)
    (local ctx options.ctx)
    (local view-target options.view-target)
    (local view-context (or options.view-context ctx))
    (local node-views {})
    (local persistence-kind "graph-node-view")
    (var restorer-targets [])
    (var unresolved-open-views [])
    (local restorer-owner {})

    (var open-node-view nil)

    (fn build-persistence [node-key]
        {:kind persistence-kind
         :node-key node-key
         :restorer-module "graph/view/node-view-panel-restorer"})

    (fn same-open-view? [left right]
        (and (= (and left left.node-key) (and right right.node-key))
             (= (and left left.panel) (and right right.panel))))

    (fn record-unresolved-open-view [entry]
        (when (and (= (type entry) :table)
                   (= (type entry.node-key) :string))
            (var exists? false)
            (each [_ current (ipairs unresolved-open-views)]
                (when (same-open-view? current entry)
                    (set exists? true)))
            (when (not exists?)
                (table.insert unresolved-open-views entry))))

    (fn resolve-node-view-builder [node]
        (local view-fn (and node node.view))
        (when (= (type view-fn) :function)
            (local builder (view-fn node))
            (when (= (type builder) :function)
                builder)))

    (fn resolve-canvas-open-position [target]
        (local camera (and target target.camera))
        (local position (and camera camera.position))
        (when position
            (glm.vec3 position.x position.y 0)))

    (fn resolve-panel-placement [target panel]
        (local placement (PanelUtils.panel-placement-options target panel))
        (when (and (= (and target target.interaction-surface) :canvas)
                   (= placement.location :float)
                   (= placement.position nil))
            (set placement.position (resolve-canvas-open-position target)))
        placement)

    (fn drop-node-view [node]
        (local record (. node-views node))
        (when record
            (if (and record.target record.element record.target.remove-panel-child)
                (record.target:remove-panel-child record.element)
                (when (and record.dialog record.dialog.drop)
                    (record.dialog:drop)))
            (set (. node-views node) nil)))

    (fn wrap-node-view [node builder]
        (NodeViewDialogBuilder.make-dialog-builder node builder
                                                   {:on-close (fn [_node _dialog]
                                                                (drop-node-view node))}))

    (fn ensure-node-view [node opts]
        (when (and node (not (. node-views node)))
            (local local-opts (or opts {}))
            (local builder (resolve-node-view-builder node))
            (local target (or local-opts.target view-target))
            (local dialog-builder (and builder (wrap-node-view node builder)))
            (when dialog-builder
                (local panel (or local-opts.panel {}))
                (local placement (resolve-panel-placement target panel))
                (local persistence (build-persistence node.key))
                (if (and target target.add-panel-child)
                    (do
                        (local panel-opts {:builder dialog-builder
                                           :location placement.location
                                           :align-x placement.align-x
                                           :align-y placement.align-y
                                           :position placement.position
                                           :rotation placement.rotation
                                           :size placement.size
                                           :persistence persistence})
                        (local element (target:add-panel-child panel-opts))
                        (set (. node-views node) {:target target
                                                  :element element}))
                    (when view-context
                        (local dialog (dialog-builder view-context))
                        (set (. node-views node) {:dialog dialog
                                                  :target nil}))))))

    (set open-node-view
         (fn [_self node opts]
             (ensure-node-view node opts)))

    (fn resolve-restored-node [key]
        (local node (or (and graph graph.lookup (graph:lookup key))
                        (and graph graph.load-by-key (graph:load-by-key key))))
        (if node
            (for [idx (length unresolved-open-views) 1 -1]
                (when (= (and (. unresolved-open-views idx) (. (. unresolved-open-views idx) :node-key)) key)
                    (table.remove unresolved-open-views idx)))
            (logging.warn (.. "[graph-view] skipping unresolved restored node view: " key)))
        node)

    (fn register-target-restorer [target]
        (when (and target
                   target.register-panel-restorer
                   target.unregister-panel-restorer)
            (var exists? false)
            (each [_ existing (ipairs restorer-targets)]
                (when (= existing target)
                    (set exists? true)))
            (when (not exists?)
                (target:register-panel-restorer
                    persistence-kind
                    (fn [panel]
                        (local key panel.node-key)
                        (assert (= (type key) :string)
                                "graph-node-view restorer requires string :node-key")
                        (local node (resolve-restored-node key))
                        (when node
                            (open-node-view nil node {:target target
                                                      :panel panel}))
                        (when (not node)
                            (record-unresolved-open-view {:node-key key
                                                          :panel panel})))
                    restorer-owner)
                (table.insert restorer-targets target))))

    (fn unregister-target-restorers []
        (each [_ target (ipairs restorer-targets)]
            (target:unregister-panel-restorer persistence-kind restorer-owner))
        (set restorer-targets []))

    (fn capture-state [_self]
        (local records [])
        (each [node record (pairs node-views)]
            (when (and node node.key)
                (local entry {:node-key node.key})
                (local target (and record record.target))
                (local element (and record record.element))
                (when (and target element target.capture-panel-element-state)
                    (local panel (target:capture-panel-element-state element))
                    (when panel
                        (set entry.panel panel)))
                (table.insert records entry)))
        (each [_ entry (ipairs unresolved-open-views)]
            (local key (and entry entry.node-key))
            (var exists? false)
            (each [_ current (ipairs records)]
                (when (= current.node-key key)
                    (set exists? true)))
            (when (and (= (type key) :string) (not exists?))
                (table.insert records entry)))
        (table.sort records
                    (fn [a b]
                        (< (or a.node-key "") (or b.node-key ""))))
        {:open-views records})

    (fn restore-state [_self state]
        (local payload (or state {}))
        (local open-views
            (if (and payload.open-views (= (type payload.open-views) :table))
                payload.open-views
                (icollect [_ key (ipairs (or payload.open-node-keys []))]
                    {:node-key key})))
        (assert (= (type open-views) :table)
                "GraphViewNodeViews.restore-state requires :open-views table")
        (set unresolved-open-views [])
        (each [_ entry (ipairs open-views)]
            (assert (= (type entry) :table)
                    "GraphViewNodeViews.restore-state entries must be tables")
            (local key entry.node-key)
            (assert (= (type key) :string)
                    "GraphViewNodeViews.restore-state node-key must be a string")
            (local node (resolve-restored-node key))
            (when node
                (ensure-node-view node {:panel entry.panel}))
            (when (not node)
                (record-unresolved-open-view entry)))
        true)

    (fn move-view [_self old new]
        (when (and old new (. node-views old))
            (set (. node-views new) (. node-views old))
            (set (. node-views old) nil)))

    (fn drop-node [_self node]
        (drop-node-view node))

    (fn drop-all [_self]
        (each [node _ (pairs node-views)]
            (drop-node-view node))
        (unregister-target-restorers))

    (register-target-restorer view-target)
    (register-target-restorer app.hud)
    (register-target-restorer app.canvas)

    {:node-views node-views
     :open open-node-view
     :capture-state capture-state
     :restore-state restore-state
     :move-view move-view
     :drop-node drop-node
     :drop-all drop-all})

GraphViewNodeViews
