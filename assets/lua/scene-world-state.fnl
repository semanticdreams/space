(local TerrainRecords (require :scene-terrain-records))
(local HeightfieldTerrainSpace (require :heightfield-terrain-space))
(local logging (require :logging))
(local TerrainIssueLog (require :terrain-issue-log))

(fn resolve-terrain-records [terrains]
  (if (= terrains nil)
      (do
        (TerrainIssueLog.warn "[scene-world-state] resolve-terrain-records received nil; using default terrains")
        (TerrainRecords.default-records))
      (TerrainRecords.normalize-records terrains)))

(fn build-terrain-entries [terrain-records]
  (var entries [])
  (each [idx record (ipairs (or terrain-records []))]
    (if (TerrainRecords.supported-record? record)
        (do
          (local entry (TerrainRecords.builder-for-record record))
          (table.insert entries {:record entry.record
                                 :builder entry.builder
                                 :position entry.position
                                 :rotation entry.rotation}))
        (logging.warn (string.format
                        "[scene] skipping unsupported terrain at index %d (kind=%s)"
                        idx
                        (tostring (and record record.kind))))))
  entries)

(fn local-layout [layout]
  (if (and layout layout.parent layout.parent.position layout.parent.rotation
           layout.position layout.rotation)
      (do
        (local parent-inverse (layout.parent.rotation:inverse))
        {:position (parent-inverse:rotate
                     (- layout.position layout.parent.position))
         :rotation (* parent-inverse layout.rotation)})
      layout))

(fn capture-terrain-layout [record layout-state]
  (if (and layout-state
           (= (and record record.kind) "heightfield-terrain"))
      (do
        (local canonical-record
          (HeightfieldTerrainSpace.record-with-canonical-layout record layout-state))
        {:position (TerrainRecords.array->vec3 canonical-record.options.position)
         :rotation (TerrainRecords.array->quat canonical-record.options.rotation)})
      layout-state))

(fn capture-terrains [scene-terrains]
  (var terrains [])
  (each [_ metadata (ipairs (or scene-terrains []))]
    (local element (and metadata metadata.element))
    (local layout (and element element.layout))
    (local record (and metadata metadata.record))
    (assert record "SceneWorldState.capture-terrains found terrain without record")
    (local layout-state (local-layout layout))
    (local capture-layout (capture-terrain-layout record layout-state))
    (table.insert terrains (TerrainRecords.capture-record record capture-layout)))
  terrains)

{:resolve-terrain-records resolve-terrain-records
 :build-terrain-entries build-terrain-entries
 :capture-terrains capture-terrains}
