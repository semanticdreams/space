(local TerrainRecords (require :scene-terrain-records))

(fn resolve-terrain-records [terrains]
  (if (= terrains nil)
      (TerrainRecords.default-records)
      (TerrainRecords.normalize-records terrains)))

(fn build-terrain-entries [terrain-records]
  (var entries [])
  (each [_ record (ipairs (or terrain-records []))]
    (local entry (TerrainRecords.builder-for-record record))
    (table.insert entries {:record entry.record
                           :builder entry.builder
                           :position entry.position
                           :rotation entry.rotation}))
  entries)

(fn capture-terrains [scene-terrains]
  (var terrains [])
  (each [_ metadata (ipairs (or scene-terrains []))]
    (local element (and metadata metadata.element))
    (local layout (and element element.layout))
    (local record (and metadata metadata.record))
    (assert record "SceneWorldState.capture-terrains found terrain without record")
    (table.insert terrains (TerrainRecords.capture-record record layout)))
  terrains)

{:resolve-terrain-records resolve-terrain-records
 :build-terrain-entries build-terrain-entries
 :capture-terrains capture-terrains}
