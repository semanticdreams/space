(local glm (require :glm))
(local bt (require :bt))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local {: LayoutRoot} (require :layout))
(local Signal (require :signal))
(local Scene (require :scene))
(local HeightfieldTerrain (require :heightfield-terrain))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local TerrainRecords (require :scene-terrain-records))
(local MathUtils (require :math-utils))
(local fixtures (require :tests/http-fixtures))
(local TestSupport (require :tests/test-support))

(local tests [])
(local approx (. MathUtils :approx))

(fn make-heights [width depth value-fn]
  (local heights [])
  (for [z 0 (- depth 1)]
    (for [x 0 (- width 1)]
      (table.insert heights (value-fn x z))))
  heights)

(fn first-home-world-path []
  (TestSupport.fixture-path "terrain-live-pick-world.json"))

(fn array->vec3 [arr]
  (glm.vec3 (. arr 1) (. arr 2) (. arr 3)))

(fn array->quat [arr]
  (glm.quat (. arr 1) (. arr 2) (. arr 3) (. arr 4)))

(fn vec3-approx= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn quat-approx= [a b]
  (and (approx a.w b.w)
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn model-origin [model]
  (local p (* model (glm.vec4 0 0 0 1)))
  (glm.vec3 p.x p.y p.z))

(fn with-scene [scene-opts f]
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (var scene nil)
  (local (ok result)
    (pcall
      (fn []
        (set scene (Scene scene-opts))
        (set app.scene scene)
        (set app.layout-root scene.layout-root)
        (f scene))))
  (when scene
    (scene:drop))
  (set app.scene original-scene)
  (set app.layout-root original-layout-root)
  (if ok
      result
      (error result)))

(fn terrain-layout-by-id [scene terrain-id]
  (var found nil)
  (each [_ metadata (ipairs (or scene.scene-terrains []))]
    (when (and (not found)
               metadata
               metadata.record
               (= metadata.record.id terrain-id))
      (set found (and metadata.element metadata.element.layout))))
  found)

(fn wait-for-terrain-layout-stable [scene terrain-id max-updates]
  (local updates (or max-updates 12))
  (var previous-position nil)
  (var previous-rotation nil)
  (var stable-layout nil)
  (for [_ 1 updates]
    (when (not stable-layout)
      (scene:update)
      (local layout (terrain-layout-by-id scene terrain-id))
      (when layout
        (if (and previous-position
                 previous-rotation
                 (vec3-approx= previous-position layout.position)
                 (quat-approx= previous-rotation layout.rotation))
            (set stable-layout layout)
            (do
              (set previous-position (glm.vec3 layout.position.x
                                               layout.position.y
                                               layout.position.z))
              (set previous-rotation (glm.quat layout.rotation.w
                                               layout.rotation.x
                                               layout.rotation.y
                                               layout.rotation.z)))))))
  (assert stable-layout "Expected terrain layout to stabilize")
  stable-layout)

(fn terrain-surface-height-at-local-point [record local-x local-z]
  (local spacing (HeightfieldTerrainGrid.spacing record))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local min-local-x (* bounds.min-sample-x spacing-x))
  (local min-local-z (* bounds.min-sample-z spacing-z))
  (local max-local-x (* bounds.max-sample-x spacing-x))
  (local max-local-z (* bounds.max-sample-z spacing-z))
  (if (or (< local-x min-local-x)
          (> local-x max-local-x)
          (< local-z min-local-z)
          (> local-z max-local-z))
      nil
      (do
        (local chunk-map (HeightfieldTerrainGrid.build-chunk-map record))
        (local cell-x (math.floor (/ local-x spacing-x)))
        (local cell-z (math.floor (/ local-z spacing-z)))
        (local h00 (HeightfieldTerrainGrid.sample-height-global record chunk-map cell-x cell-z))
        (local h01 (HeightfieldTerrainGrid.sample-height-global record chunk-map cell-x (+ cell-z 1)))
        (local h10 (HeightfieldTerrainGrid.sample-height-global record chunk-map (+ cell-x 1) cell-z))
        (local h11 (HeightfieldTerrainGrid.sample-height-global record chunk-map (+ cell-x 1) (+ cell-z 1)))
        (if (or (= h00 nil) (= h01 nil) (= h10 nil) (= h11 nil))
            nil
            (do
              (local local-u (/ (- local-x (* cell-x spacing-x)) spacing-x))
              (local local-v (/ (- local-z (* cell-z spacing-z)) spacing-z))
              (if (<= (+ local-u local-v) 1.0)
                  (+ (* h00 (- 1.0 local-u local-v))
                     (* h01 local-v)
                     (* h10 local-u))
                  (+ (* h10 (- 1.0 local-v))
                     (* h01 (- 1.0 local-u))
                     (* h11 (- (+ local-u local-v) 1.0)))))))))

(fn record-defaults-normalize-heightfield-data []
  (local record (TerrainRecords.default-record-for-kind "heightfield-terrain"))
  (assert (= record.kind "heightfield-terrain"))
  (assert (= (. record.options.chunk-samples 1) 17))
  (assert (= (. record.options.chunk-samples 2) 17))
  (assert (= (. record.options.sample-spacing 1) 20))
  (assert (= (. record.options.sample-spacing 2) 20))
  (assert (= (length record.chunks) 1))
    (local chunk (. record.chunks 1))
    (assert (= (. chunk.coord 1) 0))
    (assert (= (. chunk.coord 2) 0))
    (assert (= (length chunk.heights) (* 17 17))))

(fn record-normalizes-negative-chunk-coordinates []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :chunks [{:coord [-1 0]
                                                :size [17 17]}
                                               {:coord [0 -2]
                                                :size [17 17]}]}))
  (assert (= (length record.chunks) 2))
  (assert (= (. (. (. record.chunks 1) :coord) 1) -1))
  (assert (= (. (. (. record.chunks 2) :coord) 2) -2)))

(fn perlin-application-supports-negative-chunk-coordinates []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :chunks [{:coord [-1 0]
                                                :size [17 17]}
                                               {:coord [0 0]
                                                :size [17 17]}]}))
  (HeightfieldTerrainData.apply-perlin-record! record {:seed 99
                                                       :n1div 30
                                                       :n2div 4
                                                       :n3div 1
                                                       :n1scale 20
                                                       :n2scale 2
                                                       :n3scale 1
                                                       :zroot 2
                                                       :zpower 2.5})
  (local left-chunk (. record.chunks 1))
  (local right-chunk (. record.chunks 2))
  (assert (not (= (. left-chunk.heights 1) nil)))
  (assert (not (= (. right-chunk.heights 1) nil)))
  (assert (not (= (. left-chunk.heights 1) (. right-chunk.heights 1)))
          "negative chunk coordinates should still map to distinct perlin samples"))

(fn flat-fill-can-target-a_rectangle []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (HeightfieldTerrainData.fill-record! record 7.0 {:mode :rect
                                                   :x0 1
                                                   :z0 1
                                                   :x1 2
                                                   :z1 2})
  (local heights (. (. record.chunks 1) :heights))
  (assert (= (. heights 1) 0.0) "samples outside the rect should remain unchanged")
  (assert (= (. heights 7) 7.0) "rect fill should update sample [1,1]")
  (assert (= (. heights 8) 7.0) "rect fill should update sample [2,1]")
  (assert (= (. heights 12) 7.0) "rect fill should update sample [1,2]")
  (assert (= (. heights 13) 7.0) "rect fill should update sample [2,2]")
  (assert (= record.options.default-height 0.0)
          "rect fill should not rewrite default-height for future chunks"))

(fn perlin-application-can-target-a-rectangle []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (HeightfieldTerrainData.apply-perlin-record! record {:target {:mode :rect
                                                                :x0 1
                                                                :z0 1
                                                                :x1 3
                                                                :z1 3}
                                                       :seed 99
                                                       :n1div 30
                                                       :n2div 4
                                                       :n3div 1
                                                       :n1scale 20
                                                       :n2scale 2
                                                       :n3scale 1
                                                       :zroot 2
                                                       :zpower 2.5})
  (local heights (. (. record.chunks 1) :heights))
  (var changed-count 0)
  (each [idx value (ipairs heights)]
    (when (not (= value 0.0))
      (set changed-count (+ changed-count 1))))
  (assert (= (. heights 1) 0.0) "perlin rect should leave samples outside the target unchanged")
  (assert (> changed-count 0) "perlin rect should update at least one targeted sample")
  (assert (= record.options.default-height 0.0)
          "perlin rect should not rewrite default-height"))

(fn perlin-defaults-on-50x50-heightfield-produce-balanced-relief []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [50 50]}
                                      :chunks [{:coord [0 0]
                                                :size [50 50]
                                                :heights (make-heights 50 50 (fn [_x _z] 0.0))}]}))
  (HeightfieldTerrainData.apply-perlin-record! record {:seed 1337
                                                       :n1div 30
                                                       :n2div 4
                                                       :n3div 1
                                                       :n1scale 20
                                                       :n2scale 2
                                                       :n3scale 1
                                                       :zroot 2
                                                       :zpower 2.5})
  (local heights (. (. record.chunks 1) :heights))
  (local total (length heights))
  (var min-height math.huge)
  (var max-height (- math.huge))
  (each [_ value (ipairs heights)]
    (when (< value min-height)
      (set min-height value))
    (when (> value max-height)
      (set max-height value)))
  (local height-range (- max-height min-height))
  (local low-threshold (+ min-height (* height-range 0.25)))
  (local high-threshold (+ min-height (* height-range 0.75)))
  (var low-count 0)
  (var high-count 0)
  (each [_ value (ipairs heights)]
    (when (<= value low-threshold)
      (set low-count (+ low-count 1)))
    (when (>= value high-threshold)
      (set high-count (+ high-count 1))))
  (assert (>= height-range 20.0)
          "default perlin on a 50x50 heightfield should span at least 20 units of height")
  (assert (>= (/ low-count total) 0.2)
          "default perlin on a 50x50 heightfield should contain broad low areas near the terrain bottom")
  (assert (>= (/ high-count total) 0.08)
          "default perlin on a 50x50 heightfield should contain broad high areas far above the terrain bottom"))

(fn capture-record-preserves-heightfield-local-layout-transform []
  (local record
    (TerrainRecords.normalize-record {:id "terrain-a"
                                      :kind "heightfield-terrain"
                                      :options {:position [-600.3301 -100 199.9989]
                                                :rotation [-0.8660248517990112 0 -0.4999997019767761 0]
                                                :sample-spacing [20 20]
                                                :chunk-samples [5 5]
                                                :default-height 0.0}
                                      :chunks [{:coord [-2 -1]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-1 -1]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-2 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-1 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local canonical-position (array->vec3 record.options.position))
  (local rotation (array->quat record.options.rotation))
  (local captured
    (TerrainRecords.capture-record record {:position canonical-position
                                           :rotation rotation}))
  (local captured-position (array->vec3 captured.options.position))
  (local captured-rotation (array->quat captured.options.rotation))
  (assert (approx captured-position.x canonical-position.x))
  (assert (approx captured-position.y canonical-position.y))
  (assert (approx captured-position.z canonical-position.z))
  (assert (approx captured-rotation.w rotation.w))
  (assert (approx captured-rotation.x rotation.x))
  (assert (approx captured-rotation.y rotation.y))
  (assert (approx captured-rotation.z rotation.z)))

(fn capture-record-removes-parent-scene-transform []
  (local record
    (TerrainRecords.normalize-record {:id "terrain-a"
                                      :kind "heightfield-terrain"
                                      :options {:position [-600.3301 -100 199.9989]
                                                :rotation [-0.8660248517990112 0 -0.4999997019767761 0]
                                                :sample-spacing [20 20]
                                                :chunk-samples [5 5]
                                                :default-height 0.0}
                                      :chunks [{:coord [-2 -1]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-1 -1]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-2 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}
                                               {:coord [-1 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local local-position (array->vec3 record.options.position))
  (local local-rotation (array->quat record.options.rotation))
  (local parent-position (glm.vec3 -5 0 0))
  (local parent-rotation (glm.quat (math.rad 30) (glm.vec3 0 1 0)))
  (local world-layout-position (+ parent-position
                                  (parent-rotation:rotate local-position)))
  (local world-layout-rotation (* parent-rotation local-rotation))
  (local captured
    (TerrainRecords.capture-record record {:position world-layout-position
                                           :rotation world-layout-rotation
                                           :parent {:position parent-position
                                                    :rotation parent-rotation}}))
  (local captured-position (array->vec3 captured.options.position))
  (local captured-rotation (array->quat captured.options.rotation))
  (assert (approx captured-position.x local-position.x))
  (assert (approx captured-position.y local-position.y))
  (assert (approx captured-position.z local-position.z))
  (assert (approx captured-rotation.w local-rotation.w))
  (assert (approx captured-rotation.x local-rotation.x))
  (assert (approx captured-rotation.y local-rotation.y))
  (assert (approx captured-rotation.z local-rotation.z)))

(fn scene-heightfield-capture-remains-stable-across-rebuilds []
  (local original-record
    (TerrainRecords.normalize-record
      {:id "terrain-a"
       :kind "heightfield-terrain"
       :options {:position [-480 -100 -480]
                 :rotation [1 0 0 0]
                 :sample-spacing [20 20]
                 :chunk-samples [17 17]
                 :default-height 0.0}
       :chunks [{:coord [-1 -1]
                 :size [17 17]
                 :heights (make-heights 17 17 (fn [_x _z] 0.0))}
                {:coord [0 -1]
                 :size [17 17]
                 :heights (make-heights 17 17 (fn [x z]
                                                (if (and (>= x 8) (>= z 8))
                                                    12.0
                                                    0.0)))}
                {:coord [-1 0]
                 :size [17 17]
                 :heights (make-heights 17 17 (fn [x z]
                                                (if (and (<= x 4) (<= z 4))
                                                    7.0
                                                    0.0)))}
                {:coord [0 0]
                 :size [17 17]
                 :heights (make-heights 17 17 (fn [x z]
                                                (+ (* 0.5 x) (* 0.25 z))))}]}))
  (local scene-position (glm.vec3 25 0 -35))
  (local scene-rotation (glm.quat (math.rad 18) (glm.vec3 0 1 0)))
  (local captured0
    (with-scene
      {:position scene-position
       :rotation scene-rotation}
      (fn [scene]
        (scene:build-default {:terrains [original-record]})
        (local layout (wait-for-terrain-layout-stable scene original-record.id))
        (assert layout "Expected runtime terrain layout before capture")
        (scene:capture-state))))
  (local terrain0 (. captured0.terrains 1))
  (assert terrain0 "Expected captured terrain state")
  (assert (= terrain0.id original-record.id))
  (assert (vec3-approx= (array->vec3 terrain0.options.position)
                        (array->vec3 original-record.options.position)))
  (assert (quat-approx= (array->quat terrain0.options.rotation)
                        (array->quat original-record.options.rotation)))

  (var current captured0)
  (var baseline-layout-position nil)
  (var baseline-layout-rotation nil)
  (for [_cycle 1 3]
    (set current
         (with-scene
           {:position scene-position
            :rotation scene-rotation}
           (fn [scene]
             (scene:build-default {:terrains current.terrains})
             (local layout (wait-for-terrain-layout-stable scene original-record.id))
             (assert layout "Expected runtime terrain layout after rebuild")
             (if baseline-layout-position
                 (do
                   (assert (vec3-approx= baseline-layout-position layout.position)
                           "Terrain layout position should remain stable across capture/rebuild cycles")
                   (assert (quat-approx= baseline-layout-rotation layout.rotation)
                           "Terrain layout rotation should remain stable across capture/rebuild cycles"))
                 (do
                   (set baseline-layout-position
                        (glm.vec3 layout.position.x layout.position.y layout.position.z))
                   (set baseline-layout-rotation
                        (glm.quat layout.rotation.w layout.rotation.x layout.rotation.y layout.rotation.z))))
             (local captured (scene:capture-state))
             (local terrain (. captured.terrains 1))
             (assert terrain "Expected terrain in captured scene state")
             (assert (vec3-approx= (array->vec3 terrain.options.position)
                                   (array->vec3 original-record.options.position))
                     "Captured terrain position should stay canonical across rebuild cycles")
             (assert (quat-approx= (array->quat terrain.options.rotation)
                                   (array->quat original-record.options.rotation))
                     "Captured terrain rotation should stay canonical across rebuild cycles")
             captured)))))

(fn resize-preserves-overlapping-chunks-and-fills-new-ones []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]
                                                :default-height 0.0}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [x z] (+ x (* z 10))))}]}))
  (HeightfieldTerrainData.resize-record! record {:min-chunk-x -1
                                                 :min-chunk-z 0
                                                 :max-chunk-x 1
                                                 :max-chunk-z 0
                                                 :fill-height 3.5})
  (assert (= (length record.chunks) 3) "resize should create the requested chunk coverage")
  (local left (. record.chunks 1))
  (local center (. record.chunks 2))
  (local right (. record.chunks 3))
  (assert (= (. left.coord 1) -1) "resize should include new negative chunk coverage")
  (assert (= (. center.coord 1) 0) "resize should preserve overlapping chunk coordinates")
  (assert (= (. right.coord 1) 1) "resize should include new positive chunk coverage")
  (assert (= (. center.heights 1) 0) "resize should preserve overlapping chunk data")
  (assert (= (. center.heights 25) 44) "resize should preserve all overlapping chunk samples")
  (assert (= (. left.heights 1) 3.5) "resize should fill new chunks with the requested fill height")
  (assert (= (. right.heights 25) 3.5) "resize should fill every sample in new chunks")
  (assert (= record.options.default-height 3.5) "resize should update default-height for future chunks"))

(fn adjust-height-supports-rectangles-and-whole-terrain []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]
                                                :default-height 1.0}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 1.0))}]}))
  (HeightfieldTerrainData.adjust-record! record 2.0 {:mode :rect
                                                     :x0 1
                                                     :z0 1
                                                     :x1 2
                                                     :z1 2})
  (local heights (. (. record.chunks 1) :heights))
  (assert (= (. heights 1) 1.0) "adjust rect should leave outside samples unchanged")
  (assert (= (. heights 7) 3.0) "adjust rect should raise targeted samples")
  (assert (= record.options.default-height 1.0) "adjust rect should not rewrite default height")
  (HeightfieldTerrainData.adjust-record! record -1.5 {:mode :whole})
  (assert (= (. heights 1) -0.5) "whole adjust should affect every sample")
  (assert (= (. heights 7) 1.5) "whole adjust should apply on top of prior rect edits")
  (assert (= record.options.default-height -0.5) "whole adjust should update default height"))

(fn terrain-uploads-to-triangle-buffer []
  (var tracked 0)
  (var untracked 0)
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector
              :track-triangle-handle (fn [_self _handle _clip] (set tracked (+ tracked 1)))
              :untrack-triangle-handle (fn [_self _handle] (set untracked (+ untracked 1)))})
  (local builder
    (HeightfieldTerrain {:position (glm.vec3 0 -3 0)
                         :physics false
                         :sample-spacing [2 2]
                         :chunks [{:coord [0 0]
                                   :size [5 5]
                                   :heights (make-heights 5 5 (fn [x z] (+ (* x 0.2) (* z 0.3))))}]}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (root:update)

  (local vector-len (vector:length))
  (assert (> vector-len 0) "Heightfield terrain should upload triangle data")
  (local (dirty-from dirty-to) (vector:dirty-range))
  (assert (= dirty-from 0) "Heightfield terrain should dirty the vector from index zero")
  (assert (= dirty-to vector-len) "Heightfield terrain should dirty all uploaded data")
  (assert (> tracked 0) "Heightfield terrain should register a tracked triangle handle")

  (entity:drop)
  (assert (> untracked 0) "Heightfield terrain should untrack triangle handle on drop"))

(fn terrain-render-batch-follows-runtime-layout-transform []
  (var tracked-model nil)
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector
              :track-triangle-handle (fn [_self _handle _clip model]
                                       (set tracked-model model))
              :untrack-triangle-handle (fn [_self _handle] nil)})
  (local builder
    (HeightfieldTerrain {:position (glm.vec3 30 -12 45)
                         :physics false
                         :sample-spacing [2 2]
                         :chunks [{:coord [-3 -3]
                                   :size [3 3]
                                   :heights (make-heights 3 3 (fn [_x _z] 0.0))}
                                  {:coord [-2 -3]
                                   :size [3 3]
                                   :heights (make-heights 3 3 (fn [_x _z] 0.0))}
                                  {:coord [-3 -2]
                                   :size [3 3]
                                   :heights (make-heights 3 3 (fn [_x _z] 0.0))}
                                  {:coord [-2 -2]
                                   :size [3 3]
                                   :heights (make-heights 3 3 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (root:update)
  (assert tracked-model "Heightfield terrain should submit a tracked model matrix")
  (local origin (model-origin tracked-model))
  (assert (vec3-approx= origin entity.layout.position)
          (string.format
            "Heightfield terrain render batch origin should match layout position, got [%.3f, %.3f, %.3f] expected [%.3f, %.3f, %.3f]"
            origin.x
            origin.y
            origin.z
            entity.layout.position.x
            entity.layout.position.y
            entity.layout.position.z))
  (entity:drop))

(fn terrain-checker-pattern-alternates-across-chunk-seams []
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local builder
    (HeightfieldTerrain {:physics false
                         :sample-spacing [2 2]
                         :chunks [{:coord [0 0]
                                   :size [3 2]
                                   :heights (make-heights 3 2 (fn [_x _z] 0.0))}
                                  {:coord [1 0]
                                   :size [3 2]
                                   :heights (make-heights 3 2 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (local mesh entity.mesh)
  (local left-seam-color (. mesh.colors 7))
  (local right-seam-color (. mesh.colors 13))
  (assert left-seam-color "Expected a color for the last cell of the left chunk")
  (assert right-seam-color "Expected a color for the first cell of the right chunk")
  (assert (or (not (= left-seam-color.x right-seam-color.x))
              (not (= left-seam-color.y right-seam-color.y))
              (not (= left-seam-color.z right-seam-color.z)))
          "Checker pattern should alternate across chunk seams")
  (entity:drop))

(fn terrain-respects-array-rotation-from-record-data []
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local quarter-turn (glm.quat (/ math.pi 2) (glm.vec3 0 1 0)))
  (local builder
    (HeightfieldTerrain {:position [10 -4 20]
                         :rotation [quarter-turn.w quarter-turn.x quarter-turn.y quarter-turn.z]
                         :physics false
                         :sample-spacing [2 2]
                         :chunks [{:coord [-1 0]
                                   :size [3 2]
                                   :heights (make-heights 3 2 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (assert (< (math.abs (- entity.layout.rotation.w quarter-turn.w)) 1e-4)
          "heightfield runtime should preserve quaternion w from array rotation data")
  (assert (< (math.abs (- entity.layout.rotation.x quarter-turn.x)) 1e-4)
          "heightfield runtime should preserve quaternion x from array rotation data")
  (assert (< (math.abs (- entity.layout.rotation.y quarter-turn.y)) 1e-4)
          "heightfield runtime should preserve quaternion y from array rotation data")
  (assert (< (math.abs (- entity.layout.rotation.z quarter-turn.z)) 1e-4)
          "heightfield runtime should preserve quaternion z from array rotation data")
  (assert (< (math.abs (- entity.layout.position.x 10)) 1e-4)
          "heightfield runtime should rotate the origin offset into world x")
  (assert (< (math.abs (- entity.layout.position.z 24)) 1e-4)
          "heightfield runtime should rotate the origin offset into world z")
  (entity:drop))

(fn terrain-selection-overlay-follows-selection-target []
  (local original-themes app.themes)
  (set app.themes
       {:get-active-theme (fn []
                            {:terrain-selection {:fill (glm.vec4 0.2 0.5 0.9 0.2)
                                                 :border (glm.vec4 0.2 0.5 0.9 0.95)}})})
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local builder
    (HeightfieldTerrain {:physics false
                         :sample-spacing [2 2]
                         :chunk-samples [5 5]
                         :chunks [{:coord [0 0]
                                   :size [5 5]
                                   :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (root:update)
  (local base-length (vector:length))
  (entity:set-selection-target {:mode :rect
                                :x0 1
                                :z0 1
                                :x1 3
                                :z1 3})
  (root:update)
  (local selected-length (vector:length))
  (assert (> selected-length base-length)
          "terrain selection should add overlay triangles above the terrain mesh")
  (local target (entity:get-selection-target))
  (assert (= target.x0 1))
  (assert (= target.z1 3))
  (entity:set-selection-target {:mode :rect
                                :x0 0
                                :z0 0
                                :x1 1
                                :z1 1})
  (root:update)
  (local updated-target (entity:get-selection-target))
  (assert (= updated-target.x0 0)
          "setting terrain selection again should replace the stored target")
  (entity:clear-selection-target)
  (assert (= (entity:get-selection-target) nil)
          "terrain selection should clear the stored target")
  (entity:drop)
  (set app.themes original-themes))

(fn terrain-selection-overlay-reacts-to-theme-changes []
  (local original-themes app.themes)
  (local original-engine app.engine)
  (var current-fill (glm.vec4 0.2 0.5 0.9 0.2))
  (var current-border (glm.vec4 0.2 0.5 0.9 0.95))
  (set app.themes
       {:get-active-theme (fn []
                            {:terrain-selection {:fill current-fill
                                                 :border current-border}})})
  (set app.engine {:events {:updated (Signal)}})
  (local handle-state {:next-handle 1
                       :writes {}})
  (local vector
    {:allocate (fn [self size]
                 (local handle {:id handle-state.next-handle :size size})
                 (set handle-state.next-handle (+ handle-state.next-handle 1))
                 handle)
     :reallocate (fn [_self handle size]
                   (set handle.size size))
     :delete (fn [_self _handle] nil)
     :set-glm-vec3 (fn [_self _handle _offset _value] nil)
     :set-float (fn [_self _handle _offset _value] nil)
     :set-glm-vec4 (fn [_self handle offset value]
                     (local key (.. handle.id ":" offset))
                     (set (. handle-state.writes key)
                          [value.x value.y value.z value.w]))})
  (local ctx {:triangle-vector vector})
  (local builder
    (HeightfieldTerrain {:physics false
                         :sample-spacing [2 2]
                         :chunk-samples [5 5]
                         :chunks [{:coord [0 0]
                                   :size [5 5]
                                   :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (entity:set-selection-target {:mode :rect
                                :x0 1
                                :z0 1
                                :x1 2
                                :z1 2})
  (root:update)
  (local first-color (. handle-state.writes "2:3"))
  (assert first-color "selection overlay should write fill colors for its fill handle")
  (set current-fill (glm.vec4 0.85 0.25 0.18 0.33))
  (set current-border (glm.vec4 0.9 0.3 0.2 0.98))
  (app.engine.events.updated:emit 0.016)
  (root:update)
  (local changed-color (. handle-state.writes "2:3"))
  (assert changed-color "selection overlay should still write fill colors after theme change")
  (assert (not (= (. first-color 1) (. changed-color 1)))
          "selection overlay fill should update when the active theme changes")
  (entity:drop)
  (set app.engine original-engine)
  (set app.themes original-themes))

(fn heightfield-physics-catches-falling-body []
  (assert bt "Heightfield terrain physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local terrain-builder
    (HeightfieldTerrain {:position (glm.vec3 0 -4 0)
                         :physics true
                         :sample-spacing [2 2]
                         :chunks [{:coord [0 0]
                                   :size [17 17]
                                   :heights (make-heights 17 17 (fn [_x _z] 0.0))}]}))
  (local terrain (terrain-builder ctx))

  (local start-height 18.0)
  (var fall-body nil)

  (fn cleanup []
    (when fall-body
      (app.engine.physics:removeRigidBody fall-body)
      (set fall-body nil))
    (terrain:drop))

  (local result
    (table.pack
      (pcall
        (fn []
          (local fall-shape (bt.BoxShape (bt.Vector3 1 1 1)))
          (local fall-transform (bt.Transform))
          (fall-transform:setIdentity)
          (fall-transform:setOrigin (bt.Vector3 8 start-height 8))
          (local fall-motion (bt.DefaultMotionState fall-transform))
          (local inertia (bt.Vector3 0 0 0))
          (fall-shape:calculateLocalInertia 1.0 inertia)
          (local fall-ci (bt.RigidBodyConstructionInfo 1.0 fall-motion fall-shape inertia))
          (set fall-body (bt.RigidBody fall-ci))
          (app.engine.physics:addRigidBody fall-body)

          (for [_ 1 180]
            (app.engine.physics:update 0))

          (local final-transform (fall-body:getCenterOfMassTransform))
          (local origin (final-transform:getOrigin))
          (assert (< origin.y start-height) "Body should move downward under gravity")
          (assert (> origin.y -20) "Body fell through heightfield terrain")))))
  (local ok (. result 1))
  (local err (. result 2))
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-physics-catches-falling-body-on-raised-area []
  (assert bt "Raised heightfield terrain physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local heights [0 0 0 0 0
                  0 8 8 8 0
                  0 8 8 8 0
                  0 8 8 8 0
                  0 0 0 0 0])
  (local terrain-builder
    (HeightfieldTerrain {:position (glm.vec3 0 -100 0)
                         :physics true
                         :sample-spacing [20 20]
                         :chunk-samples [5 5]
                         :chunks [{:coord [0 0]
                                   :size [5 5]
                                   :heights heights}]}))
  (local terrain (terrain-builder ctx))

  (local start-height -40.0)
  (var fall-body nil)

  (fn cleanup []
    (when fall-body
      (app.engine.physics:removeRigidBody fall-body)
      (set fall-body nil))
    (terrain:drop))

  (local result
    (table.pack
      (pcall
        (fn []
          (local fall-shape (bt.BoxShape (bt.Vector3 1 1 1)))
          (local fall-transform (bt.Transform))
          (fall-transform:setIdentity)
          (fall-transform:setOrigin (bt.Vector3 40 start-height 40))
          (local fall-motion (bt.DefaultMotionState fall-transform))
          (local inertia (bt.Vector3 0 0 0))
          (fall-shape:calculateLocalInertia 1.0 inertia)
          (local fall-ci (bt.RigidBodyConstructionInfo 1.0 fall-motion fall-shape inertia))
          (set fall-body (bt.RigidBody fall-ci))
          (app.engine.physics:addRigidBody fall-body)

          (for [_ 1 240]
            (app.engine.physics:update 0))

          (local final-transform (fall-body:getCenterOfMassTransform))
          (local origin (final-transform:getOrigin))
          (assert (< origin.y start-height) "Body should move downward under gravity")
          (assert (> origin.y -96)
                  (string.format
                    "Body should collide with raised terrain instead of falling to the base (center_y=%.3f)"
                    origin.y))))))
  (local ok (. result 1))
  (local err (. result 2))
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-physics-searches-live-3x3-support-mismatch []
  (assert bt "Live 3x3 search test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local fixture (fixtures.read-json (TestSupport.fixture-path "terrain-live-pick-world.json")))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (assert terrain-record "Expected terrain in live fixture")

  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local terrain-builder
    (HeightfieldTerrain {:position (array->vec3 terrain-record.options.position)
                         :rotation (array->quat terrain-record.options.rotation)
                         :physics true
                         :sample-spacing terrain-record.options.sample-spacing
                         :chunk-samples terrain-record.options.chunk-samples
                         :chunks terrain-record.chunks}))
  (local terrain (terrain-builder ctx))

  (local bounds (HeightfieldTerrainData.sample-bounds terrain-record))
  (local spacing (HeightfieldTerrainGrid.spacing terrain-record))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local chunk-samples (HeightfieldTerrainGrid.chunk-samples terrain-record))
  (local terrain-position (array->vec3 terrain-record.options.position))
  (local terrain-rotation (array->quat terrain-record.options.rotation))
  (local min-local-x (+ (* bounds.min-sample-x spacing-x) 15.0))
  (local max-local-x (- (* bounds.max-sample-x spacing-x) 15.0))
  (local min-local-z (+ (* bounds.min-sample-z spacing-z) 15.0))
  (local max-local-z (- (* bounds.max-sample-z spacing-z) 15.0))
  (local radius 9.0)
  (var first-mismatch nil)
  (var fall-body nil)

  (fn clear-fall-body []
    (when fall-body
      (app.engine.physics:removeRigidBody fall-body)
      (set fall-body nil)))

  (fn cleanup []
    (clear-fall-body)
    (terrain:drop))

  (fn run-probe! [local-x local-z]
    (when (= first-mismatch nil)
      (clear-fall-body)
      (local local-surface-y
        (terrain-surface-height-at-local-point terrain-record local-x local-z))
      (when local-surface-y
        (local world-xz
          (+ terrain-position (terrain-rotation:rotate (glm.vec3 local-x 0 local-z))))
        (local expected-surface-y (+ terrain-position.y local-surface-y))
        (local fall-shape (bt.BoxShape (bt.Vector3 radius radius radius)))
        (local fall-transform (bt.Transform))
        (fall-transform:setIdentity)
        (fall-transform:setOrigin (bt.Vector3 world-xz.x
                                             (+ expected-surface-y radius 30.0)
                                             world-xz.z))
        (local fall-motion (bt.DefaultMotionState fall-transform))
        (local inertia (bt.Vector3 0 0 0))
        (fall-shape:calculateLocalInertia 1.0 inertia)
        (local fall-ci (bt.RigidBodyConstructionInfo 1.0 fall-motion fall-shape inertia))
        (set fall-body (bt.RigidBody fall-ci))
        (app.engine.physics:addRigidBody fall-body)
        (for [_ 1 240]
          (app.engine.physics:update 0))
        (local final-transform (fall-body:getCenterOfMassTransform))
        (local origin (final-transform:getOrigin))
        (when (<= origin.y (+ expected-surface-y radius -12.0))
          (set first-mismatch {:local-x local-x
                               :local-z local-z
                               :expected-surface-y expected-surface-y
                               :final-center-y origin.y
                               :world-x world-xz.x
                               :world-z world-xz.z})))))

  (local result
    (table.pack
      (pcall
        (fn []
          (for [probe-z 0 12]
            (for [probe-x 0 12]
              (when (= first-mismatch nil)
                (local local-x
                  (+ min-local-x
                     (* (/ probe-x 12.0)
                        (- max-local-x min-local-x))))
                (local local-z
                  (+ min-local-z
                     (* (/ probe-z 12.0)
                        (- max-local-z min-local-z))))
                (run-probe! local-x local-z))))
          (for [seam-sample-x (+ bounds.min-sample-x (- (. chunk-samples 1) 1))
                              (- bounds.max-sample-x (- (. chunk-samples 1) 1))
                              (- (. chunk-samples 1) 1)]
            (local seam-local-x (* seam-sample-x spacing-x))
            (each [_ x-offset (ipairs [-3.0 -1.0 1.0 3.0])]
              (for [probe-z 0 24]
                (local local-z
                  (+ min-local-z
                     (* (/ probe-z 24.0)
                        (- max-local-z min-local-z))))
                (run-probe! (+ seam-local-x x-offset) local-z))))
          (for [seam-sample-z (+ bounds.min-sample-z (- (. chunk-samples 2) 1))
                              (- bounds.max-sample-z (- (. chunk-samples 2) 1))
                              (- (. chunk-samples 2) 1)]
            (local seam-local-z (* seam-sample-z spacing-z))
            (each [_ z-offset (ipairs [-3.0 -1.0 1.0 3.0])]
              (for [probe-x 0 24]
                (local local-x
                  (+ min-local-x
                     (* (/ probe-x 24.0)
                        (- max-local-x min-local-x))))
                (run-probe! local-x (+ seam-local-z z-offset))))))
          (assert (= first-mismatch nil)
                  (if first-mismatch
                      (string.format
                        "Found live 3x3 Bullet support mismatch local=(%.3f, %.3f) expected_surface_y=%.3f final_center_y=%.3f world=(%.3f, %.3f)"
                        first-mismatch.local-x
                        first-mismatch.local-z
                        first-mismatch.expected-surface-y
                        first-mismatch.final-center-y
                        first-mismatch.world-x
                        first-mismatch.world-z)
                      "Unexpected mismatch state")))))
  (local ok (. result 1))
  (local err (. result 2))
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-physics-finds-first-home-world-elevated-support-mismatch []
  (assert bt "First home world support test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local fixture (fixtures.read-json (first-home-world-path)))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (assert terrain-record "Expected terrain in first home world")

  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local terrain-builder
    (HeightfieldTerrain {:position (array->vec3 terrain-record.options.position)
                         :rotation (array->quat terrain-record.options.rotation)
                         :physics true
                         :sample-spacing terrain-record.options.sample-spacing
                         :chunk-samples terrain-record.options.chunk-samples
                         :chunks terrain-record.chunks}))
  (local terrain (terrain-builder ctx))

  (local bounds (HeightfieldTerrainData.sample-bounds terrain-record))
  (local spacing (HeightfieldTerrainGrid.spacing terrain-record))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local chunk-map (HeightfieldTerrainGrid.build-chunk-map terrain-record))
  (local terrain-position (array->vec3 terrain-record.options.position))
  (local terrain-rotation (array->quat terrain-record.options.rotation))
  (local radius 3.0)
  (var first-mismatch nil)
  (var fall-body nil)

  (fn clear-fall-body []
    (when fall-body
      (app.engine.physics:removeRigidBody fall-body)
      (set fall-body nil)))

  (fn cleanup []
    (clear-fall-body)
    (terrain:drop))

  (fn run-probe! [sample-x sample-z max-height]
    (when (= first-mismatch nil)
      (clear-fall-body)
      (local local-x (* (+ sample-x 0.5) spacing-x))
      (local local-z (* (+ sample-z 0.5) spacing-z))
      (local local-surface-y
        (terrain-surface-height-at-local-point terrain-record local-x local-z))
      (when local-surface-y
        (local world-xz
          (+ terrain-position (terrain-rotation:rotate (glm.vec3 local-x 0 local-z))))
        (local expected-surface-y (+ terrain-position.y local-surface-y))
        (local fall-shape (bt.BoxShape (bt.Vector3 radius radius radius)))
        (local fall-transform (bt.Transform))
        (fall-transform:setIdentity)
        (fall-transform:setOrigin (bt.Vector3 world-xz.x
                                             (+ expected-surface-y radius 20.0)
                                             world-xz.z))
        (local fall-motion (bt.DefaultMotionState fall-transform))
        (local inertia (bt.Vector3 0 0 0))
        (fall-shape:calculateLocalInertia 1.0 inertia)
        (local fall-ci (bt.RigidBodyConstructionInfo 1.0 fall-motion fall-shape inertia))
        (set fall-body (bt.RigidBody fall-ci))
        (app.engine.physics:addRigidBody fall-body)
        (for [_ 1 240]
          (app.engine.physics:update 0))
        (local final-transform (fall-body:getCenterOfMassTransform))
        (local origin (final-transform:getOrigin))
        (when (<= origin.y (+ expected-surface-y radius -8.0))
          (set first-mismatch {:sample-x sample-x
                               :sample-z sample-z
                               :max-height max-height
                               :local-x local-x
                               :local-z local-z
                               :expected-surface-y expected-surface-y
                               :final-center-y origin.y
                               :world-x world-xz.x
                               :world-z world-xz.z})))))

  (local result
    (table.pack
      (pcall
        (fn []
          (for [sample-z bounds.min-sample-z (- bounds.max-sample-z 1)]
            (for [sample-x bounds.min-sample-x (- bounds.max-sample-x 1)]
              (when (= first-mismatch nil)
                (local h00 (HeightfieldTerrainGrid.sample-height-global terrain-record chunk-map sample-x sample-z))
                (local h01 (HeightfieldTerrainGrid.sample-height-global terrain-record chunk-map sample-x (+ sample-z 1)))
                (local h10 (HeightfieldTerrainGrid.sample-height-global terrain-record chunk-map (+ sample-x 1) sample-z))
                (local h11 (HeightfieldTerrainGrid.sample-height-global terrain-record chunk-map (+ sample-x 1) (+ sample-z 1)))
                (when (and h00 h01 h10 h11)
                  (local max-height (math.max h00 h01 h10 h11))
                  (when (> max-height 1.0)
                    (run-probe! sample-x sample-z max-height)))))))
          (assert (= first-mismatch nil)
                  (if first-mismatch
                      (string.format
                        "First home world elevated Bullet support mismatch sample=(%d,%d) max_height=%.3f local=(%.3f, %.3f) expected_surface_y=%.3f final_center_y=%.3f world=(%.3f, %.3f)"
                        first-mismatch.sample-x
                        first-mismatch.sample-z
                        first-mismatch.max-height
                        first-mismatch.local-x
                        first-mismatch.local-z
                        first-mismatch.expected-surface-y
                        first-mismatch.final-center-y
                        first-mismatch.world-x
                        first-mismatch.world-z)
                      "Unexpected mismatch state")))))
  (local ok (. result 1))
  (local err (. result 2))
  (cleanup)
  (when (not ok)
    (error err)))

(table.insert tests {:name "Heightfield terrain record defaults normalize chunk data"
                     :fn record-defaults-normalize-heightfield-data})
(table.insert tests {:name "Heightfield terrain record accepts negative chunk coordinates"
                     :fn record-normalizes-negative-chunk-coordinates})
(table.insert tests {:name "Heightfield terrain perlin supports negative chunk coordinates"
                     :fn perlin-application-supports-negative-chunk-coordinates})
(table.insert tests {:name "Heightfield terrain flat fill supports rectangular targets"
                     :fn flat-fill-can-target-a_rectangle})
(table.insert tests {:name "Heightfield terrain perlin supports rectangular targets"
                     :fn perlin-application-can-target-a-rectangle})
(table.insert tests {:name "Heightfield terrain default perlin on 50x50 produces balanced relief"
                     :fn perlin-defaults-on-50x50-heightfield-produce-balanced-relief})
(table.insert tests {:name "Heightfield terrain capture preserves local layout transform"
                     :fn capture-record-preserves-heightfield-local-layout-transform})
(table.insert tests {:name "Heightfield terrain capture removes parent scene transform"
                     :fn capture-record-removes-parent-scene-transform})
(table.insert tests {:name "Heightfield terrain scene capture remains stable across rebuilds"
                     :fn scene-heightfield-capture-remains-stable-across-rebuilds})
(table.insert tests {:name "Heightfield terrain resize preserves overlap and fills new chunks"
                     :fn resize-preserves-overlapping-chunks-and-fills-new-ones})
(table.insert tests {:name "Heightfield terrain adjust supports rectangles and whole terrain"
                     :fn adjust-height-supports-rectangles-and-whole-terrain})
(table.insert tests {:name "Heightfield terrain uploads triangle buffer data"
                     :fn terrain-uploads-to-triangle-buffer})
(table.insert tests {:name "Heightfield terrain render batch follows runtime layout transform"
                     :fn terrain-render-batch-follows-runtime-layout-transform})
(table.insert tests {:name "Heightfield terrain checker pattern alternates across chunk seams"
                     :fn terrain-checker-pattern-alternates-across-chunk-seams})
(table.insert tests {:name "Heightfield terrain physics catches falling body on raised area"
                     :fn heightfield-physics-catches-falling-body-on-raised-area})
(table.insert tests {:name "Heightfield terrain searches live 3x3 support mismatch"
                     :fn heightfield-physics-searches-live-3x3-support-mismatch})
(table.insert tests {:name "Heightfield terrain first home world elevated support mismatch"
                     :fn heightfield-physics-finds-first-home-world-elevated-support-mismatch})
(table.insert tests {:name "Heightfield terrain respects array rotation from record data"
                     :fn terrain-respects-array-rotation-from-record-data})
(table.insert tests {:name "Heightfield terrain selection overlay follows selection target"
                     :fn terrain-selection-overlay-follows-selection-target})
(table.insert tests {:name "Heightfield terrain selection overlay reacts to theme changes"
                     :fn terrain-selection-overlay-reacts-to-theme-changes})
(table.insert tests {:name "Heightfield terrain integrates with Bullet physics"
                     :fn heightfield-physics-catches-falling-body})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "heightfield-terrain"
                       :tests tests})))

{:name "heightfield-terrain"
 :tests tests
 :main main}
