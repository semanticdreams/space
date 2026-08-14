(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local TerrainsNodeView (require :graph/view/views/terrains))
(local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
(local WorldData (require :graph/world-data))
(local TerrainRecords (require :scene-terrain-records))

(local M {})

(fn terrain-node-key [self terrain-id]
  (.. "activity-terrain:" self.world-id ":" self.activity-id ":" terrain-id))

(fn M.TerrainsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainsNode requires :world-id"))
  (local activity-id (assert options.activity-id "TerrainsNode requires :activity-id"))
  (local world-manager (assert options.world-manager "TerrainsNode requires :world-manager"))
  (local key (or options.key (.. "activity-terrains:" world-id ":" activity-id)))
  (local node (GraphNode {:key key
                           :label "terrains"
                           :color (glm.vec4 0.35 0.55 0.35 1)
                           :sub-color (glm.vec4 0.25 0.45 0.25 1)
                           :size 8.0
                           :view TerrainsNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.items-changed (Signal))
  (set node.supported-terrain-kinds (TerrainRecords.supported-kinds))
  (set node.known-terrain-ids {})
  (fn collect-items [self]
    (WorldData.list-terrains self.world-manager self.world-id self.activity-id))
  (fn update-known-terrain-ids [self items]
    (local known {})
    (each [_ item (ipairs (or items []))]
      (local entry (. item 1))
      (local terrain-id (and entry entry.terrain-id))
      (when terrain-id
        (set (. known terrain-id) true)))
    (set self.known-terrain-ids known)
    known)
  (fn attach-terrain-node [self entry]
    (local graph self.graph)
    (when (and graph entry entry.terrain-id)
      (local terrain-key (terrain-node-key self entry.terrain-id))
	      (local terrain-node
	        (or (graph:lookup terrain-key)
	            (TerrainNode {:world-id self.world-id
                              :activity-id self.activity-id
	                          :world-manager self.world-manager
	                          :terrain-id entry.terrain-id
	                          :terrain entry.entry
	                          :terrain-record entry.record
                              :key terrain-key})))
      (graph:add-edge (GraphEdge {:source self
                                  :target terrain-node}))))
  (fn emit-items [self]
    (local items (collect-items self))
    (update-known-terrain-ids self items)
    (self.items-changed:emit items)
    items)
  (set node.collect-items collect-items)
  (set node.emit-items emit-items)
  (set node.update-known-terrain-ids update-known-terrain-ids)
  (set node.attach-terrain-node attach-terrain-node)
  (set node.open-terrain-node
       (fn [self entry]
         (attach-terrain-node self entry)))
  (set node.add-terrain
       (fn [self terrain-kind]
          (WorldData.add-terrain self.world-manager self.world-id self.activity-id terrain-kind)))
  (update-known-terrain-ids node (collect-items node))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (var changed-handler nil)
  (set changed-handler
        (world-manager.changed:connect
          (fn [payload]
            (if (WorldData.resolve-activity-surface-state world-manager world-id activity-id "scene")
                (do
                  (local items (collect-items node))
                 (when (and node.graph
                            payload
                            (= payload.world-id world-id)
                            (= payload.reason "terrain-added"))
                   (each [_ item (ipairs items)]
                     (local entry (. item 1))
                     (local terrain-id (and entry entry.terrain-id))
                     (when (and terrain-id
                                (not (. node.known-terrain-ids terrain-id)))
                       (attach-terrain-node node entry))))
                 (update-known-terrain-ids node items)
                 (node.items-changed:emit items))
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
