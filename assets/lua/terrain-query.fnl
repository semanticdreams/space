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

(fn M.screen-rect-target [record start-pos end-pos opts]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.screen-rect-target record start-pos end-pos opts)
      nil))

{:raycast-record M.raycast-record
 :domain-hit-record M.domain-hit-record
 :screen-rect-target M.screen-rect-target
 :target-between-hits M.target-between-hits}
