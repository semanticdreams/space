(local glm (require :glm))
(local bt (require :bt))
(local HeightfieldTerrain (require :heightfield-terrain))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local fixtures (require :tests/http-fixtures))
(local TestSupport (require :tests/test-support))

(fn array->vec3 [arr]
  (glm.vec3 (. arr 1) (. arr 2) (. arr 3)))

(fn array->quat [arr]
  (glm.quat (. arr 1) (. arr 2) (. arr 3) (. arr 4)))

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

(fn first-home-world-path []
  (TestSupport.fixture-path "terrain-live-pick-world.json"))

(fn elevated-sample-centers [record]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local spacing (HeightfieldTerrainGrid.spacing record))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local chunk-map (HeightfieldTerrainGrid.build-chunk-map record))
  (local centers [])
  (for [sample-z bounds.min-sample-z (- bounds.max-sample-z 1)]
    (for [sample-x bounds.min-sample-x (- bounds.max-sample-x 1)]
      (local h00 (HeightfieldTerrainGrid.sample-height-global record chunk-map sample-x sample-z))
      (local h01 (HeightfieldTerrainGrid.sample-height-global record chunk-map sample-x (+ sample-z 1)))
      (local h10 (HeightfieldTerrainGrid.sample-height-global record chunk-map (+ sample-x 1) sample-z))
      (local h11 (HeightfieldTerrainGrid.sample-height-global record chunk-map (+ sample-x 1) (+ sample-z 1)))
      (when (and h00 h01 h10 h11)
        (local max-height (math.max h00 h01 h10 h11))
        (when (> max-height 1.0)
          (table.insert centers {:local-x (* (+ sample-x 0.5) spacing-x)
                                 :local-z (* (+ sample-z 0.5) spacing-z)
                                 :max-height max-height
                                 :sample-x sample-x
                                 :sample-z sample-z})))))
  centers)

(fn make-probe-body [center radius]
  (local transform (bt.Transform))
  (transform:setIdentity)
  (transform:setOrigin (bt.Vector3 center.x center.y center.z))
  (local motion (bt.DefaultMotionState transform))
  (local shape (bt.BoxShape (bt.Vector3 radius radius radius)))
  (local inertia (bt.Vector3 0 0 0))
  (shape:calculateLocalInertia 1.0 inertia)
  (local ci (bt.RigidBodyConstructionInfo 1.0 motion shape inertia))
  (local body (bt.RigidBody ci))
  (app.engine.physics:addRigidBody body)
  {:body body :shape shape :motion motion})

(fn drop-probe-body [probe]
  (when (and probe probe.body app.engine app.engine.physics)
    (app.engine.physics:removeRigidBody probe.body)))

(fn log-result [label payload]
  (print label payload))

(fn main []
  (assert bt "Bullet bindings required")
  (assert (and app.engine app.engine.physics) "Physics instance required")
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

  (local terrain-position (array->vec3 terrain-record.options.position))
  (local terrain-rotation (array->quat terrain-record.options.rotation))
  (local elevated-centers (elevated-sample-centers terrain-record))
  (local radius 3.0)
  (var found nil)

  (each [_ center (ipairs elevated-centers)]
    (when (= found nil)
      (local local-x center.local-x)
      (local local-z center.local-z)
      (local local-surface-y (terrain-surface-height-at-local-point terrain-record local-x local-z))
      (when local-surface-y
        (local world-xz (+ terrain-position (terrain-rotation:rotate (glm.vec3 local-x 0 local-z))))
        (local expected-surface-y (+ terrain-position.y local-surface-y))
        (local start-center (glm.vec3 world-xz.x (+ expected-surface-y radius 20.0) world-xz.z))
        (local probe (make-probe-body start-center radius))
        (for [_ 1 240]
          (app.engine.physics:update 0))
        (local final-transform (probe.body:getCenterOfMassTransform))
        (local origin (final-transform:getOrigin))
        (local final-center (glm.vec3 origin.x origin.y origin.z))
        (when (<= final-center.y (+ expected-surface-y radius -8.0))
          (set found {:sample-x center.sample-x
                      :sample-z center.sample-z
                      :max-height center.max-height
                      :local-x local-x
                      :local-z local-z
                      :expected-surface-y expected-surface-y
                      :final-center-y final-center.y
                      :world-x world-xz.x
                      :world-z world-xz.z}))
        (drop-probe-body probe))))

  (terrain:drop)

  (if found
      (do
        (log-result "FOUND_HEIGHTFIELD_SUPPORT_MISMATCH" found)
        (error "Found Bullet support mismatch"))
      (log-result "NO_HEIGHTFIELD_SUPPORT_MISMATCH_FOUND"
                  {:elevated-centers (length elevated-centers) :radius radius})))

{:main main}
