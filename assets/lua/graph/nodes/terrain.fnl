(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local TerrainNodeView (require :graph/view/views/terrain))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.TerrainNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainNode requires :world-id"))
  (local world-manager (assert options.world-manager "TerrainNode requires :world-manager"))
  (local terrain-id (assert options.terrain-id "TerrainNode requires :terrain-id"))
  (local resolved (or options.terrain-entry
                      (WorldData.find-terrain world-manager world-id terrain-id)
                      {}))
  (local terrain (or options.terrain resolved.entry resolved.record {}))
  (local terrain-record (or options.terrain-record resolved.record {}))
  (local terrain-kind (or terrain.kind terrain-record.kind resolved.kind "unknown"))
  (local key (or options.key (.. "terrain:" world-id ":" terrain-id)))
  (local label (or options.label terrain-kind))
  (local node (GraphNode {:key key
                           :label label
                           :color (glm.vec4 0.4 0.6 0.4 1)
                           :sub-color (glm.vec4 0.3 0.5 0.3 1)
                           :size 7.0
                           :view TerrainNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.terrain-id terrain-id)
  (set node.terrain-kind terrain-kind)
  (set node.terrain terrain)
  (set node.terrain-record terrain-record)
  (set node.changed (Signal))
  (set node.actions [])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (local current (WorldData.find-terrain world-manager world-id terrain-id))
           (when (not current)
             (when (and node.graph node.graph.remove-nodes)
               (node.graph:remove-nodes [node]))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))))
  node)

M
