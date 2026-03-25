(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local Camera (require :camera))
(local Ball (require :ball))
(local HeightfieldTerrain (require :heightfield-terrain))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local JsonUtils (require :json-utils))
(local fixtures (require :tests/http-fixtures))
(local {: Layout} (require :layout))
(local TestSupport (require :tests/test-support))

(fn array->vec3 [arr]
  (glm.vec3 (. arr 1) (. arr 2) (. arr 3)))

(fn array->quat [arr]
  (glm.quat (. arr 1) (. arr 2) (. arr 3) (. arr 4)))

(fn first-home-world-path []
  (TestSupport.fixture-path "terrain-live-pick-world.json"))

(fn report-path []
  (TestSupport.fixture-path "heightfield-physics-support-grid.json"))

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

(fn random-range [min-value max-value]
  (+ min-value (* (math.random) (- max-value min-value))))

(fn make-ball-specs [terrain-record count]
  (local bounds (HeightfieldTerrainData.sample-bounds terrain-record))
  (local spacing (HeightfieldTerrainGrid.spacing terrain-record))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local terrain-position (array->vec3 terrain-record.options.position))
  (local terrain-rotation (array->quat terrain-record.options.rotation))
  (local margin 24.0)
  (local min-local-x (+ (* bounds.min-sample-x spacing-x) margin))
  (local max-local-x (- (* bounds.max-sample-x spacing-x) margin))
  (local min-local-z (+ (* bounds.min-sample-z spacing-z) margin))
  (local max-local-z (- (* bounds.max-sample-z spacing-z) margin))
  (local start-center-y 60.0)
  (local radius 4.5)
  (local specs [])
  (math.randomseed 424242)
  (for [idx 1 count]
    (local local-x (random-range min-local-x max-local-x))
    (local local-z (random-range min-local-z max-local-z))
    (local world-xz (+ terrain-position (terrain-rotation:rotate (glm.vec3 local-x 0 local-z))))
    (table.insert specs {:index idx
                         :radius radius
                         :local-x local-x
                         :local-z local-z
                         :world-x world-xz.x
                         :world-z world-xz.z
                         :start-center-y start-center-y}))
  specs)

(fn build-scene [ctx]
  (local fixture (fixtures.read-json (first-home-world-path)))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (assert terrain-record "Expected terrain fixture for support grid snapshot")
  (local terrain
    ((HeightfieldTerrain {:position (array->vec3 terrain-record.options.position)
                          :rotation (array->quat terrain-record.options.rotation)
                          :physics true
                          :sample-spacing terrain-record.options.sample-spacing
                          :chunk-samples terrain-record.options.chunk-samples
                          :chunks terrain-record.chunks})
     ctx))
  (local ball-specs (make-ball-specs terrain-record 48))
  (local balls [])
  (each [_ spec (ipairs ball-specs)]
    (local ball-radius spec.radius)
    (local start-center-y spec.start-center-y)
    (local ball
      ((Ball {:radius ball-radius
              :size (glm.vec3 (* ball-radius 2) (* ball-radius 2) (* ball-radius 2))
              :position (glm.vec3 (- spec.world-x ball-radius)
                                  (- start-center-y ball-radius)
                                  (- spec.world-z ball-radius))})
       ctx))
    (table.insert balls {:ball ball :spec spec}))

  (local children [terrain.layout])
  (each [_ entry (ipairs balls)]
    (table.insert children entry.ball.layout))

  (local root-layout
    (Layout {:name "heightfield-physics-support-grid-root"
             :children children
             :measurer (fn [self]
                         (terrain.layout:measurer)
                         (each [_ entry (ipairs balls)]
                           (entry.ball.layout:measurer))
                         (set self.measure (glm.vec3 960 220 960)))
             :layouter (fn [self]
                         (set self.size self.measure)
                         (set terrain.layout.size (or terrain.layout.measure self.measure))
                         (set terrain.layout.depth-offset-index self.depth-offset-index)
                         (set terrain.layout.clip-region self.clip-region)
                         (terrain.layout:layouter)
                         (each [i entry (ipairs balls)]
                           (local ball entry.ball)
                           (set ball.layout.size (or ball.layout.measure (glm.vec3 9 9 9)))
                           (set ball.layout.depth-offset-index (+ self.depth-offset-index (* i 0.001)))
                           (set ball.layout.clip-region self.clip-region)
                           (ball.layout:layouter)))}))

  {:layout root-layout
   :terrain terrain
   :terrain-record terrain-record
   :camera-state fixture.camera
   :balls balls
   :drop (fn [self]
           (self.layout:drop)
           (each [_ entry (ipairs balls)]
             (entry.ball:drop))
           (terrain:drop))})

(fn settle-balls! [entries steps]
  (each [_ entry (ipairs entries)]
    (entry.ball:ensure-body))
  (for [_ 1 steps]
    (app.engine.physics:update 0)
    (each [_ entry (ipairs entries)]
      (entry.ball:sync))))

(fn build-report [scene]
  (local terrain-record scene.terrain-record)
  (local terrain-position (array->vec3 terrain-record.options.position))
  (local terrain-rotation (array->quat terrain-record.options.rotation))
  (local inverse-rotation (terrain-rotation:inverse))
  (local entries [])
  (var under-terrain-count 0)
  (each [_ entry (ipairs scene.balls)]
    (local ball entry.ball)
    (local center (ball:center-from-layout))
    (local local-point (inverse-rotation:rotate (- center terrain-position)))
    (local terrain-y-local
      (terrain-surface-height-at-local-point terrain-record local-point.x local-point.z))
    (local terrain-y-world
      (if terrain-y-local
          (+ terrain-position.y terrain-y-local)
          nil))
    (local ball-bottom-y (- center.y entry.spec.radius))
    (local under-terrain?
      (and terrain-y-world (< ball-bottom-y terrain-y-world)))
    (when under-terrain?
      (set under-terrain-count (+ under-terrain-count 1)))
    (table.insert entries {:index entry.spec.index
                           :radius entry.spec.radius
                           :spawn-world-x entry.spec.world-x
                           :spawn-world-z entry.spec.world-z
                           :spawn-center-y entry.spec.start-center-y
                           :final-center [center.x center.y center.z]
                           :final-bottom-y ball-bottom-y
                           :terrain-surface-y terrain-y-world
                           :terrain-local [local-point.x local-point.y local-point.z]
                           :under-terrain (not (not under-terrain?))}))
  {:ball-count (length entries)
   :under-terrain-count under-terrain-count
   :entries entries})

(fn scene-projection [ctx]
  (glm.perspective 1.0 (/ ctx.width ctx.height) 0.1 5000.0))

(fn run [ctx]
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (var built nil)
  (local scene-target
    (Harness.make-scene-target
      {:builder (fn [child-ctx]
                  (set built (build-scene child-ctx))
                  built)
       :child-position (glm.vec3 480 110 0)
       :projection (scene-projection ctx)
       :view-matrix (camera:get-view-matrix)}))
  (assert built "heightfield physics support snapshot should build scene")
  (settle-balls! built.balls 540)
  (camera:set-rotation (array->quat built.camera-state.rotation))
  (camera:set-position
    (+ (array->vec3 built.camera-state.position)
       (camera.rotation:rotate (glm.vec3 120 0 180))))
  (set scene-target.view-matrix (camera:get-view-matrix))
  (local report (build-report built))
  (JsonUtils.write-json! (report-path) report)
  (Harness.draw-targets 1600 900 [{:target scene-target}])
  (Harness.capture-snapshot {:name "heightfield-physics-support-grid"
                             :width 1600
                             :height 900
                             :tolerance 2})
  (Harness.cleanup-target scene-target)
  (camera:drop)
  report)

(fn main []
  (Harness.with-app {:width 1600 :height 900}
                   (fn [ctx]
                     (local report (run ctx))
                     (print "heightfield-physics-support-grid report" report.under-terrain-count "/" report.ball-count)))
  (print "E2E heightfield physics support grid snapshot complete"))

{:run run
 :main main}
