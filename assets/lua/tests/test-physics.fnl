(local tests [])

(local bt (require :bt))

(fn approx= [a b]
  (< (math.abs (- a b)) 0.0001))

(fn assert-vec3= [actual expected message]
  (assert (approx= actual.x expected.x) (.. message " x"))
  (assert (approx= actual.y expected.y) (.. message " y"))
  (assert (approx= actual.z expected.z) (.. message " z")))

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

(fn physics-bindings-expose-rigid-body-controls []
  (assert bt "Physics bindings require the bt module")
  (assert (= bt.ACTIVE_TAG 1) "ACTIVE_TAG constant should be exposed")
  (assert (= bt.CF_CUSTOM_MATERIAL_CALLBACK 8) "Collision flags should be exposed")
  (assert (= bt.CF_ANISOTROPIC_ROLLING_FRICTION 2) "Anisotropic friction flags should be exposed")

  (local shape (bt.SphereShape 2.0))
  (shape:setLocalScaling (bt.Vector3 1.2 1.3 1.4))
  (assert-vec3= (shape:getLocalScaling) (bt.Vector3 1.2 1.3 1.4) "Sphere shape scaling should round-trip")

  (local inertia (bt.Vector3 0 0 0))
  (shape:calculateLocalInertia 3.0 inertia)
  (assert (> inertia.x 0) "Sphere shape should calculate local inertia")

  (local transform (bt.Transform))
  (transform:setIdentity)
  (transform:setOrigin (bt.Vector3 4 5 6))
  (local motion (bt.DefaultMotionState transform))
  (local info (bt.RigidBodyConstructionInfo 3.0 motion shape inertia))
  (set info.m-linearDamping 0.1)
  (set info.m-angularDamping 0.2)
  (set info.m-friction 0.9)
  (set info.m-rollingFriction 0.8)
  (set info.m-spinningFriction 0.7)
  (set info.m-restitution 0.3)
  (set info.m-linearSleepingThreshold 0.4)
  (set info.m-angularSleepingThreshold 0.5)
  (set info.m-additionalDamping true)
  (set info.m-additionalDampingFactor 0.6)
  (assert (approx= info.m-linearDamping 0.1) "Construction info should expose linear damping")
  (assert (approx= info.m-angularDamping 0.2) "Construction info should expose angular damping")
  (assert (approx= info.m-friction 0.9) "Construction info should expose friction")
  (assert (approx= info.m-rollingFriction 0.8) "Construction info should expose rolling friction")
  (assert (approx= info.m-spinningFriction 0.7) "Construction info should expose spinning friction")
  (assert (approx= info.m-restitution 0.3) "Construction info should expose restitution")
  (assert info.m-additionalDamping "Construction info should expose additional damping")
  (assert (approx= info.m-additionalDampingFactor 0.6) "Construction info should expose additional damping factor")

  (local body (bt.RigidBody info))
  (assert (not (body:isInWorld)) "Fresh rigid body should not be in a world yet")
  (assert (approx= (body:getMass) 3.0) "Rigid body should expose mass")
  (assert (approx= (body:getInvMass) (/ 1 3.0)) "Rigid body should expose inverse mass")

  (body:setGravity (bt.Vector3 0 -5 0))
  (assert-vec3= (body:getGravity) (bt.Vector3 0 -5 0) "Rigid body gravity should round-trip")

  (body:setDamping 0.11 0.22)
  (assert (approx= (body:getLinearDamping) 0.11) "Rigid body should expose linear damping")
  (assert (approx= (body:getAngularDamping) 0.22) "Rigid body should expose angular damping")

  (body:setSleepingThresholds 0.33 0.44)
  (assert (approx= (body:getLinearSleepingThreshold) 0.33) "Rigid body should expose linear sleeping threshold")
  (assert (approx= (body:getAngularSleepingThreshold) 0.44) "Rigid body should expose angular sleeping threshold")

  (body:setLinearFactor (bt.Vector3 1 0 1))
  (assert-vec3= (body:getLinearFactor) (bt.Vector3 1 0 1) "Rigid body should expose linear factor")

  (body:setAngularFactor (bt.Vector3 0 1 0))
  (assert-vec3= (body:getAngularFactor) (bt.Vector3 0 1 0) "Rigid body should expose angular factor vector overload")
  (body:setAngularFactor 0.5)
  (assert-vec3= (body:getAngularFactor) (bt.Vector3 0.5 0.5 0.5) "Rigid body should expose angular factor scalar overload")

  (body:setFriction 0.91)
  (body:setRollingFriction 0.81)
  (body:setSpinningFriction 0.71)
  (body:setRestitution 0.31)
  (assert (approx= (body:getFriction) 0.91) "Rigid body should expose friction")
  (assert (approx= (body:getRollingFriction) 0.81) "Rigid body should expose rolling friction")
  (assert (approx= (body:getSpinningFriction) 0.71) "Rigid body should expose spinning friction")
  (assert (approx= (body:getRestitution) 0.31) "Rigid body should expose restitution")

  (body:setContactProcessingThreshold 1.25)
  (body:setContactStiffnessAndDamping 10.0 0.75)
  (assert (approx= (body:getContactProcessingThreshold) 1.25) "Rigid body should expose contact processing threshold")
  (assert (approx= (body:getContactStiffness) 10.0) "Rigid body should expose contact stiffness")
  (assert (approx= (body:getContactDamping) 0.75) "Rigid body should expose contact damping")

  (body:setCcdMotionThreshold 0.125)
  (body:setCcdSweptSphereRadius 0.55)
  (assert (approx= (body:getCcdMotionThreshold) 0.125) "Rigid body should expose CCD motion threshold")
  (assert (approx= (body:getCcdSweptSphereRadius) 0.55) "Rigid body should expose CCD swept sphere radius")

  (body:setAnisotropicFriction (bt.Vector3 1.0 0.5 0.25) bt.CF_ANISOTROPIC_ROLLING_FRICTION)
  (assert-vec3= (body:getAnisotropicFriction) (bt.Vector3 1.0 0.5 0.25) "Rigid body should expose anisotropic friction")
  (assert (body:hasAnisotropicFriction bt.CF_ANISOTROPIC_ROLLING_FRICTION)
          "Rigid body should expose anisotropic rolling friction mode")

  (body:setCollisionFlags bt.CF_CUSTOM_MATERIAL_CALLBACK)
  (assert (= (body:getCollisionFlags) bt.CF_CUSTOM_MATERIAL_CALLBACK) "Rigid body should expose collision flags")

  (body:setUserIndex 11)
  (body:setUserIndex2 12)
  (body:setUserIndex3 13)
  (assert (= (body:getUserIndex) 11) "Rigid body should expose user index")
  (assert (= (body:getUserIndex2) 12) "Rigid body should expose user index 2")
  (assert (= (body:getUserIndex3) 13) "Rigid body should expose user index 3")

  (body:setDeactivationTime 2.5)
  (assert (approx= (body:getDeactivationTime) 2.5) "Rigid body should expose deactivation time")

  (body:setLinearVelocity (bt.Vector3 1 2 3))
  (body:setAngularVelocity (bt.Vector3 4 5 6))
  (assert-vec3= (body:getLinearVelocity) (bt.Vector3 1 2 3) "Rigid body should expose linear velocity")
  (assert-vec3= (body:getAngularVelocity) (bt.Vector3 4 5 6) "Rigid body should expose angular velocity")
  (assert-vec3= (body:getVelocityInLocalPoint (bt.Vector3 0 1 0)) (bt.Vector3 -5 2 7)
                "Rigid body should expose velocity at local point")

  (body:applyCentralForce (bt.Vector3 2 3 4))
  (body:applyTorque (bt.Vector3 5 6 7))
  (assert-vec3= (body:getTotalForce) (bt.Vector3 2 0 4) "Rigid body should expose accumulated force with linear factor")
  (assert-vec3= (body:getTotalTorque) (bt.Vector3 2.5 3.0 3.5) "Rigid body should expose accumulated torque with angular factor")
  (body:clearForces)
  (assert-vec3= (body:getTotalForce) (bt.Vector3 0 0 0) "Rigid body should clear accumulated force")
  (assert-vec3= (body:getTotalTorque) (bt.Vector3 0 0 0) "Rigid body should clear accumulated torque")

  (body:translate (bt.Vector3 1 2 3))
  (assert-vec3= (body:getCenterOfMassPosition) (bt.Vector3 5 7 9) "Rigid body should expose translation")

  (body:forceActivationState bt.ACTIVE_TAG)
  (assert (= (body:getActivationState) bt.ACTIVE_TAG) "Rigid body should expose activation state")
  (assert (body:isActive) "Rigid body should report active state"))

(table.insert tests {:name "Physics updates rigid bodies via Bullet bindings"
                     :fn physics-bindings-step})

(table.insert tests {:name "Physics exposes Bullet rigid-body tuning controls"
                     :fn physics-bindings-expose-rigid-body-controls})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "physics"
                       :tests tests})))

{:name "physics"
 :tests tests
 :main main}
