(local glm (require :glm))
(local bt (require :bt))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local {: LayoutRoot} (require :layout))
(local HeightfieldTerrain (require :heightfield-terrain))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local TerrainRecords (require :scene-terrain-records))

(local tests [])

(fn make-heights [width depth value-fn]
  (local heights [])
  (for [z 0 (- depth 1)]
    (for [x 0 (- width 1)]
      (table.insert heights (value-fn x z))))
  heights)

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

(table.insert tests {:name "Heightfield terrain record defaults normalize chunk data"
                     :fn record-defaults-normalize-heightfield-data})
(table.insert tests {:name "Heightfield terrain record accepts negative chunk coordinates"
                     :fn record-normalizes-negative-chunk-coordinates})
(table.insert tests {:name "Heightfield terrain perlin supports negative chunk coordinates"
                     :fn perlin-application-supports-negative-chunk-coordinates})
(table.insert tests {:name "Heightfield terrain uploads triangle buffer data"
                     :fn terrain-uploads-to-triangle-buffer})
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
