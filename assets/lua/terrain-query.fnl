(local HeightfieldTerrainQuery (require :heightfield-terrain-query))

(local M {})

(fn M.raycast-record [record ray]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.raycast-record record ray)
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

(fn M.surface-info-at-world-point [record world-point]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.surface-info-at-world-point record world-point)
      nil))

(fn M.surface-info-at-local-point [record local-x local-z]
  (local kind (and record record.kind))
  (if (= kind "heightfield-terrain")
      (HeightfieldTerrainQuery.surface-info-at-local-point record local-x local-z)
      nil))

{:raycast-record M.raycast-record
 :domain-hit-record M.domain-hit-record
 :screen-rect-target M.screen-rect-target
 :surface-info-at-world-point M.surface-info-at-world-point
 :surface-info-at-local-point M.surface-info-at-local-point}
