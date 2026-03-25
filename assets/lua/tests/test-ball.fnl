(local glm (require :glm))
(local Ball (require :ball))
(local Sphere (require :sphere))
(local {: Layout} (require :layout))
(local bt (require :bt))
(local MathUtils (require :math-utils))

(local tests [])

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx []
  (local instanced-batches [])
  {:triangle-vector (make-vector-buffer)
   :instanced-color-mesh-batches instanced-batches
   :register-instanced-color-mesh-batch (fn [_self batch]
                                          (table.insert instanced-batches batch)
                                          batch)
   :unregister-instanced-color-mesh-batch (fn [_self batch]
                                            (for [idx 1 (length instanced-batches)]
                                              (when (= (. instanced-batches idx) batch)
                                                (table.remove instanced-batches idx)
                                                (lua "break")))
                                            nil)})

(local approx (. MathUtils :approx))

(fn vec-approx= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn ball-measure-matches-radius []
  (local builder (Ball {:radius 3
                        :position (glm.vec3 1 2 3)}))
  (local ball (builder (make-test-ctx)))

  (ball.layout:measurer)

  (assert (vec-approx= ball.layout.measure (glm.vec3 6 6 6)))

  (ball:drop))

(fn ball-accepts-custom-visual-builder []
  (local builder
    (Ball {:radius 3
           :position (glm.vec3 1 2 3)
           :visual (Sphere {:color (glm.vec4 1 0 0 1)
                            :size (glm.vec3 6 6 6)})}))
  (local ball (builder (make-test-ctx)))

  (ball.layout:measurer)

  (assert (vec-approx= ball.layout.measure (glm.vec3 6 6 6)))

  (ball:drop))

(fn ball-syncs-position-from-physics []
  (assert bt "Ball physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local builder (Ball {:radius 2
                            :position (glm.vec3 0 10 0)}))
  (local ball (builder (make-test-ctx)))
  (local root (Layout {:name "ball-root"}))

  (ball:ensure-body root)
  (local start-layout-y (or (and ball.layout ball.layout.position ball.layout.position.y) 0))

  (for [i 1 45]
    (app.engine.physics:update 0))
  (ball:sync root)

  (assert (< ball.layout.position.y start-layout-y)
          "Ball layout position did not move downward after physics update")

  (ball:drop))

(fn ball-syncs-rotation-from-physics []
  (assert bt "Ball physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")

  (local builder (Ball {:radius 2
                        :position (glm.vec3 0 10 0)}))
  (local ball (builder (make-test-ctx)))
  (local root (Layout {:name "ball-rotation-root"}))
  (local target-rotation (glm.quat (* 0.5 math.pi) (glm.vec3 0 1 0)))

  (ball:ensure-body root)

  (local transform (bt.Transform))
  (transform:setIdentity)
  (transform:setOrigin (bt.Vector3 0 10 0))
  (transform:setRotation (bt.Quaternion target-rotation.x
                                        target-rotation.y
                                        target-rotation.z
                                        target-rotation.w))
  (ball.body:setWorldTransform transform)
  (when ball.motion-state
    (ball.motion-state:setWorldTransform transform))

  (ball:sync root)

  (assert (approx ball.layout.rotation.w target-rotation.w)
          "Ball layout rotation w did not sync from Bullet body")
  (assert (approx ball.layout.rotation.x target-rotation.x)
          "Ball layout rotation x did not sync from Bullet body")
  (assert (approx ball.layout.rotation.y target-rotation.y)
          "Ball layout rotation y did not sync from Bullet body")
  (assert (approx ball.layout.rotation.z target-rotation.z)
          "Ball layout rotation z did not sync from Bullet body")

  (ball:drop))

(fn ball-applies-rigid-body-options []
  (assert bt "Ball physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")

  (local builder
    (Ball {:radius 2
           :position (glm.vec3 0 10 0)
           :mass 2.5
           :friction 0.95
           :rolling-friction 0.85
           :spinning-friction 0.75
           :restitution 0.15
           :linear-damping 0.11
           :angular-damping 0.22
           :linear-sleeping-threshold 0.33
           :angular-sleeping-threshold 0.44
           :additional-damping true
           :additional-damping-factor 0.55
           :additional-linear-damping-threshold-sqr 0.66
           :additional-angular-damping-threshold-sqr 0.77
           :additional-angular-damping-factor 0.88
           :initial-velocity (glm.vec3 1 2 3)
           :initial-angular-velocity (glm.vec3 4 5 6)
           :gravity (glm.vec3 0 -7 0)
           :linear-factor (glm.vec3 1 0 1)
           :angular-factor 0.5
           :anisotropic-friction (glm.vec3 1.0 0.5 0.25)
           :anisotropic-friction-mode bt.CF_ANISOTROPIC_ROLLING_FRICTION
           :contact-processing-threshold 1.25
           :contact-stiffness 10.0
           :contact-damping 0.75
           :ccd-motion-threshold 0.125
           :ccd-swept-sphere-radius 0.55
           :collision-flags bt.CF_CUSTOM_MATERIAL_CALLBACK
           :body-flags bt.BT_DISABLE_WORLD_GRAVITY
           :deactivation-time 2.5
           :activation-state bt.DISABLE_DEACTIVATION}))
  (local ball (builder (make-test-ctx)))
  (local root (Layout {:name "ball-options-root"}))

  (ball:ensure-body root)

  (assert (approx (ball.body:getMass) 2.5) "Ball should apply mass")
  (assert (approx (ball.body:getFriction) 0.95) "Ball should apply friction")
  (assert (approx (ball.body:getRollingFriction) 0.85) "Ball should apply rolling friction")
  (assert (approx (ball.body:getSpinningFriction) 0.75) "Ball should apply spinning friction")
  (assert (approx (ball.body:getRestitution) 0.15) "Ball should apply restitution")
  (assert (approx (ball.body:getLinearDamping) 0.11) "Ball should apply linear damping")
  (assert (approx (ball.body:getAngularDamping) 0.22) "Ball should apply angular damping")
  (assert (approx (ball.body:getLinearSleepingThreshold) 0.33) "Ball should apply linear sleeping threshold")
  (assert (approx (ball.body:getAngularSleepingThreshold) 0.44) "Ball should apply angular sleeping threshold")
  (assert (vec-approx= (ball.body:getLinearVelocity) (bt.Vector3 1 2 3)) "Ball should apply initial velocity")
  (assert (vec-approx= (ball.body:getAngularVelocity) (bt.Vector3 4 5 6)) "Ball should apply initial angular velocity")
  (assert (vec-approx= (ball.body:getGravity) (bt.Vector3 0 -7 0)) "Ball should apply gravity override")
  (assert (vec-approx= (ball.body:getLinearFactor) (bt.Vector3 1 0 1)) "Ball should apply linear factor")
  (assert (vec-approx= (ball.body:getAngularFactor) (bt.Vector3 0.5 0.5 0.5)) "Ball should apply angular factor")
  (assert (vec-approx= (ball.body:getAnisotropicFriction) (bt.Vector3 1.0 0.5 0.25)) "Ball should apply anisotropic friction")
  (assert (ball.body:hasAnisotropicFriction bt.CF_ANISOTROPIC_ROLLING_FRICTION)
          "Ball should apply anisotropic friction mode")
  (assert (approx (ball.body:getContactProcessingThreshold) 1.25) "Ball should apply contact processing threshold")
  (assert (approx (ball.body:getContactStiffness) 10.0) "Ball should apply contact stiffness")
  (assert (approx (ball.body:getContactDamping) 0.75) "Ball should apply contact damping")
  (assert (approx (ball.body:getCcdMotionThreshold) 0.125) "Ball should apply CCD motion threshold")
  (assert (approx (ball.body:getCcdSweptSphereRadius) 0.55) "Ball should apply CCD swept sphere radius")
  (assert (= (ball.body:getCollisionFlags) bt.CF_CUSTOM_MATERIAL_CALLBACK) "Ball should apply collision flags")
  (assert (= (ball.body:getFlags) bt.BT_DISABLE_WORLD_GRAVITY) "Ball should apply body flags")
  (assert (approx (ball.body:getDeactivationTime) 2.5) "Ball should apply deactivation time")
  (assert (= (ball.body:getActivationState) bt.DISABLE_DEACTIVATION) "Ball should apply activation state")

  (ball:drop))

(table.insert tests {:name "Ball measurer matches default size" :fn ball-measure-matches-radius})
(table.insert tests {:name "Ball accepts custom visual builder" :fn ball-accepts-custom-visual-builder})
(table.insert tests {:name "Ball sync updates from Bullet body" :fn ball-syncs-position-from-physics})
(table.insert tests {:name "Ball sync updates rotation from Bullet body" :fn ball-syncs-rotation-from-physics})
(table.insert tests {:name "Ball applies rigid-body tuning options" :fn ball-applies-rigid-body-options})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ball"
                       :tests tests})))

{:name "ball"
 :tests tests
 :main main}
