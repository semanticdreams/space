(local WorldData (require :graph/world-data))
(local {:HeightfieldTerrainNode HeightfieldTerrainNode} (require :graph/nodes/heightfield-terrain))

(local M {})

(local editor-specs
  {"heightfield-terrain" {:node-kind HeightfieldTerrainNode}})

(fn editor-key [world-id activity-id terrain-id]
  (.. "activity-terrain-editor:" world-id ":" activity-id ":" terrain-id))

(fn editor-spec [terrain-kind]
  (. editor-specs terrain-kind))

(fn has-editor? [terrain-kind]
  (not (= (editor-spec terrain-kind) nil)))

(fn create-editor-node [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainEditors.create-editor-node requires :world-id"))
  (local activity-id (assert options.activity-id "TerrainEditors.create-editor-node requires :activity-id"))
  (local terrain-id (assert options.terrain-id "TerrainEditors.create-editor-node requires :terrain-id"))
  (local world-manager (assert options.world-manager "TerrainEditors.create-editor-node requires :world-manager"))
  (local resolved (or options.terrain-entry
                       (WorldData.find-terrain world-manager world-id activity-id terrain-id)))
  (local terrain-kind (or options.terrain-kind
                          (and resolved resolved.kind)))
  (local spec (editor-spec terrain-kind))
  (if spec
       (spec.node-kind {:world-id world-id
                        :activity-id activity-id
                        :terrain-id terrain-id
                       :world-manager world-manager
                       :terrain-entry resolved
                       :key (or options.key (editor-key world-id activity-id terrain-id))})
      nil))

{:editor-key editor-key
 :editor-spec editor-spec
 :has-editor? has-editor?
 :create-editor-node create-editor-node}
