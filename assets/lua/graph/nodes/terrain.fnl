(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local TerrainNodeView (require :graph/view/views/terrain))
(local TerrainEditors (require :graph/terrain-editors))
(local TerrainTools (require :graph/terrain-tools))
(local WorldData (require :graph/world-data))

(local M {})

(fn terrain-node-label [record fallback]
  (or (and record record.name)
      fallback
      "terrain"))

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
  (local label (terrain-node-label terrain-record options.label))
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
  (set node.has-editor? (TerrainEditors.has-editor? terrain-kind))
  (set node.available-tools (TerrainTools.list-tools terrain-kind))
  (set node.terrain terrain)
  (set node.terrain-record terrain-record)
  (set node.changed (Signal))
  (set node.open-editor
       (fn [self]
         (local graph self.graph)
         (local editor
           (and graph
                (TerrainEditors.create-editor-node {:world-id self.world-id
                                                    :terrain-id self.terrain-id
                                                    :world-manager self.world-manager})))
         (when (and graph editor)
           (graph:add-edge (GraphEdge {:source self :target editor})))
	         editor))
  (set node.open-tool
       (fn [self tool-id]
         (local graph self.graph)
         (local tool-node
           (and graph
                (TerrainTools.create-tool-node {:world-id self.world-id
                                                :terrain-id self.terrain-id
                                                :terrain-kind self.terrain-kind
                                                :world-manager self.world-manager
                                                :tool-id tool-id})))
         (when (and graph tool-node)
           (graph:add-edge (GraphEdge {:source self :target tool-node})))
         tool-node))
  (set node.remove-terrain
       (fn [self]
         (WorldData.remove-terrain self.world-manager self.world-id self.terrain-id)))
  (set node.actions
       [{:name "Open Editor"
         :fn (fn [_button _event]
               (node:open-editor))}
         {:name "Delete Terrain"
         :fn (fn [_button _event]
               (when (node:remove-terrain)
                  (when (and node.graph node.graph.remove-nodes)
                    (node.graph:remove-nodes [node] {:cause "shared-delete"}))))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (local current (WorldData.find-terrain world-manager world-id terrain-id))
           (if current
               (do
                  (set node.terrain-kind (or current.kind "unknown"))
                  (set node.has-editor? (TerrainEditors.has-editor? node.terrain-kind))
                  (set node.available-tools (TerrainTools.list-tools node.terrain-kind))
                  (set node.label (terrain-node-label current.record options.label))
                  (set node.terrain (or current.entry current.record {}))
                  (set node.terrain-record (or current.record {}))
                  (node.changed:emit current))
                (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))))
  node)

M
