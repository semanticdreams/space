(local HeightfieldTerrainSpace (require :heightfield-terrain-space))

(fn from-canonical-layout [record layout]
  (HeightfieldTerrainSpace.record-with-canonical-layout record layout))

(fn from-runtime-layout [record layout]
  (HeightfieldTerrainSpace.record-with-runtime-layout record layout))

(fn from-metadata [metadata]
  (local record (and metadata metadata.record))
  (local layout (and metadata metadata.element metadata.element.layout))
  (from-runtime-layout record layout))

{:from-canonical-layout from-canonical-layout
 :from-runtime-layout from-runtime-layout
 :from-metadata from-metadata}
