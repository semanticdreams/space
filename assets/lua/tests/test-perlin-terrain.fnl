(local glm (require :glm))
(local bt (require :bt))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local {: LayoutRoot} (require :layout))
(local native (require :perlin-terrain-native))
(local PerlinTerrain (require :perlin-terrain))

(local tests [])

(fn native-mesh-is-deterministic []
  (local a (native.PerlinTerrainMesh {:width 12 :length 11 :seed 77}))
  (local b (native.PerlinTerrainMesh {:width 12 :length 11 :seed 77}))
  (local c (native.PerlinTerrainMesh {:width 12 :length 11 :seed 78}))
  (local sample-a (a:point-height 3 4))
  (local sample-b (b:point-height 3 4))
  (local sample-c (c:point-height 3 4))

  (assert (= sample-a sample-b) "Perlin mesh with same seed must match")
  (assert (not (= sample-a sample-c)) "Perlin mesh with different seed should differ")
  (assert (= (a:triangle-count) (* 2 (- 12 1) (- 11 1))))
  (assert (= (a:vertex-count) (* 3 (a:triangle-count))))
  (assert (= (a:float-count) (* 8 (a:vertex-count))))
  (assert (<= (a:min-height) (a:max-height))
          "Perlin mesh min height must not exceed max height"))

(fn terrain-uploads-to-triangle-buffer []
  (var tracked 0)
  (var untracked 0)
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector
              :track-triangle-handle (fn [_self _handle _clip] (set tracked (+ tracked 1)))
              :untrack-triangle-handle (fn [_self _handle] (set untracked (+ untracked 1)))})
  (local builder (PerlinTerrain {:width 8
                                 :length 8
                                 :seed 11
                                 :scale (glm.vec3 2 1 2)
                                 :position (glm.vec3 0 -3 0)
                                 :physics false}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (root:update)

  (local vector-len (vector:length))
  (assert (> vector-len 0) "Perlin terrain should upload triangle data")
  (local (dirty-from dirty-to) (vector:dirty-range))
  (assert (= dirty-from 0) "Perlin terrain should dirty the vector from index zero")
  (assert (= dirty-to vector-len) "Perlin terrain should dirty all uploaded data")
  (assert (> tracked 0) "Perlin terrain should register a tracked triangle handle")

  (entity:drop)
  (assert (> untracked 0) "Perlin terrain should untrack triangle handle on drop"))

(fn perlin-physics-catches-falling-body []
  (assert bt "Perlin terrain physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local terrain-builder (PerlinTerrain {:width 18
                                         :length 18
                                         :seed 7
                                         :scale (glm.vec3 2 1.5 2)
                                         :position (glm.vec3 0 -4 0)
                                         :physics true}))
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
          (fall-transform:setOrigin (bt.Vector3 0 start-height 0))
          (local fall-motion (bt.DefaultMotionState fall-transform))
          (local inertia (bt.Vector3 0 0 0))
          (fall-shape:calculateLocalInertia 1.0 inertia)
          (local fall-ci (bt.RigidBodyConstructionInfo 1.0 fall-motion fall-shape inertia))
          (set fall-body (bt.RigidBody fall-ci))
          (app.engine.physics:addRigidBody fall-body)

          (for [i 1 180]
            (app.engine.physics:update 0))

          (local final-transform (fall-body:getCenterOfMassTransform))
          (local origin (final-transform:getOrigin))
          (assert (< origin.y start-height) "Body should move downward under gravity")
          (assert (> origin.y -40) "Body fell through Perlin terrain")))))
  (local ok (. result 1))
  (local err (. result 2))
  (cleanup)
  (when (not ok)
    (error err)))

(table.insert tests {:name "Perlin native mesh is deterministic"
                     :fn native-mesh-is-deterministic})
(table.insert tests {:name "Perlin terrain uploads triangle buffer data"
                     :fn terrain-uploads-to-triangle-buffer})
(table.insert tests {:name "Perlin terrain integrates with Bullet physics"
                     :fn perlin-physics-catches-falling-body})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "perlin-terrain"
                       :tests tests})))

{:name "perlin-terrain"
 :tests tests
 :main main}
