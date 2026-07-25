(local PanelUtils (require :target-panel-utils))
(local NodeViewDialogBuilder (require :graph/view/node-view-dialog-builder))

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
  (assert (= (type panel.graph-map-id) :string)
          "graph-node-view panel restorer requires string :graph-map-id")
  (local key panel.node-key)
  (fn match-map [candidate]
      (and candidate
           candidate.lookup
           (= candidate.id panel.graph-map-id)))
  (fn target-graph-map [target]
      (and target target.graph-map (match-map target.graph-map) target.graph-map))
  (local graph (or (target-graph-map options.target)
                     (target-graph-map options.scene)
                     (target-graph-map options.hud)
                     (target-graph-map options.canvas)
                     (and (match-map app.graph-map) app.graph-map)
                     (and app.active-world-runtime
                          (match-map app.active-world-runtime.graph-map)
                          app.active-world-runtime.graph-map)))
  (assert graph "graph-node-view panel restore requires active matching graph-map")
  (local node (when graph.lookup (graph:lookup key)))
  (assert node (.. "graph-node-view panel restore node not found: " key))
  (local view-fn (and node node.view))
  (assert (= (type view-fn) :function)
          (.. "graph-node-view panel restore node has no view function: " key))
  (local builder (view-fn node))
  (assert (= (type builder) :function)
          (.. "graph-node-view panel restore view returned non-builder for node: " key))
  (var panel-element nil)
  (local placement (PanelUtils.panel-placement-options target panel))
  (local persistence {:kind "graph-node-view"
                      :node-key key
                      :restorer-module "graph/view/node-view-panel-restorer"})
  (when (and graph graph.id)
     (set persistence.graph-map-id graph.id))
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
          :persistence persistence})))

{:restore restore}
