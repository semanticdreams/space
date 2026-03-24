(local HeightfieldTerrainQuery (require :heightfield-terrain-query))

(local M {})

(fn M.raycast-record [record ray]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.raycast-record record ray)
      nil))

(fn M.target-between-hits [record start-hit end-hit]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.target-between-hits record start-hit end-hit)
      nil))

(fn M.domain-hit-record [record ray]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.domain-hit-record record ray)
      nil))

(fn M.screen-hit-record [record point opts]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.screen-hit-record record point opts)
      nil))

{:raycast-record M.raycast-record
 :domain-hit-record M.domain-hit-record
 :screen-hit-record M.screen-hit-record
 :target-between-hits M.target-between-hits}
