(local glm (require :glm))
(local MathUtils (require :math-utils))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn resolve-position [record]
  (array->vec3 (or (and record record.options record.options.position) [0 0 0])))

(fn resolve-rotation [record]
  (array->quat (or (and record record.options record.options.rotation) [1 0 0 0])))

(fn clone-options [options]
  (local out {})
  (each [key value (pairs (or options {}))]
    (set (. out key) value))
  out)

(fn copy-record [record]
  (local out {})
  (each [key value (pairs (or record {}))]
    (set (. out key) value))
  out)

(fn canonical-origin-offset [record]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local spacing (HeightfieldTerrainGrid.spacing record))
  (glm.vec3 (* bounds.min-sample-x (. spacing 1))
            0
            (* bounds.min-sample-z (. spacing 2))))

(fn runtime-layout-position [record position rotation]
  (+ position
     (rotation:rotate (canonical-origin-offset record))))

(fn canonical-position-from-runtime-layout [record layout-position rotation]
  (- layout-position
     (rotation:rotate (canonical-origin-offset record))))

(fn canonical-local->runtime-local [record local-point]
  (- local-point (canonical-origin-offset record)))

(fn runtime-local->canonical-local [record local-point]
  (+ local-point (canonical-origin-offset record)))

(fn query-local-origin-offset [record]
  (array->vec3 (or (and record record.runtime-space record.runtime-space.local-origin-offset)
                   [0 0 0])))

(fn canonical-local->query-local [record local-point]
  (- local-point (query-local-origin-offset record)))

(fn query-local->canonical-local [record local-point]
  (+ local-point (query-local-origin-offset record)))

(fn canonical-domain-bounds [record]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local spacing (HeightfieldTerrainGrid.spacing record))
  {:min-x (* bounds.min-sample-x (. spacing 1))
   :max-x (* bounds.max-sample-x (. spacing 1))
   :min-z (* bounds.min-sample-z (. spacing 2))
   :max-z (* bounds.max-sample-z (. spacing 2))})

(fn query-domain-bounds [record]
  (local bounds (canonical-domain-bounds record))
  (local origin-offset (query-local-origin-offset record))
  {:min-x (- bounds.min-x origin-offset.x)
   :max-x (- bounds.max-x origin-offset.x)
   :min-z (- bounds.min-z origin-offset.z)
   :max-z (- bounds.max-z origin-offset.z)})

(fn local->world [record local-point]
  (local rotation (resolve-rotation record))
  (+ (resolve-position record)
     (rotation:rotate local-point)))

(fn world->local [record world-point]
  (local rotation (resolve-rotation record))
  (local inverse (rotation:inverse))
  (inverse:rotate (- world-point (resolve-position record))))

(fn with-position-rotation [record position rotation]
  (local out (copy-record record))
  (local options (clone-options out.options))
  (set options.position (vec3->array position))
  (set options.rotation (quat->array rotation))
  (set out.options options)
  out)

(fn record-with-runtime-layout [record layout]
  (if (or (not record)
          (not layout))
      record
      (do
        (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
        (local out (with-position-rotation record layout.position rotation))
        (if (= record.kind "heightfield-terrain")
            (set out.runtime-space
                 {:local-origin-offset (vec3->array (canonical-origin-offset record))})
            (set out.runtime-space nil))
        out)))

(fn record-with-canonical-layout [record layout]
  (if (or (not record)
          (not layout))
      record
      (do
        (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
        (local position
          (if (= record.kind "heightfield-terrain")
              (canonical-position-from-runtime-layout record layout.position rotation)
              layout.position))
        (local out (with-position-rotation record position rotation))
        (set out.runtime-space nil)
        out)))

{:resolve-position resolve-position
 :resolve-rotation resolve-rotation
 :clone-options clone-options
 :canonical-origin-offset canonical-origin-offset
 :runtime-layout-position runtime-layout-position
 :canonical-position-from-runtime-layout canonical-position-from-runtime-layout
 :canonical-local->runtime-local canonical-local->runtime-local
 :runtime-local->canonical-local runtime-local->canonical-local
 :query-local-origin-offset query-local-origin-offset
 :canonical-local->query-local canonical-local->query-local
 :query-local->canonical-local query-local->canonical-local
 :canonical-domain-bounds canonical-domain-bounds
 :query-domain-bounds query-domain-bounds
 :local->world local->world
 :world->local world->local
 :record-with-runtime-layout record-with-runtime-layout
 :record-with-canonical-layout record-with-canonical-layout}
