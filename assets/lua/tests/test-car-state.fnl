(local glm (require :glm))
(local CarState (require :car-state))
(local DemoCar (require :demo-car))
(local BuildContext (require :build-context))
(local {: LayoutRoot} (require :layout))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))

(local tests [])

(local bt (require :bt))
(local KEY_F1 1073741882)
(local KEY_UNRELATED (string.byte "u"))
(local reset-engine-events
  (fn []
    (when _G.reset-engine-events
      (_G.reset-engine-events))))

(fn ensure-events-and-states []
  (when (not (and app.engine app.engine.events app.engine.events.updated))
    (reset-engine-events))
  (when (not (and app.engine app.states))
    (local states (States))
    (StateSystemBindings.bind-states-host states)
    (set app.states states)))

(fn build-demo-car [position]
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")}))
  (local builder (DemoCar {:position position}))
  (local host (builder ctx))
  (host.layout:measurer)
  (set host.layout.size host.layout.measure)
  (host.layout:layouter)
  (local root (LayoutRoot {:log-dirt? false}))
  (host.layout:set-root root)
  (root:update)
  (set app.scene {:entity host})
  {:host host :root root})

(fn with-demo-car-state [body opts]
  (local options (or opts {}))
  (local original-states app.states)
  (local original-scene app.scene)
  (var build nil)
  (var host nil)
  (var state nil)
  (local states
    (or options.states
        (States {:hud_provider
                 (fn [_states]
                   {:command-hints
                    {:handle-toggle-key (fn [_self _payload]
                                          false)
                     :close-on-handled-event (fn [_self _route-key _payload]
                                               false)}})})))
  (when (not options.states)
    (states:add-state :normal {})
    (states:set-state :normal))
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  (local (ok result)
    (pcall
      (fn []
        (set build (build-demo-car (glm.vec3 0 0 0)))
        (set host build.host)
        (set state (CarState))
        (when states
          (states:add-state :car state))
        (state:on-enter)
        (body state host))))
  (when state
    (state:on-leave))
  (when host
    (host:drop))
  (set app.scene original-scene)
  (StateSystemBindings.bind-states-host original-states)
  (set app.states original-states)
  (when (not ok)
    (error result))
  result)

(fn vehicle-binding-creates-raycast []
  (assert bt "Vehicle test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -9.8 0)
  (local shape (bt.BoxShape (bt.Vector3 1 0.5 2)))
  (local transform (bt.Transform))
  (transform:setIdentity)
  (transform:setOrigin (bt.Vector3 0 2 0))
  (local motion (bt.DefaultMotionState transform))
  (local inertia (bt.Vector3 0 0 0))
  (shape:calculateLocalInertia 800 inertia)
  (local info (bt.RigidBodyConstructionInfo 800 motion shape inertia))
  (local body (bt.RigidBody info))
  (local raycaster (bt.DefaultVehicleRaycaster (app.engine.physics:getWorld)))
  (local tuning (bt.VehicleTuning))
  (local vehicle (bt.RaycastVehicle tuning body raycaster))
  (vehicle:setCoordinateSystem 2 1 0)
  (local wheel-dir (bt.Vector3 0 -1 0))
  (local wheel-axle (bt.Vector3 0 0 1))
  (vehicle:addWheel (bt.Vector3 -0.6 0.6 -0.8) wheel-dir wheel-axle 0.3 0.4 tuning true)
  (vehicle:addWheel (bt.Vector3 -0.6 0.6 0.8) wheel-dir wheel-axle 0.3 0.4 tuning true)
  (vehicle:addWheel (bt.Vector3 0.6 0.6 -0.8) wheel-dir wheel-axle 0.3 0.4 tuning false)
  (vehicle:addWheel (bt.Vector3 0.6 0.6 0.8) wheel-dir wheel-axle 0.3 0.4 tuning false)
  (app.engine.physics:addRigidBody body)
  (local wheel-count (vehicle:getNumWheels))
  (local chassis-transform (vehicle:getChassisWorldTransform))
  (local origin (chassis-transform:getOrigin))
  (app.engine.physics:removeRigidBody body)
  (assert (= wheel-count 4) (.. "Expected 4 wheels, got " wheel-count))
  (assert origin "Vehicle origin missing after setup")
  (assert (> origin.y 0.5) (.. "Vehicle chassis y unexpectedly low: " origin.y)))

(fn car-state-drives-forward []
  (assert bt "Car state test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (ensure-events-and-states)
  (with-demo-car-state
    (fn [state _host]
      (state:on-key-down {:key CarState.KEY.forward})
      (state:on-key-down {:key CarState.KEY.left})
      (state:on-updated 0.016)
      (local internal state.__car_state)
      (local vehicle (and internal internal.vehicle))
      (local steer (and internal internal.steer))
      (state:on-key-up {:key CarState.KEY.forward})
      (state:on-key-up {:key CarState.KEY.left})
      (assert vehicle "Car state did not create a vehicle")
      (assert (= (vehicle:getNumWheels) 4) "Vehicle did not add four wheels")
      (assert (< (or steer 0) 0) "Left key did not update steering state"))))

(fn car-state-ignores-first-person-controls []
  (ensure-events-and-states)
  (var called 0)
  (set app.first-person-controls {:update (fn [_ delta]
                                              (set called (+ called 1))
                                              (assert delta "Expected delta to be provided"))})
  (with-demo-car-state
    (fn [state _host]
      (state:on-updated 0.02)))
  (assert (= called 0) "Car state should not forward updates to first-person controls"))

(fn car-state-survives-gc-during-physics-step []
  (assert bt "Car state test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (ensure-events-and-states)
  (with-demo-car-state
    (fn [state _host]
      (local internal state.__car_state)
      (assert internal.vehicle "Car state did not create a vehicle")
      (collectgarbage)
      (collectgarbage)
      (app.engine.physics:update 16)
      (state:on-updated 0.016)
      (assert internal.vehicle "Vehicle lost during physics update"))))

(fn car-state-does-not-swallow-unrelated-keys []
  (ensure-events-and-states)
  (with-demo-car-state
    (fn [state _host]
      (local handled (state:on-key-down {:key KEY_UNRELATED}))
      (local internal state.__car_state)
      (local key-state (. internal.keys KEY_UNRELATED))
      (assert (not handled) "Car state should let unrelated keys fall through")
      (assert (= key-state nil) "Car state should not record unrelated keys as active"))))

(fn car-state-f1-toggles-command-hints []
  (ensure-events-and-states)
  (var toggles 0)
  (local states
    (States {:hud_provider
             (fn [_states]
               {:command-hints
                {:handle-toggle-key (fn [_self payload]
                                      (assert (= payload.key KEY_F1)
                                              "F1 toggle should receive the original payload")
                                      (set toggles (+ toggles 1))
                                      true)
                 :close-on-handled-event (fn [_self _route-key _payload]
                                           false)}})}))
  (states:add-state :normal {})
  (states:set-state :normal)
  (with-demo-car-state
    (fn [state _host]
      (assert (state:on-key-down {:key KEY_F1})
              "Car state should route unhandled F1 to command hints")
      (assert (= toggles 1)
              "Car state F1 should toggle command hints through the HUD host"))
    {:states states}))

(table.insert tests {:name "Vehicle bindings expose raycast vehicle" :fn vehicle-binding-creates-raycast})
(table.insert tests {:name "Car state moves car with keyboard input" :fn car-state-drives-forward})
(table.insert tests {:name "Car state does not touch first-person controls" :fn car-state-ignores-first-person-controls})
(table.insert tests {:name "Car state keeps Bullet objects alive across GC" :fn car-state-survives-gc-during-physics-step})
(table.insert tests {:name "Car state does not swallow unrelated keys" :fn car-state-does-not-swallow-unrelated-keys})
(table.insert tests {:name "Car state F1 toggles command hints" :fn car-state-f1-toggles-command-hints})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "car-state"
                       :tests tests})))

{:name "car-state"
 :tests tests
 :main main}
