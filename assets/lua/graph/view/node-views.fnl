(local Dialog (require :dialog))

(fn GraphViewNodeViews [opts]
    (local options (or opts {}))
    (local ctx options.ctx)
    (local view-target options.view-target)
    (local view-context (or options.view-context ctx))
    (local node-views {})

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
            (local dialog-builder
              (Dialog {:title (or node.label node.key)
                       :actions [{:name "close"
                                  :icon "close"
                                  :handler (fn [_button _event]
                                             (drop-node-view node))}]
                       :child (fn [_dialog-ctx] view)}))
            (dialog-builder ctx)))

    (fn ensure-node-view [node]
        (when (and node (not (. node-views node)))
            (local builder (resolve-node-view-builder node))
            (local target view-target)
            (local dialog-builder (and builder (wrap-node-view node builder)))
            (when dialog-builder
                (if (and target target.add-panel-child)
                    (do
                        (local element (target:add-panel-child {:builder dialog-builder}))
                        (set (. node-views node) {:target target
                                                  :element element}))
                    (when view-context
                        (local dialog (dialog-builder view-context))
                        (set (. node-views node) {:dialog dialog
                                                  :target nil})))))) 

    (fn open-node-view [_self node]
        (ensure-node-view node))

    (fn move-view [_self old new]
        (when (and old new (. node-views old))
            (set (. node-views new) (. node-views old))
            (set (. node-views old) nil)))

    (fn drop-node [_self node]
        (drop-node-view node))

    (fn drop-all [_self]
        (each [node _ (pairs node-views)]
            (drop-node-view node)))

    {:node-views node-views
     :open open-node-view
     :move-view move-view
     :drop-node drop-node
     :drop-all drop-all})

GraphViewNodeViews
