(local PanelUtils (require :target-panel-utils))
(local NodeViewDialogBuilder (require :graph/view/node-view-dialog-builder))
(local logging (require :logging))

(fn restore [opts]
  (local options (assert opts "graph-node-view panel restorer requires opts"))
  (local target (or options.hud options.canvas options.target))
  (assert target "graph-node-view panel restorer requires target (hud, canvas, or target)")
  (assert (= (type target.add-panel-child) :function)
          "graph-node-view panel restorer requires target with :add-panel-child")
  (local panel (assert options.panel
                       "graph-node-view panel restorer requires :panel"))
  (assert (= (type panel.node-key) :string)
          "graph-node-view panel restorer requires string :node-key")
  (local key panel.node-key)
  (local graph (or app.graph
                   (and app.active-world-runtime app.active-world-runtime.graph)))
  (when (not graph)
    (logging.warn "[graph-node-view] skipping panel restore: no graph available")
    (lua "return nil"))
  (local node (or (when graph.lookup (graph:lookup key))
                  (when graph.load-by-key (graph:load-by-key key))))
  (when (not node)
    (logging.warn (.. "[graph-node-view] skipping panel restore: node not found: " key))
    (lua "return nil"))
  (local view-fn (and node node.view))
  (when (not (= (type view-fn) :function))
    (logging.warn (.. "[graph-node-view] skipping panel restore: node has no view function: " key))
    (lua "return nil"))
  (local builder (view-fn node))
  (when (not (= (type builder) :function))
    (logging.warn (.. "[graph-node-view] skipping panel restore: view returned non-builder for node: " key))
    (lua "return nil"))
  (var panel-element nil)
  (local placement (PanelUtils.panel-placement-options target panel))
  (set panel-element
       (target:add-panel-child
         {:builder (NodeViewDialogBuilder.make-dialog-builder
                     node builder
                     {:on-close (fn [_node _dialog]
                                  (when (and target target.remove-panel-child)
                                    (target:remove-panel-child panel-element)))})
          :location placement.location
          :align-x placement.align-x
          :align-y placement.align-y
          :position placement.position
          :rotation placement.rotation
          :size placement.size
          :persistence {:kind "graph-node-view"
                         :node-key key
                         :restorer-module "graph/view/node-view-panel-restorer"}})))

{:restore restore}
