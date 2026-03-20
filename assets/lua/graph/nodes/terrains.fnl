(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local TerrainsNodeView (require :graph/view/views/terrains))
(local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.TerrainsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainsNode requires :world-id"))
  (local world-manager (assert options.world-manager "TerrainsNode requires :world-manager"))
  (local key (or options.key (.. "terrains:" world-id)))
  (local node (GraphNode {:key key
                           :label "terrains"
                           :color (glm.vec4 0.35 0.55 0.35 1)
                           :sub-color (glm.vec4 0.25 0.45 0.25 1)
                           :size 8.0
                           :view TerrainsNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.items-changed (Signal))
  (fn collect-items [self]
    (WorldData.list-terrains self.world-manager self.world-id))
  (fn emit-items [self]
    (local items (collect-items self))
    (self.items-changed:emit items)
    items)
  (set node.collect-items collect-items)
  (set node.emit-items emit-items)
  (set node.add-terrain-node
       (fn [self entry]
         (local graph self.graph)
         (when (and graph entry entry.terrain-id)
           (local terrain-node (TerrainNode {:world-id self.world-id
                                             :world-manager self.world-manager
                                             :terrain-id entry.terrain-id
                                             :terrain entry.entry
                                             :terrain-record entry.record
                                             :label entry.kind}))
           (graph:add-edge (GraphEdge {:source self
                                       :target terrain-node})))))
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
                 (node.graph:remove-nodes [node]))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.items-changed
           (self.items-changed:clear))))
  node)

M
