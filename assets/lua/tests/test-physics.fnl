(local tests [])

(local bt (require :bt))
(fn physics-bindings-step []
  (assert bt "Physics bindings require the bt module")
  (assert (and app.engine app.engine.physics) "Physics instance not available")

  (app.engine.physics:setGravity 0 -10 0)

  (local start-height 5.0)
  (var ground-body nil)
  (var fall-body nil)
  (var final-y nil)

  (fn cleanup []
    (when fall-body
      (app.engine.physics:removeRigidBody fall-body)
      (set fall-body nil))
    (when ground-body
      (app.engine.physics:removeRigidBody ground-body)
      (set ground-body nil)))

  (local result
    (table.pack
      (pcall
        (fn []
          (local ground-shape (bt.StaticPlaneShape (bt.Vector3 0 1 0) 0))
          (local ground-transform (bt.Transform))
          (ground-transform:setIdentity)
          (local ground-motion (bt.DefaultMotionState ground-transform))
          (local zero (bt.Vector3 0 0 0))
          (local ground-ci (bt.RigidBodyConstructionInfo 0 ground-motion ground-shape zero))
          (set ground-body (bt.RigidBody ground-ci))
          (app.engine.physics:addRigidBody ground-body)

          (local fall-shape (bt.BoxShape (bt.Vector3 1 1 1)))
          (local fall-transform (bt.Transform))
          (fall-transform:setIdentity)
          (fall-transform:setOrigin (bt.Vector3 0 start-height 0))
          (local fall-motion (bt.DefaultMotionState fall-transform))
          (local fall-inertia (bt.Vector3 0 0 0))
          (fall-shape:calculateLocalInertia 1.0 fall-inertia)
          (local fall-ci (bt.RigidBodyConstructionInfo 1.0 fall-motion fall-shape fall-inertia))
          (set fall-body (bt.RigidBody fall-ci))
          (app.engine.physics:addRigidBody fall-body)

          (for [i 1 120]
            (app.engine.physics:update 0))

          (local final-transform (fall-body:getCenterOfMassTransform))
          (local origin (final-transform:getOrigin))
          (set final-y origin.y)))))
  (local ok (. result 1))
  (local err (. result 2))

  (cleanup)
  (when (not ok)
    (error err))

  (assert final-y "Rigid body did not report a position")
  (assert (< final-y start-height) "Gravity did not reduce the body's height")
  (assert (> final-y 0) "Body fell through the ground plane"))

(table.insert tests {:name "Physics updates rigid bodies via Bullet bindings"
                     :fn physics-bindings-step})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "physics"
                       :tests tests})))

{:name "physics"
 :tests tests
 :main main}
