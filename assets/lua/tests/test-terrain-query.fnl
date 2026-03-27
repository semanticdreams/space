(local glm (require :glm))
(local HeightfieldTerrainQuery (require :heightfield-terrain-query))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local TerrainLayoutRecord (require :terrain-layout-record))
(local TerrainRecords (require :scene-terrain-records))
(local MathUtils (require :math-utils))

(local tests [])
 (local approx (. MathUtils :approx))

(fn make-heights [width depth value-fn]
  (local heights [])
  (for [z 0 (- depth 1)]
    (for [x 0 (- width 1)]
      (table.insert heights (value-fn x z))))
  heights)

(fn vec3-from-spherical [yaw pitch]
  (local cp (math.cos pitch))
  (glm.vec3 (* (math.cos yaw) cp)
            (math.sin pitch)
            (* (math.sin yaw) cp)))

(fn random-range [min-value max-value]
  (+ min-value (* (math.random) (- max-value min-value))))

(fn random-heightfield-record [seed]
  (math.randomseed seed)
  (local chunk-width 5)
  (local chunk-length 5)
  (local min-chunk-x (- (math.random 0 1)))
  (local max-chunk-x (+ min-chunk-x (math.random 0 2)))
  (local min-chunk-z (- (math.random 0 1)))
  (local max-chunk-z (+ min-chunk-z (math.random 0 2)))
  (local chunks [])
  (for [chunk-z min-chunk-z max-chunk-z]
    (for [chunk-x min-chunk-x max-chunk-x]
      (table.insert chunks
        {:coord [chunk-x chunk-z]
         :size [chunk-width chunk-length]
         :heights (make-heights chunk-width chunk-length
                    (fn [x z]
                      (+ (random-range -2.5 2.5)
                         (* 0.35 x)
                         (* 0.2 z))))})))
  (local yaw (random-range (- math.pi) math.pi))
  (local half-angle (/ yaw 2))
  (TerrainRecords.normalize-record
    {:kind "heightfield-terrain"
     :options {:position [(random-range -30 30)
                          (random-range -5 5)
                          (random-range -30 30)]
               :rotation [(math.cos half-angle) 0 (math.sin half-angle) 0]
               :sample-spacing [(random-range 0.75 4.0)
                                (random-range 0.75 4.0)]
               :chunk-samples [chunk-width chunk-length]}
     :chunks chunks}))

(fn random-ray-for-record [record seed]
  (math.randomseed seed)
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local spacing (or (and record.options record.options.sample-spacing) [1 1]))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local local-center
    (glm.vec3 (* (+ bounds.min-sample-x (/ (- bounds.max-sample-x bounds.min-sample-x) 2)) spacing-x)
              0
              (* (+ bounds.min-sample-z (/ (- bounds.max-sample-z bounds.min-sample-z) 2)) spacing-z)))
  (local world-center (HeightfieldTerrainQuery.local->world record local-center))
  (local yaw (random-range (- math.pi) math.pi))
  (local pitch (random-range (- (/ math.pi 3)) (- (/ math.pi 16))))
  (local direction (glm.normalize (vec3-from-spherical yaw pitch)))
  (local distance (random-range 20 120))
  (local lateral (random-range -25 25))
  (local forward (glm.normalize direction))
  (local up (glm.vec3 0 1 0))
  (local right (glm.normalize (glm.cross forward up)))
  (local origin (+ world-center
                   (* forward (glm.vec3 (- distance)))
                   (* right (glm.vec3 lateral))
                   (glm.vec3 0 (random-range 10 60) 0)))
  {:origin origin
   :direction forward})

(fn hits-approx=? [left right]
  (if (or (not left) (not right))
      (= left right)
      (and (approx left.distance right.distance {:epsilon 1e-3})
           (approx left.world-point.x right.world-point.x {:epsilon 1e-3})
           (approx left.world-point.y right.world-point.y {:epsilon 1e-3})
           (approx left.world-point.z right.world-point.z {:epsilon 1e-3})
           (= left.sample.x right.sample.x)
           (= left.sample.z right.sample.z)
           (= left.target.x0 right.target.x0)
           (= left.target.z0 right.target.z0)
           (= left.target.x1 right.target.x1)
           (= left.target.z1 right.target.z1))))

(fn heightfield-raycast-hits-flat-terrain []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [2 2]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local hit
    (HeightfieldTerrainQuery.raycast-record record {:origin (glm.vec3 4 10 4)
                                                    :direction (glm.vec3 0 -1 0)}))
  (assert hit "raycast should hit flat heightfield terrain")
  (assert (< (math.abs hit.world-point.y) 1e-4) "flat terrain hit should land on y=0")
  (assert (= hit.sample.x 2) "raycast should resolve nearest sample x")
  (assert (= hit.sample.z 2) "raycast should resolve nearest sample z")
  (assert (= hit.target.mode :samples) "raycast should return a single-sample target")
  (assert (= hit.target.shape :rect) "raycast should use the compact rectangular sample target")
  (assert (= hit.target.x0 2) "raycast target should use the resolved sample x")
  (assert (= hit.target.z0 2) "raycast target should use the resolved sample z"))

(fn heightfield-raycast-respects-transform []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [10 3 20]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [2 2]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 1.5))}]}))
  (local hit
    (HeightfieldTerrainQuery.raycast-record record {:origin (glm.vec3 14 20 24)
                                                    :direction (glm.vec3 0 -1 0)}))
  (assert hit "raycast should hit translated heightfield terrain")
  (assert (< (math.abs (- hit.world-point.x 14)) 1e-4) "translated hit should preserve world x")
  (assert (< (math.abs (- hit.world-point.z 24)) 1e-4) "translated hit should preserve world z")
  (assert (< (math.abs (- hit.world-point.y 4.5)) 1e-4) "translated hit should include terrain position and sample height")
  (assert (= hit.sample.x 2) "translated hit should still resolve the correct local sample x")
  (assert (= hit.sample.z 2) "translated hit should still resolve the correct local sample z"))

(fn heightfield-raycast-detects-second-triangle-hit []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [1 1]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local hit
    (HeightfieldTerrainQuery.raycast-record record {:origin (glm.vec3 0.75 10 0.75)
                                                    :direction (glm.vec3 0 -1 0)}))
  (assert hit "raycast should hit points that land only on the cell's second triangle")
  (assert (< (math.abs (- hit.world-point.x 0.75)) 1e-4) "second-triangle hit should preserve x")
  (assert (< (math.abs (- hit.world-point.z 0.75)) 1e-4) "second-triangle hit should preserve z")
  (assert (< (math.abs hit.world-point.y) 1e-4) "second-triangle hit should land on the flat terrain"))

(fn heightfield-rect-target-between-local-points-builds-rect []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [2 2]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local start-hit
    (HeightfieldTerrainQuery.raycast-record record {:origin (glm.vec3 2 10 2)
                                                    :direction (glm.vec3 0 -1 0)}))
  (local end-hit
    (HeightfieldTerrainQuery.raycast-record record {:origin (glm.vec3 6 10 4)
                                                    :direction (glm.vec3 0 -1 0)}))
  (assert start-hit "expected start hit for terrain rect target test")
  (assert end-hit "expected end hit for terrain rect target test")
  (local target
    (HeightfieldTerrainQuery.rect-target-between-local-points record
                                                              start-hit.local-point
                                                              end-hit.local-point))
  (assert (= target.mode :samples) "rect-target-between-local-points should produce a sample target")
  (assert (= target.shape :rect) "rect-target-between-local-points should use the compact rectangular sample target")
  (assert (= target.x0 1) "rect target should use the smaller sample x")
  (assert (= target.z0 1) "rect target should use the smaller sample z")
  (assert (= target.x1 3) "rect target should use the larger sample x")
  (assert (= target.z1 2) "rect target should use the larger sample z"))

(fn heightfield-rect-target-between-local-points-respects-rebased-runtime-origin []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [1 1]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [-3 -3]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-2 -3]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-3 -2]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-2 -2]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local runtime-record
    (TerrainLayoutRecord.from-runtime-layout record
                                            {:position (glm.vec3 -12 0 -12)
                                             :rotation (glm.quat 1 0 0 0)}))
  (local target
    (HeightfieldTerrainQuery.rect-target-between-local-points runtime-record
                                                              (glm.vec3 1 0 2)
                                                              (glm.vec3 3 0 2)))
  (assert (= target.mode :samples) "rebased rect-target-between-local-points should produce a sample target")
  (assert (= target.shape :rect) "rebased rect-target-between-local-points should use the compact rectangular sample target")
  (assert (= target.sample-count 3) "rebased rect-target-between-local-points should preserve the dragged sample width")
  (assert (= target.x0 -11) "rebased rect-target-between-local-points should convert runtime local x back to canonical sample x")
  (assert (= target.z0 -10) "rebased rect-target-between-local-points should convert runtime local z back to canonical sample z")
  (assert (= target.x1 -9) "rebased rect-target-between-local-points should preserve the dragged canonical x range")
  (assert (= target.z1 -10) "rebased rect-target-between-local-points should preserve the dragged canonical z range"))

(fn heightfield-domain-hit-record-handles-nonflat-multi-chunk-terrain []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [2 2]
                                                :chunk-samples [3 3]}
                                      :chunks [{:coord [0 0]
                                                :size [3 3]
                                                :heights (make-heights 3 3 (fn [x z] (+ x (* z 0.5))))}
                                               {:coord [1 0]
                                                :size [3 3]
                                                :heights (make-heights 3 3 (fn [x z] (+ 5 x (* z 0.25))))}]}))
  (local ray {:origin (glm.vec3 4.5 20 2.5)
              :direction (glm.normalize (glm.vec3 0.05 -1.0 0.02))})
  (local (ok hit) (pcall (fn [] (HeightfieldTerrainQuery.domain-hit-record record ray))))
  (assert ok "domain-hit-record should not error on non-flat multi-chunk terrain")
  (assert hit "domain-hit-record should resolve a hit on non-flat multi-chunk terrain")
  (assert (= hit.target.mode :samples) "domain-hit-record should resolve a single-sample target"))

(fn heightfield-domain-hit-record-tolerates-sparse-chunk-gaps []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [2 2]
                                                :chunk-samples [3 3]}
                                      :chunks [{:coord [0 0]
                                                :size [3 3]
                                                :heights (make-heights 3 3 (fn [x z] (+ x z)))}
                                               {:coord [2 0]
                                                :size [3 3]
                                                :heights (make-heights 3 3 (fn [x z] (+ 10 x z)))}]}))
  (local ray {:origin (glm.vec3 6 20 2)
              :direction (glm.vec3 0 -1 0)})
  (local (ok hit) (pcall (fn [] (HeightfieldTerrainQuery.domain-hit-record record ray))))
  (assert ok "domain-hit-record should not error when the ray crosses a sparse chunk gap")
  (assert (= hit nil) "domain-hit-record should return nil when the ray lands in a gap"))

(fn project-world-point [point view projection viewport]
  (local viewport-vec (glm.vec4 viewport.x viewport.y viewport.width viewport.height))
  (local projected (glm.project point view projection viewport-vec))
  {:x projected.x
   :y (- (+ viewport.height viewport.y) projected.y)
   :z projected.z})

(fn heightfield-screen-rect-target-selects-samples-in-frustum []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [1 1]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local viewport {:x 0 :y 0 :width 100 :height 100})
  (local projection (glm.ortho 0.5 3.5 0.5 3.5 0.1 40.0))
  (local view (glm.lookAt (glm.vec3 2 10 2)
                          (glm.vec3 2 0 2)
                          (glm.vec3 0 0 -1)))
  (local top-left
    (project-world-point (HeightfieldTerrainQuery.local->world record (glm.vec3 1 0 1))
                         view
                         projection
                         viewport))
  (local bottom-right
    (project-world-point (HeightfieldTerrainQuery.local->world record (glm.vec3 3 0 3))
                         view
                         projection
                         viewport))
  (local target
    (HeightfieldTerrainQuery.screen-rect-target record
                                                {:x top-left.x :y top-left.y}
                                                {:x bottom-right.x :y bottom-right.y}
                                                {:view view
                                                 :projection projection
                                                 :viewport viewport}))
  (assert target "screen-rect-target should resolve a target for samples inside the drag frustum")
  (assert (= target.mode :samples))
  (assert (= target.shape :rect))
  (assert (= target.sample-count 9))
  (assert (= target.x0 1))
  (assert (= target.z0 1))
  (assert (= target.x1 3))
  (assert (= target.z1 3))
  (assert (= target.samples nil)))

(fn heightfield-screen-rect-target-respects-rebased-runtime-origin []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [1 1]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [-3 -3]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-2 -3]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-3 -2]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-2 -2]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local runtime-record
    (TerrainLayoutRecord.from-runtime-layout record
                                            {:position (glm.vec3 -12 0 -12)
                                             :rotation (glm.quat 1 0 0 0)}))
  (local viewport {:x 0 :y 0 :width 100 :height 100})
  (local projection (glm.ortho -11.5 -8.5 -11.5 -8.5 0.1 40.0))
  (local view (glm.lookAt (glm.vec3 -10 10 -10)
                          (glm.vec3 -10 0 -10)
                          (glm.vec3 0 0 -1)))
  (local top-left
    (project-world-point (HeightfieldTerrainQuery.local->world runtime-record (glm.vec3 1 0 2))
                         view
                         projection
                         viewport))
  (local bottom-right
    (project-world-point (HeightfieldTerrainQuery.local->world runtime-record (glm.vec3 3 0 2))
                         view
                         projection
                         viewport))
  (local target
    (HeightfieldTerrainQuery.screen-rect-target runtime-record
                                                {:x top-left.x :y top-left.y}
                                                {:x bottom-right.x :y bottom-right.y}
                                                {:view view
                                                 :projection projection
                                                 :viewport viewport}))
  (assert target "screen-rect-target should resolve a rebased runtime target")
  (assert (= target.mode :samples))
  (assert (= target.shape :rect))
  (assert (= target.sample-count 3))
  (assert (= target.x0 -11))
  (assert (= target.z0 -10))
  (assert (= target.x1 -9))
  (assert (= target.z1 -10))
  (assert (= target.samples nil)))

(fn heightfield-rectangularize-target-fills-bounding-rect []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:position [0 0 0]
                                                :rotation [1 0 0 0]
                                                :sample-spacing [1 1]
                                                :chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local target
    (HeightfieldTerrainData.rectangularize-target record
      {:mode :samples
       :samples [{:x 1 :z 1}
                 {:x 3 :z 3}]}))
  (assert target "rectangularize-target should return a target")
  (assert (= target.mode :samples))
  (assert (= target.shape :rect))
  (assert (= target.x0 1))
  (assert (= target.z0 1))
  (assert (= target.x1 3))
  (assert (= target.z1 3))
  (assert (= target.sample-count 9))
  (assert (= target.samples nil))
  (assert (= target.sample-lookup nil)))

(table.insert tests {:name "heightfield terrain query raycast hits flat terrain"
                     :fn heightfield-raycast-hits-flat-terrain})
(table.insert tests {:name "heightfield terrain query raycast respects transform"
                     :fn heightfield-raycast-respects-transform})
(table.insert tests {:name "heightfield terrain query raycast detects second triangle hit"
                     :fn heightfield-raycast-detects-second-triangle-hit})
(table.insert tests {:name "heightfield terrain query rect-target-between-local-points builds rect"
                     :fn heightfield-rect-target-between-local-points-builds-rect})
(table.insert tests {:name "heightfield terrain query rect-target-between-local-points respects rebased runtime origin"
                     :fn heightfield-rect-target-between-local-points-respects-rebased-runtime-origin})
(table.insert tests {:name "heightfield terrain query domain-hit handles non-flat multi-chunk terrain"
                     :fn heightfield-domain-hit-record-handles-nonflat-multi-chunk-terrain})
(table.insert tests {:name "heightfield terrain query domain-hit tolerates sparse chunk gaps"
                     :fn heightfield-domain-hit-record-tolerates-sparse-chunk-gaps})
(table.insert tests {:name "heightfield terrain query screen-rect target selects samples in frustum"
                     :fn heightfield-screen-rect-target-selects-samples-in-frustum})
(table.insert tests {:name "heightfield terrain query screen-rect target respects rebased runtime origin"
                     :fn heightfield-screen-rect-target-respects-rebased-runtime-origin})
(table.insert tests {:name "heightfield terrain query rectangularize target fills bounding rect"
                     :fn heightfield-rectangularize-target-fills-bounding-rect})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "terrain-query"
                       :tests tests})))

{:name "terrain-query"
 :tests tests
 :main main}
