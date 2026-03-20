(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HudPanelsNodeView (require :graph/view/views/hud-panels))
(local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))

(local M {})

(fn M.HudPanelsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HudPanelsNode requires :world-id"))
  (local key (or options.key (.. "hud-panels:" world-id)))
  (local node (GraphNode {:key key
                           :label "hud panels"
                           :color (glm.vec4 0.45 0.65 0.55 1)
                           :sub-color (glm.vec4 0.35 0.55 0.45 1)
                           :size 8.0
                           :view HudPanelsNodeView}))
  (set node.world-id world-id)
  (set node.items-changed (Signal))
  (fn collect-items [self]
    (local hud (and app.hud))
    (local produced [])
    (local tiles (and hud hud.tiles hud.tiles.children))
    (each [idx metadata (ipairs (or tiles []))]
      (local persistence (and metadata metadata.persistence))
      (local kind (or (and persistence persistence.kind) "unknown"))
      (local label (.. kind " [tiles:" idx "]"))
      (table.insert produced [{:index idx
                               :layer "tiles"
                               :kind kind
                               :metadata metadata}
                              label]))
    (local float (and hud hud.float hud.float.children))
    (each [idx metadata (ipairs (or float []))]
      (local persistence (and metadata metadata.persistence))
      (local kind (or (and persistence persistence.kind) "unknown"))
      (local label (.. kind " [float:" idx "]"))
      (table.insert produced [{:index idx
                               :layer "float"
                               :kind kind
                               :metadata metadata}
                              label]))
    produced)
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
                                            :layer entry.layer
                                            :panel-index entry.index
                                            :panel entry.metadata}))
           (graph:add-edge (GraphEdge {:source self
                                       :target panel-node})))))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (set node.drop
       (fn [self]
         (when self.items-changed
           (self.items-changed:clear))))
  node)

M
