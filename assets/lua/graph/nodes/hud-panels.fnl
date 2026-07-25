(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HudPanelsNodeView (require :graph/view/views/hud-panels))
(local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.HudPanelsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HudPanelsNode requires :world-id"))
  (local world-manager (assert options.world-manager "HudPanelsNode requires :world-manager"))
  (local key (or options.key (.. "hud-panels:" world-id)))
  (local node (GraphNode {:key key
                           :label "hud panels"
                           :color (glm.vec4 0.45 0.65 0.55 1)
                           :sub-color (glm.vec4 0.35 0.55 0.45 1)
                           :size 8.0
                           :view HudPanelsNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.items-changed (Signal))
  (fn collect-items [self]
    (WorldData.list-hud-panels self.world-manager self.world-id))
  (fn emit-items [self]
    (local items (collect-items self))
    (self.items-changed:emit items)
    items)
  (set node.collect-items collect-items)
  (set node.emit-items emit-items)
  (set node.add-panel-node
       (fn [self entry]
         (local graph self.graph)
         (when (and graph entry entry.index entry.layer)
           (local panel-node (HudPanelNode {:world-id self.world-id
                                            :world-manager self.world-manager
                                            :layer entry.layer
                                            :panel-index entry.index
                                            :panel entry.metadata
                                            :panel-record entry.panel
                                            :label entry.kind}))
           (graph:add-edge (GraphEdge {:source self
                                       :target panel-node})))))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (if (WorldData.resolve-world-entry world-manager world-id)
               (node:emit-items)
               (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.items-changed
           (self.items-changed:clear))))
  node)

M
