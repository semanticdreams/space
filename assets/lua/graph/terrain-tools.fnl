(local {:HeightfieldFlatToolNode HeightfieldFlatToolNode} (require :graph/nodes/heightfield-flat-tool))
(local {:HeightfieldAdjustToolNode HeightfieldAdjustToolNode} (require :graph/nodes/heightfield-adjust-tool))
(local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode} (require :graph/nodes/heightfield-perlin-tool))
(local {:HeightfieldResizeToolNode HeightfieldResizeToolNode} (require :graph/nodes/heightfield-resize-tool))

(local M {})

(local tool-specs
  {"heightfield-terrain"
   [{:id "resize-terrain"
     :label "Resize Terrain"
     :node-kind HeightfieldResizeToolNode}
    {:id "initialize-flat"
     :label "Initialize Flat"
     :node-kind HeightfieldFlatToolNode}
    {:id "adjust-height"
     :label "Raise/Lower"
     :node-kind HeightfieldAdjustToolNode}
    {:id "apply-perlin"
     :label "Apply Perlin"
     :node-kind HeightfieldPerlinToolNode}]})

(fn tool-key [world-id terrain-id tool-id]
  (.. "terrain-tool:" world-id ":" terrain-id ":" tool-id))

(fn list-tools [terrain-kind]
  (local specs (. tool-specs terrain-kind))
  (if specs
      (icollect [_ spec (ipairs specs)] spec)
      []))

(fn tool-spec [terrain-kind tool-id]
  (var resolved nil)
  (each [_ spec (ipairs (list-tools terrain-kind))]
    (when (and (not resolved) (= spec.id tool-id))
      (set resolved spec)))
  resolved)

(fn create-tool-node [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainTools.create-tool-node requires :world-id"))
  (local activity-id (or options.activity-id "sandbox"))
  (local terrain-id (assert options.terrain-id "TerrainTools.create-tool-node requires :terrain-id"))
  (local terrain-kind (assert options.terrain-kind "TerrainTools.create-tool-node requires :terrain-kind"))
  (local world-manager (assert options.world-manager "TerrainTools.create-tool-node requires :world-manager"))
  (local tool-id (assert options.tool-id "TerrainTools.create-tool-node requires :tool-id"))
  (local spec (tool-spec terrain-kind tool-id))
  (if spec
       (spec.node-kind {:world-id world-id
                        :activity-id activity-id
                        :terrain-id terrain-id
                       :world-manager world-manager
                       :tool-id tool-id
                       :key (or options.key (tool-key world-id terrain-id tool-id))})
      nil))

{:list-tools list-tools
 :tool-key tool-key
 :tool-spec tool-spec
 :create-tool-node create-tool-node}
