(local WorldData (require :graph/world-data))
(local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))

(local M {})

(fn editor-key [world-id terrain-id]
  (.. "terrain-editor:" world-id ":" terrain-id))

(fn has-editor? [terrain-kind]
  (= terrain-kind "flat-terrain"))

(fn create-editor-node [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "TerrainEditors.create-editor-node requires :world-id"))
  (local terrain-id (assert options.terrain-id "TerrainEditors.create-editor-node requires :terrain-id"))
  (local world-manager (assert options.world-manager "TerrainEditors.create-editor-node requires :world-manager"))
  (local resolved (or options.terrain-entry
                      (WorldData.find-terrain world-manager world-id terrain-id)))
  (local terrain-kind (or options.terrain-kind
                          (and resolved resolved.kind)))
  (if (= terrain-kind "flat-terrain")
      (FlatTerrainNode {:world-id world-id
                        :terrain-id terrain-id
                        :world-manager world-manager
                        :terrain-entry resolved
                        :key (or options.key (editor-key world-id terrain-id))})
      nil))

{:editor-key editor-key
 :has-editor? has-editor?
 :create-editor-node create-editor-node}
