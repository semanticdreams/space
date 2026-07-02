(local fs (require :fs))
(local Dialog (require :dialog))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local {:TableNode TableNode} (require :graph/nodes/table))

(fn make-dialog-builder [node builder opts]
  (local options (or opts {}))
  (local on-close options.on-close)
  (fn [ctx builder-opts]
    (var view (builder ctx builder-opts))
    (when (= (type view) :function)
      (set view (view ctx builder-opts)))
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
                                                                 :target table-node})))}
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
                                                                 :target fs-node})))}
                         {:name "close"
                          :icon "close"
                          :handler (fn [_button _event]
                                     (when on-close
                                       (on-close node dialog-instance)))}]
               :child (fn [_dialog-ctx] view)}))
    (set dialog-instance (dialog-builder ctx))
    dialog-instance))

{:make-dialog-builder make-dialog-builder}
