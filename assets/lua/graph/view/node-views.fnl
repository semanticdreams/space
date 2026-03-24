(local Dialog (require :dialog))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local {:TableNode TableNode} (require :graph/nodes/table))
(local fs (require :fs))
(local logging (require :logging))
(local MathUtils (require :math-utils))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

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

    (fn panel-placement-options [panel]
        (local layer (or (and panel panel.layer) "tiles"))
        (if (= layer "float")
            {:location :float
             :position (array->vec3 (and panel panel.position))
             :rotation (array->quat (and panel panel.rotation))
             :size (array->vec3 (and panel panel.size))}
            {:location :tiles
             :align-x (and panel panel.align-x)
             :align-y (and panel panel.align-y)}))

    (fn build-persistence [node-key]
        {:kind persistence-kind
         :node-key node-key})

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

    (fn drop-node-view [node]
        (local record (. node-views node))
        (when record
            (if (and record.target record.element record.target.remove-panel-child)
                (record.target:remove-panel-child record.element)
                (when (and record.dialog record.dialog.drop)
                    (record.dialog:drop)))
            (set (. node-views node) nil)))

    (fn wrap-node-view [node builder]
        (fn [ctx opts]
            (var view (builder ctx opts))
            (when (= (type view) :function)
                ;; Some builders may return another builder; unwrap it once so we
                ;; can still enforce the widget contract.
                (set view (view ctx opts)))
            (assert (and view view.layout)
                    "Node view builder must return a widget with a layout")
            (fn resolve-view-module-name [node]
                (local view-fn (and node node.view))
                (assert (= (type view-fn) :function)
                        "Node view code action requires a node view function")
                (var module-name nil)
                (each [name value (pairs package.loaded)]
                    (when (= value view-fn)
                        (set module-name name)))
                (assert module-name "Node view code action requires a loaded view module")
                module-name)
            (fn resolve-view-module-path [module-name]
                (assert app "Node view code action requires global app")
                (assert (and app.engine app.engine.get-asset-path)
                        "Node view code action requires app.engine.get-asset-path")
                (assert module-name "Node view code action requires module name")
                (app.engine.get-asset-path (.. "lua/" module-name ".fnl")))
            (var dialog-instance nil)
            (local dialog-builder
              (Dialog {:title (or node.label node.key)
                       :actions [{:name "table"
                                  :icon "table"
                                  :handler (fn [_button _event]
                                             (local graph (and node node.graph))
                                             (assert graph "Node view table action requires a mounted graph")
                                             (assert dialog-instance
                                                     "Node view table action requires a built dialog")
                                             (local key (.. "table:node-view-dialog:"
                                                            (tostring dialog-instance)))
                                             (local table-node (or (and graph.lookup (graph:lookup key))
                                                                   (TableNode {:table dialog-instance
                                                                               :key key
                                                                               :label (.. "node view: "
                                                                                         (or node.label node.key))})))
                                             (graph:add-edge (GraphEdge {:source node
                                                                         :target table-node}))) }
                                 {:name "code"
                                  :icon "code"
                                  :handler (fn [_button _event]
                                             (local graph (and node node.graph))
                                             (assert graph "Node view code action requires a mounted graph")
                                             (local module-name (resolve-view-module-name node))
                                             (local module-path (resolve-view-module-path module-name))
                                             (local key (.. "fs:" module-path))
                                             (local fs-node (or (and graph.lookup (graph:lookup key))
                                                                (FsNode {:path (fs.absolute module-path)
                                                                         :key key})))
                                             (graph:add-edge (GraphEdge {:source node
                                                                         :target fs-node}))) }
                                 {:name "close"
                                  :icon "close"
                                  :handler (fn [_button _event]
                                             (drop-node-view node))}]
                       :child (fn [_dialog-ctx] view)}))
            (set dialog-instance (dialog-builder ctx))
            dialog-instance))

    (fn ensure-node-view [node opts]
        (if (or (not node) (. node-views node))
            nil
            (do
                (local local-opts (or opts {}))
                (local builder (resolve-node-view-builder node))
                (local target (or local-opts.target view-target))
                (local dialog-builder (and builder (wrap-node-view node builder)))
                (when dialog-builder
                    (local panel (or local-opts.panel {}))
                    (local placement (panel-placement-options panel))
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
                                                      :target nil})))))))

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
    (register-target-restorer app.scene)

    {:node-views node-views
     :open open-node-view
     :capture-state capture-state
     :restore-state restore-state
     :move-view move-view
     :drop-node drop-node
     :drop-all drop-all})

GraphViewNodeViews
