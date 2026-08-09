(local glm (require :glm))
(local logging (require :logging))
(local PanelUtils (require :target-panel-utils))
(local NodeViewDialogBuilder (require :graph/view/node-view-dialog-builder))
(local PanelBounds (require :graph/view/panel-bounds)) (fn new-canvas-float-panel? [target placement panel] (and (= (and target target.interaction-surface) :canvas) (= placement.location :float) (= placement.size nil) (= (and panel panel.size) nil)))
(fn GraphViewNodeViews [opts]
    (local options (or opts {}))
    (local graph-map options.graph-map)
    (local graph-map-id (or (and graph-map graph-map.id) "main"))
    (local ctx options.ctx)
    (local view-target options.view-target)
    (local view-context (or options.view-context ctx))
    (local node-views {})
    (local persistence-kind "graph-node-view")
    (var restorer-targets [])
    (var unresolved-open-views [])
    (local restorer-owner {})

    (var open-node-view nil)
    (var panel-transfer-handler nil)
    (var panel-transfer-source nil)

    (fn build-persistence [node-key]
        (local record {:kind persistence-kind
                        :node-key node-key
                        :restorer-module "graph/view/node-view-panel-restorer"})
        (set record.graph-map-id graph-map-id)
        record)

    (fn same-open-view? [left right]
        (and (= (and left left.node-key) (and right right.node-key))
             (= (and left left.panel) (and right right.panel))))

    (fn record-unresolved-open-view [entry]
        (when (and (= (type entry) :table)
                   (= (type entry.node-key) :string))
            (local normalized {})
            (each [k v (pairs entry)]
                (set (. normalized k) v))
            (when (not normalized.graph-map-id)
                (set normalized.graph-map-id (or (and normalized.panel normalized.panel.graph-map-id)
                                                 graph-map-id)))
            (var exists? false)
            (each [_ current (ipairs unresolved-open-views)]
                (when (same-open-view? current normalized)
                    (set exists? true)))
            (when (not exists?)
                (table.insert unresolved-open-views normalized))))

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
        (when (new-canvas-float-panel? target placement panel) (set placement.size (PanelBounds.default-panel-size)))
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
                        (local record {:target target
                                       :element element})
                        (when local-opts.receiver-id
                            (set record.receiver-id local-opts.receiver-id))
                        (set (. node-views node) record))
                    (when view-context
                        (local dialog (dialog-builder view-context))
                        (set (. node-views node) {:dialog dialog
                                                   :target nil}))))))

    (set open-node-view
         (fn [_self node opts]
             (ensure-node-view node opts)))

    (fn resolve-restored-node [key]
        (local node (and graph-map graph-map.lookup (graph-map:lookup key)))
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
            (fn restore-target []
                (or (and (= target app.canvas)
                         app.canvas
                         app.canvas.active-activity-slot
                         app.canvas.active-activity-slot.visible?
                         app.canvas.active-activity-slot)
                    target))
            (var exists? false)
            (each [_ existing (ipairs restorer-targets)]
                (when (= existing target)
                    (set exists? true)))
            (when (not exists?)
                (target:register-panel-restorer
                    persistence-kind
                    (fn [panel]
                        (assert (= (type panel.graph-map-id) :string)
                                "graph-node-view restorer requires string :graph-map-id")
                        (assert (= graph-map-id panel.graph-map-id)
                                "graph-node-view restorer graph-map-id must match active graph map")
                        (local key panel.node-key)
                        (assert (= (type key) :string)
                                "graph-node-view restorer requires string :node-key")
                        (local node (resolve-restored-node key))
                        (when node
                            (open-node-view nil node {:target (restore-target)
                                                       :panel panel}))
                        (when (not node)
                            (record-unresolved-open-view {:node-key key
                                                          :graph-map-id panel.graph-map-id
                                                          :panel panel})))
                    restorer-owner)
                (table.insert restorer-targets target))))

    (fn unregister-target-restorers []
        (each [_ target (ipairs restorer-targets)]
            (target:unregister-panel-restorer persistence-kind restorer-owner))
        (set restorer-targets []))

    (fn graph-node-view-persistence? [persistence]
        (= (and persistence persistence.kind) persistence-kind))

    (fn persistence-matches-node? [persistence node]
        (and (graph-node-view-persistence? persistence)
             (= persistence.node-key (and node node.key))
             (= persistence.graph-map-id graph-map-id)))

    (fn handle-panel-transferred [payload]
        (local persistence (and payload payload.persistence))
        (when (graph-node-view-persistence? persistence)
            (each [node record (pairs node-views)]
                (when (and record
                           (or (= record.element (and payload payload.element))
                               (persistence-matches-node? persistence node)))
                    (set record.target (or (and payload payload.target)
                                           (and payload payload.destination payload.destination.target)))
                    (set record.element (and payload payload.new-element))
                    (set record.receiver-id (and payload payload.receiver-id))))))

    (fn register-panel-transfer-handler []
        (local pt (and app app.panel-transfer))
        (when (and pt pt.panel-transferred (not panel-transfer-handler))
            (set panel-transfer-source pt)
            (set panel-transfer-handler
                 (pt.panel-transferred:connect handle-panel-transferred))))

    (fn unregister-panel-transfer-handler []
        (local pt panel-transfer-source)
        (when (and pt pt.panel-transferred panel-transfer-handler)
            (pt.panel-transferred:disconnect panel-transfer-handler true)
            (set panel-transfer-handler nil)
            (set panel-transfer-source nil)))

    (fn identify-target-kind [target record]
        (if record.receiver-id
            (values "receiver" record.receiver-id)
            (= target app.hud) "hud"
            (= target app.scene) "scene"
            (= target view-target) "canvas"
            (not target) "canvas"
            (not app.panel-transfer)
            (error "GraphViewNodeViews: unrecognised target and no panel-transfer available")
            (let [receiver (app.panel-transfer:find-receiver-for-target target)]
                (if receiver
                    (values "receiver" receiver.id)
                    (error "GraphViewNodeViews: unrecognised target with no registered receiver")))))

    (fn capture-state [_self]
        (local records [])
        (each [node record (pairs node-views)]
            (when (and node node.key)
                (local entry {:node-key node.key})
                (set entry.graph-map-id graph-map-id)
                (local target (and record record.target))
                (local element (and record record.element))
                (when target
                    (local (kind receiver-id) (identify-target-kind target record))
                    (set entry.target-kind kind)
                    (when receiver-id
                        (set entry.target-receiver-id receiver-id)))
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

    (fn resolve-restore-target [entry]
        (if (= entry.target-kind nil) (values view-target nil)
            (= entry.target-kind "canvas") (values view-target nil)
            (= entry.target-kind "hud")
            (do
                (assert app.hud
                        "GraphViewNodeViews: hud target-kind requires app.hud")
                (values app.hud nil))
            (= entry.target-kind "scene")
            (do
                (assert app.scene
                        "GraphViewNodeViews: scene target-kind requires app.scene")
                (values app.scene nil))
            (= entry.target-kind "receiver")
            (do
                (assert entry.target-receiver-id
                        "GraphViewNodeViews: receiver target-kind requires target-receiver-id")
                (assert app.panel-transfer
                        "GraphViewNodeViews: receiver target-kind requires app.panel-transfer")
                (let [receiver (app.panel-transfer:find-receiver-by-id entry.target-receiver-id)]
                    (assert receiver
                            (.. "GraphViewNodeViews: receiver not found for restore: "
                                entry.target-receiver-id))
                    (let [target (receiver.target-fn)]
                        (assert target
                                (.. "GraphViewNodeViews: receiver target-fn returned nil for: "
                                    entry.target-receiver-id))
                        (values target entry.target-receiver-id))))
            (error (.. "GraphViewNodeViews: unknown target-kind for restore: " entry.target-kind))))

    (fn restore-state [_self state]
        (local payload (or state {}))
        (local open-views
            (if (and payload.open-views (= (type payload.open-views) :table))
                payload.open-views
                (icollect [_ key (ipairs (or payload.open-node-keys []))]
                    {:node-key key
                     :graph-map-id graph-map-id})))
        (assert (= (type open-views) :table)
                "GraphViewNodeViews.restore-state requires :open-views table")
        (set unresolved-open-views [])
        (each [_ entry (ipairs open-views)]
            (assert (= (type entry) :table)
                    "GraphViewNodeViews.restore-state entries must be tables")
            (local key entry.node-key)
            (assert (= (type key) :string)
                    "GraphViewNodeViews.restore-state node-key must be a string")
            (assert (= (type entry.graph-map-id) :string)
                    "GraphViewNodeViews.restore-state requires graph-map-id")
            (assert (= entry.graph-map-id graph-map-id)
                    "GraphViewNodeViews.restore-state graph-map-id must match active graph map")
            (local node (resolve-restored-node key))
            (when node
                (local (target receiver-id) (resolve-restore-target entry))
                (ensure-node-view node {:panel entry.panel :target target :receiver-id receiver-id}))
            (when (not node)
                (record-unresolved-open-view entry)))
        true)

    (fn move-view [_self old new]
        (when (and old new (. node-views old))
            (local record (. node-views old))
            (local opts {:target record.target :receiver-id record.receiver-id})
            (when (and record.target record.element record.target.capture-panel-element-state)
                (set opts.panel (record.target:capture-panel-element-state record.element)))
            (drop-node-view old)
            (ensure-node-view new opts)))

    (fn drop-node [_self node]
        (drop-node-view node))

    (fn drop-all [_self]
        (each [node _ (pairs node-views)]
            (drop-node-view node))
        (unregister-target-restorers)
        (unregister-panel-transfer-handler))

    (register-target-restorer view-target)
    (register-target-restorer app.hud)
    (register-target-restorer app.canvas)
    (register-panel-transfer-handler)

    {:node-views node-views
     :open open-node-view
     :capture-state capture-state
     :restore-state restore-state
     :move-view move-view
     :drop-node drop-node
     :drop-all drop-all})

GraphViewNodeViews
