(local glm (require :glm))
(local bt (require :bt))

(fn bt-glm-vec3 [value]
  (assert value "PhysicsPointGrab requires bt.Vector3 value")
  (glm.vec3 value.x value.y value.z))

(fn glm-bt-vec3 [value]
  (assert value "PhysicsPointGrab requires glm vec3 value")
  (bt.Vector3 value.x value.y value.z))

(fn bt-quat->glm-quat [rotation]
  (assert rotation "PhysicsPointGrab requires bt.Quaternion value")
  (glm.quat (rotation:w)
            (rotation:x)
            (rotation:y)
            (rotation:z)))

(fn local-pivot-from-hit [body hit-point]
  (assert body "PhysicsPointGrab.local-pivot-from-hit requires body")
  (assert body.getCenterOfMassTransform
          "PhysicsPointGrab.local-pivot-from-hit requires body:getCenterOfMassTransform")
  (assert hit-point "PhysicsPointGrab.local-pivot-from-hit requires hit-point")
  (local transform (body:getCenterOfMassTransform))
  (local origin (bt-glm-vec3 (transform:getOrigin)))
  (local rotation (bt-quat->glm-quat (transform:getRotation)))
  (local inverse (rotation:inverse))
  (local local-point (inverse:rotate (- hit-point origin)))
  (glm-bt-vec3 local-point))

(fn create [opts]
  (local options (or opts {}))
  (local physics (assert options.physics "PhysicsPointGrab.create requires :physics"))
  (local body (assert options.body "PhysicsPointGrab.create requires :body"))
  (local hit-point (assert options.hit-point "PhysicsPointGrab.create requires :hit-point"))
  (assert bt.Point2PointConstraint "PhysicsPointGrab.create requires bt.Point2PointConstraint")
  (assert physics.addConstraint "PhysicsPointGrab.create requires physics:addConstraint")
  (assert physics.removeConstraint "PhysicsPointGrab.create requires physics:removeConstraint")
  (local pivot-a (local-pivot-from-hit body hit-point))
  (local constraint (bt.Point2PointConstraint body pivot-a))
  (constraint:setPivotB (glm-bt-vec3 hit-point))
  (constraint:setTau (or options.tau 0.3))
  (constraint:setDamping (or options.damping 1.0))
  (constraint:setImpulseClamp (or options.impulse-clamp 30.0))
  (physics:addConstraint constraint true)
  (when body.activate
    (body:activate true))
  (var active? true)
  {:constraint constraint
   :update-target (fn [_self world-point]
                    (assert world-point "PhysicsPointGrab.update-target requires worldPoint")
                    (assert active? "PhysicsPointGrab.update-target requires an active session")
                    (constraint:setPivotB (glm-bt-vec3 world-point))
                    (when body.activate
                      (body:activate true))
                    true)
   :destroy (fn [_self]
              (when active?
                (physics:removeConstraint constraint)
                (set active? false))
              true)
   :active? (fn [_self]
              active?)})

{:local-pivot-from-hit local-pivot-from-hit
 :create create}
