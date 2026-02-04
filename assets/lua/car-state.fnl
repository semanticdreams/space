(local glm (require :glm))
(local StateBase (require :state-base))
(local InputState (require :input-state-router))
(local bt (require :bt))
(local Utils (require :car-state-utils))
(local physics-available? (. Utils :physics-available?))
(local vec3-zero (. Utils :vec3-zero))
(local quat-identity (. Utils :quat-identity))
(local copy-glm-vec3! (. Utils :copy-glm-vec3!))
(local copy-glm-quat! (. Utils :copy-glm-quat!))
(local bt-glm-vec3 (. Utils :bt-glm-vec3))
(local bt-glm-quat (. Utils :bt-glm-quat))
(local quat-from-bt (. Utils :quat-from-bt))
(local parent-transform (. Utils :parent-transform))
(local car-world-transform (. Utils :car-world-transform))
(local offset-from-physics (. Utils :offset-from-physics))
(local wheel-lateral-offset (. Utils :wheel-lateral-offset))
(local find-car (. Utils :find-car))

(local KEY
  {:forward (string.byte "w")
   :backward (string.byte "s")
   :left (string.byte "a")
   :right (string.byte "d")
   :brake 32
   :reset (string.byte "r")})

(local SDLK_ESCAPE 27)

(local default-mass 1200.0)
(local default-engine-force 2200.0)
(local default-brake-force 180.0)
(local max-steer 0.6)
(local steer-step 0.04)
(local suspension-rest-scale 0.55)


(fn CarState []
  (local state {:vehicle nil
                :chassis nil
                :chassis-shape nil
                :chassis-motion nil
                :gc-protect []
                :raycaster nil
                :tuning nil
                :ground nil
                :offset nil
                :rotation nil
                :half-size (vec3-zero)
                :car nil
                :host nil
                :initial-center nil
                :initial-rotation nil
                :forward-sign -1.0
                :front-wheels []
                :rear-wheels []
                :keys {}
                :steer 0.0
                :engine-force default-engine-force
                :brake-force default-brake-force})

  (fn has-car? []
    (and state.host state.car state.offset state.rotation))

  (fn resolve-car []
    (set state.host (or state.host (find-car)))
    (set state.car (or state.car (and state.host state.host.car)))
    (set state.offset (or state.offset (and state.host state.host.car-offset)))
    (set state.rotation (or state.rotation (and state.host state.host.car-rotation)))
    (local bounds (and state.car state.car.bounds))
    (when (and bounds bounds.size)
      (copy-glm-vec3! state.half-size
                  (glm.vec3 (* bounds.size.x 0.5)
                        (* bounds.size.y 0.5)
                        (* bounds.size.z 0.5)))))

  (fn cleanup-ground []
    (when (and state.ground physics-available? state.ground.body)
      (app.engine.physics:removeRigidBody state.ground.body))
    (set state.ground nil))

  (fn cleanup-vehicle []
    (when (and state.vehicle (physics-available?))
      (app.engine.physics:removeAction state.vehicle))
    (when (and state.chassis (physics-available?))
      (app.engine.physics:removeRigidBody state.chassis))
    (set state.vehicle nil)
    (set state.chassis nil)
    (set state.raycaster nil)
    (set state.tuning nil)
    (set state.chassis-shape nil)
    (set state.chassis-motion nil))

  (fn keep-alive [object]
    (when object
      (table.insert state.gc-protect object)))

  (fn reset-layout-dirt []
    (when (and state.host state.host.layout)
      (state.host.layout:mark-layout-dirty)))

  (fn sync-layout-from-transform [transform]
    (when (and transform state.offset state.rotation)
      (local origin (transform:getOrigin))
      (local rotation (transform:getRotation))
      (local parent (parent-transform (and state.host state.host.layout.parent)))
      (local world-center (glm.vec3 origin.x origin.y origin.z))
      (local world-rotation (quat-from-bt rotation))
      (local local-rotation (* (parent.rotation:inverse) world-rotation))
      (local offset (offset-from-physics parent world-center local-rotation state.half-size))
      (copy-glm-vec3! state.offset offset)
      (copy-glm-quat! state.rotation local-rotation)
      (reset-layout-dirt)))

  (fn capture-initial-transform []
    (when (has-car?)
      (local parent (parent-transform (and state.host state.host.layout.parent)))
      (local current (car-world-transform parent state.offset state.rotation state.half-size))
      (set state.initial-center current.center)
      (set state.initial-rotation current.rotation)))

  (fn create-ground []
    (when (and (physics-available?) (not state.ground))
      (local shape (bt.StaticPlaneShape (bt.Vector3 0 1 0) 0))
      (local transform (bt.Transform))
      (transform:setIdentity)
      (local motion (bt.DefaultMotionState transform))
      (local zero (bt.Vector3 0 0 0))
      (local info (bt.RigidBodyConstructionInfo 0 motion shape zero))
      (local body (bt.RigidBody info))
      (app.engine.physics:addRigidBody body)
      (keep-alive shape)
      (keep-alive motion)
      (keep-alive body)
      (set state.ground {:shape shape
                         :motion motion
                         :body body})))

	  (fn apply-tuning [tuning wheel-radius]
	    (when tuning
	      (set tuning.m-suspensionStiffness 20.0)
	      (set tuning.m-suspensionCompression 4.0)
	      (set tuning.m-suspensionDamping 2.3)
	      (set tuning.m-frictionSlip 1.2)
	      (set tuning.m-maxSuspensionTravelCm 500.0)
	      (set tuning.m-maxSuspensionForce 6000.0)
	      (when wheel-radius
	        (set tuning.m-maxSuspensionTravelCm (* 200.0 wheel-radius)))))

  (fn create-vehicle []
    (resolve-car)
    (when (and (physics-available?) (has-car?) (not state.vehicle))
      (app.engine.physics:setGravity 0 -25 0)
      (create-ground)
      (local parent (parent-transform (and state.host state.host.layout.parent)))
      (local current (car-world-transform parent state.offset state.rotation state.half-size))
      (local shape (bt.BoxShape (bt-glm-vec3 state.half-size)))
      (local transform (bt.Transform))
      (transform:setIdentity)
      (transform:setOrigin (bt-glm-vec3 current.center))
      (transform:setRotation (bt-glm-quat current.rotation))
      (local motion (bt.DefaultMotionState transform))
      (local inertia (bt.Vector3 0 0 0))
      (shape:calculateLocalInertia default-mass inertia)
      (local info (bt.RigidBodyConstructionInfo default-mass motion shape inertia))
      (local body (bt.RigidBody info))
      (body:setFriction 1.2)
      (body:setRollingFriction 0.4)

      (local world (app.engine.physics:getWorld))
      (local raycaster (bt.DefaultVehicleRaycaster world))
      (local tuning (bt.VehicleTuning))
      (apply-tuning tuning (or (and state.car state.car.mesh state.car.mesh.wheel-radius)
                               state.half-size.y))
      (local vehicle (bt.RaycastVehicle tuning body raycaster))
      (vehicle:setCoordinateSystem 2 1 0)

      (local mesh (and state.car state.car.mesh))
      (local wheel-radius (or (and mesh mesh.wheel-radius) state.half-size.y))
      (local wheel-width (or (and mesh mesh.wheel-width) (math.max 0.4 (* 0.1 state.half-size.z 2))))
      (local wheel-height (or (and mesh mesh.wheel-height) wheel-radius))
      (local front-axle (or (and mesh mesh.front-axle) (* 0.35 state.half-size.x 2)))
      (local rear-axle (or (and mesh mesh.rear-axle) (* 0.65 state.half-size.x 2)))
      (local half-length state.half-size.x)
      (local front-x (- front-axle half-length))
      (local rear-x (- rear-axle half-length))
      (local lateral (wheel-lateral-offset state.half-size wheel-width))
      (local wheel-dir (bt.Vector3 0 -1 0))
      (local wheel-axle (bt.Vector3 0 0 1))
      (local rest-length (* suspension-rest-scale wheel-radius))

      (vehicle:addWheel (bt.Vector3 front-x wheel-height (- lateral))
                        wheel-dir wheel-axle rest-length wheel-radius tuning true)
      (vehicle:addWheel (bt.Vector3 front-x wheel-height lateral)
                        wheel-dir wheel-axle rest-length wheel-radius tuning true)
      (vehicle:addWheel (bt.Vector3 rear-x wheel-height (- lateral))
                        wheel-dir wheel-axle rest-length wheel-radius tuning false)
      (vehicle:addWheel (bt.Vector3 rear-x wheel-height lateral)
                        wheel-dir wheel-axle rest-length wheel-radius tuning false)

      (app.engine.physics:addRigidBody body)
      (app.engine.physics:addAction vehicle)

      (set state.vehicle vehicle)
      (set state.chassis body)
      (set state.chassis-shape shape)
      (set state.chassis-motion motion)
      (set state.raycaster raycaster)
      (set state.tuning tuning)
      (keep-alive vehicle)
      (keep-alive body)
      (keep-alive shape)
      (keep-alive motion)
      (keep-alive raycaster)
      (keep-alive tuning)
      (set state.front-wheels [0 1])
      (set state.rear-wheels [2 3])
      (capture-initial-transform)))

  (fn reset-vehicle []
    (when (and state.vehicle state.chassis state.initial-center state.initial-rotation)
      (local transform (bt.Transform))
      (transform:setIdentity)
      (transform:setOrigin (bt-glm-vec3 state.initial-center))
      (transform:setRotation (bt-glm-quat state.initial-rotation))
      (state.chassis:setWorldTransform transform)
      (state.chassis:setLinearVelocity (bt.Vector3 0 0 0))
      (state.chassis:setAngularVelocity (bt.Vector3 0 0 0))
      (state.vehicle:resetSuspension)
      (for [i 0 (- (state.vehicle:getNumWheels) 1)]
        (state.vehicle:updateWheelTransform i true))
      (sync-layout-from-transform transform)))

  (fn apply-controls [_self]
    (when state.vehicle
      (local forward? (. state.keys KEY.forward))
      (local backward? (. state.keys KEY.backward))
      (local brake? (. state.keys KEY.brake))
      (local reset? (. state.keys KEY.reset))
      (local steer-left? (. state.keys KEY.left))
      (local steer-right? (. state.keys KEY.right))
      (when reset?
        (reset-vehicle))

      (var target-steer 0.0)
      (when steer-left?
        (set target-steer (- max-steer)))
      (when steer-right?
        (set target-steer max-steer))
      (local current-steer (or state.steer 0.0))
      (local delta (- target-steer current-steer))
      (if (< (math.abs delta) steer-step)
          (set state.steer target-steer)
          (set state.steer (+ current-steer (* steer-step (if (< delta 0) -1 1)))))

      (var engine 0.0)
      (when forward?
        (set engine (* state.forward-sign state.engine-force)))
      (when backward?
        (set engine state.engine-force))

      (local brake-force (if brake? state.brake-force 0.0))
      (for [i 0 (- (state.vehicle:getNumWheels) 1)]
        (state.vehicle:applyEngineForce engine i)
        (state.vehicle:setBrake brake-force i)
        (when (or (= i 0) (= i 1))
          (state.vehicle:setSteeringValue state.steer i)))))

  (fn update-layout-from-physics []
    (when (and state.vehicle state.vehicle.getChassisWorldTransform)
      (local transform (state.vehicle:getChassisWorldTransform))
      (sync-layout-from-transform transform)))

  (fn on-key-down [_self payload]
    (local key (and payload payload.key))
    (if (= key SDLK_ESCAPE)
        (do
          (when (and app.engine app.states app.states.set-state)
            (app.states.set-state :normal))
          (set state.keys {})
          (reset-vehicle)
          (reset-layout-dirt)
          true)
        (do
          (when key
            (set (. state.keys key) true))
          true)))

  (fn on-key-up [_self payload]
    (local key (and payload payload.key))
    (when key
      (set (. state.keys key) nil))
    true)

  (fn on-enter []
    (resolve-car)
    (create-vehicle)
    (capture-initial-transform))

  (fn on-leave []
    (set state.keys {})
    (cleanup-vehicle)
    (cleanup-ground))

  (fn on-updated [_self delta]
    (apply-controls nil)
    (update-layout-from-physics))

  (local result
    (StateBase.make-state {:name :car
                           :on-enter on-enter
                           :on-leave on-leave
                           :on-key-down on-key-down
                           :on-key-up on-key-up
                           :on-updated on-updated}))
  (set result.on-updated on-updated)
  (set result.__car_state state)
  result)

(local module {:new CarState
               :KEY KEY})
(setmetatable module {:__call (fn [_ ...] (CarState ...))})

module
