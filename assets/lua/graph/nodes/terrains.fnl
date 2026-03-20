(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local TerrainsNodeView (require :graph/view/views/terrains))
(local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))

(local M {})

(fn M.TerrainsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainsNode requires :world-id"))
  (local key (or options.key (.. "terrains:" world-id)))
  (local node (GraphNode {:key key
                           :label "terrains"
                           :color (glm.vec4 0.35 0.55 0.35 1)
                           :sub-color (glm.vec4 0.25 0.45 0.25 1)
                           :size 8.0
                           :view TerrainsNodeView}))
  (set node.world-id world-id)
  (set node.items-changed (Signal))
  (fn collect-items [self]
    (local scene (and app.scene))
    (local terrains (and scene scene.scene-terrains))
    (local produced [])
    (each [idx entry (ipairs (or terrains []))]
      (local record (and entry entry.record))
      (local terrain-id (or (and record record.id) (tostring idx)))
      (local kind (or (and record record.kind) "unknown"))
      (local label (.. kind " [" terrain-id "]"))
      (table.insert produced [{:terrain-id terrain-id
                               :kind kind
                               :entry entry}
                              label]))
    produced)
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
                                             :terrain-id entry.terrain-id
                                             :terrain entry.entry}))
           (graph:add-edge (GraphEdge {:source self
                                       :target terrain-node})))))
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
