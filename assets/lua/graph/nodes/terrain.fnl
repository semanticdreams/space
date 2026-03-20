(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local TerrainNodeView (require :graph/view/views/terrain))

(local M {})

(fn M.TerrainNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainNode requires :world-id"))
  (local terrain-id (assert options.terrain-id "TerrainNode requires :terrain-id"))
  (local terrain (or options.terrain {}))
  (local terrain-kind (or terrain.kind "unknown"))
  (local key (or options.key (.. "terrain:" world-id ":" terrain-id)))
  (local label (or options.label terrain-kind))
  (local node (GraphNode {:key key
                           :label label
                           :color (glm.vec4 0.4 0.6 0.4 1)
                           :sub-color (glm.vec4 0.3 0.5 0.3 1)
                           :size 7.0
                           :view TerrainNodeView}))
  (set node.world-id world-id)
  (set node.terrain-id terrain-id)
  (set node.terrain-kind terrain-kind)
  (set node.terrain terrain)
  (set node.changed (Signal))
  (set node.actions [])
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))))
  node)

M
