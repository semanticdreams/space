;; SandboxCameraControls — flight/walk camera controls wrapper.
;; Delegates to existing FirstPersonControls in :flight mode and
;; provides terrain-following movement in :walk mode.
(local glm (require :glm))
(local CameraAnimation (require :camera-animation))

(local SDL_BUTTON_LEFT 1)

(local default-key-mapping
  {:move-left 97
   :move-right 100
   :move-forward 119
   :move-backward 115
   :look-up 1073741906
   :look-down 1073741905
   :look-left 1073741904
   :look-right 1073741903
   :jump 32})

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn delta->seconds [delta delta-unit]
  (if (not (finite-number? delta))
      0
      (= delta-unit :milliseconds)
      (/ delta 1000.0)
      (= delta-unit :seconds)
      delta
      (error (.. "SandboxCameraControls invalid :delta-unit "
                 (tostring delta-unit)
                 " (expected :milliseconds or :seconds)"))))

(fn clamp [value min-value max-value]
  (if (< value min-value) min-value
      (> value max-value) max-value
      value))

(fn vec3-x [v] (. v 1))
(fn vec3-y [v] (. v 2))
(fn vec3-z [v] (. v 3))

(fn horizontal-component [vec3-val]
  (local flat (glm.vec3 (vec3-x vec3-val) 0 (vec3-z vec3-val)))
  (local len (glm.length flat))
  (if (> len 0.0001)
      (/ flat len)
      (glm.vec3 0 0 0)))

(fn SandboxCameraControls [opts]
  (local options (or opts {}))
  (local camera (assert options.camera
                        "SandboxCameraControls requires a camera"))
  (local toolbar-state (assert options.toolbar-state
                               "SandboxCameraControls requires toolbar-state"))
  (local flight-controls (assert options.flight-controls
                                 "SandboxCameraControls requires flight-controls"))
  (local delta-unit (or options.delta-unit :milliseconds))
  (local eye-height (or options.eye-height 2.0))
  (local gravity (or options.gravity 18.0))
  (local jump-speed (or options.jump-speed 8.0))
  (local pitch-min (or options.pitch-min -1.2))
  (local pitch-max (or options.pitch-max 1.2))
  (local movement-speed (or options.movement-speed 10.0))
  (local mouse-look-speed (or options.mouse-look-speed 0.001))

  (fn current-navigation-mode []
    (toolbar-state:navigation-mode))

  (when (= (current-navigation-mode) :walk)
    (when (not options.terrain-sampler)
      (error "SandboxCameraControls walk mode requires terrain sampler (terrain-sampler)")))

  (var grounded-keys {})
  (var grounded-vertical-velocity 0.0)
  (var grounded-airborne? false)
  (var grounded-drag-look-start nil)
  (var grounded-mouse-pos nil)
  (var grounded-pitch 0.0)

  ;; Track navigation mode so we can detect flight→walk transitions
  ;; and sync the y-channel from the camera's current Y before
  ;; the first grounded terrain update.
  (var prev-navigation-mode (current-navigation-mode))

  (local y-channel (CameraAnimation.scalar-channel
                      {:value (vec3-y camera.position)
                       :target (vec3-y camera.position)
                       :smoothing-rate 8.0}))

  (fn apply-grounded-pitch! [delta]
    "Apply a pitch delta clamped to [pitch-min, pitch-max]."
    (local new-pitch (+ grounded-pitch delta))
    (local clamped-pitch (clamp new-pitch pitch-min pitch-max))
    (local actual-delta (- clamped-pitch grounded-pitch))
    (when (not (= actual-delta 0.0))
      (camera:pitch actual-delta))
    (set grounded-pitch clamped-pitch))

  (fn grounded-action-active? [action]
    (local key (. default-key-mapping action))
    (and key (. grounded-keys key)))

  (fn grounded-horizontal-speed []
    movement-speed)

  (fn ensure-grounded-deps! []
    "Assert that all dependencies required for grounded mode are present."
    (when (not options.terrain-sampler)
      (error "SandboxCameraControls walk mode requires terrain sampler (terrain-sampler)")))

  (fn grounded-sample-terrain-height []
    (ensure-grounded-deps!)
    (local sampled (options.terrain-sampler:height-at-world-point camera.position))
    (if (finite-number? sampled) sampled 0.0))

  (fn grounded-apply-gravity-and-terrain [delta-seconds]
    (local terrain-height (grounded-sample-terrain-height))
    (local target-y (+ terrain-height eye-height))
    (local current-y (vec3-y camera.position))
    (if grounded-airborne?
        ;; Airborne: integrate velocity under gravity, check for landing
        (do
          (set grounded-vertical-velocity
               (- grounded-vertical-velocity (* gravity delta-seconds)))
          (local new-y (+ current-y (* grounded-vertical-velocity delta-seconds)))
          (if (<= new-y target-y)
              ;; Land: snap channel to target-y (not new-y which could
              ;; be below terrain+eye-height), then set camera to target-y
              ;; so the next frame's smoothing starts at the correct
              ;; terrain-following height.
              (do
                (set grounded-vertical-velocity 0.0)
                (set grounded-airborne? false)
                (y-channel:snap target-y)
                (y-channel:set-target target-y)
                (camera:set-position
                  (glm.vec3 (vec3-x camera.position) target-y (vec3-z camera.position))))
              ;; Still airborne: apply position directly
              (camera:set-position
                (glm.vec3 (vec3-x camera.position) new-y (vec3-z camera.position)))))
        ;; Grounded: always use scalar channel for smooth terrain following
        (do
          (set grounded-vertical-velocity 0.0)
          (y-channel:set-target target-y)
          (local smoothed-y (y-channel:update delta-seconds))
          (camera:set-position
            (glm.vec3 (vec3-x camera.position) smoothed-y (vec3-z camera.position))))))

  (fn sync-y-channel-on-flight-to-grounded-transition! []
    "When entering walk mode from flight, synchronize the smoothing
    channel to the camera's current Y so terrain following starts from
    the right value instead of a stale construction-time Y."
    (when (and (= (current-navigation-mode) :walk)
               (not (= prev-navigation-mode :walk)))
      (local current-y (vec3-y camera.position))
      (y-channel:snap current-y)
      (y-channel:set-target current-y)))

  (fn update [self delta]
    (local delta-seconds (delta->seconds delta delta-unit))
    (local current-mode (current-navigation-mode))
    (if (= current-mode :flight)
        (flight-controls:update delta)
        (= current-mode :walk)
        (do
          (ensure-grounded-deps!)
          ;; Sync y-channel from current camera Y on flight→walk transition.
          (sync-y-channel-on-flight-to-grounded-transition!)
          ;; Horizontal movement
          (when (or (grounded-action-active? :move-left)
                    (grounded-action-active? :move-right)
                    (grounded-action-active? :move-forward)
                    (grounded-action-active? :move-backward))
            (local fwd (horizontal-component (camera:get-forward)))
            (local right-dir (horizontal-component (camera:get-right)))
            (local speed (grounded-horizontal-speed))
            (var move (glm.vec3 0 0 0))
            (when (grounded-action-active? :move-left)
              (set move (- move (* right-dir speed))))
            (when (grounded-action-active? :move-right)
              (set move (+ move (* right-dir speed))))
            (when (grounded-action-active? :move-forward)
              (set move (+ move (* fwd speed))))
            (when (grounded-action-active? :move-backward)
              (set move (- move (* fwd speed))))
            (local flat-move (* (glm.vec3 delta-seconds) move))
            (camera:set-position (+ camera.position flat-move)))
          ;; Keyboard look
          (when (grounded-action-active? :look-up)
            (apply-grounded-pitch! (* delta-seconds 1.0)))
          (when (grounded-action-active? :look-down)
            (apply-grounded-pitch! (* -1 delta-seconds 1.0)))
          (when (grounded-action-active? :look-right)
            (camera:yaw (* delta-seconds 1.0)))
          (when (grounded-action-active? :look-left)
            (camera:yaw (* -1 delta-seconds 1.0)))
          ;; Gravity and terrain following
          (grounded-apply-gravity-and-terrain delta-seconds)))
    ;; Track navigation mode for next frame's transition detection.
    (set prev-navigation-mode current-mode))

  (fn drop [self]
    (flight-controls:drop)
    (set grounded-keys {})
    (set grounded-drag-look-start nil)
    (set grounded-mouse-pos nil)
    (set grounded-vertical-velocity 0.0)
    (set grounded-airborne? false)
    (set grounded-pitch 0.0))

  (fn drag-active? [self]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:drag-active?)
        (= mode :walk)
        (not (not grounded-drag-look-start))
        false))

  (fn should-suppress-click? [self payload]
    (if (= (current-navigation-mode) :flight)
        (flight-controls:should-suppress-click? payload)
        false))

  (fn on-key-down [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-key-down payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          (set (. grounded-keys payload.key) true)
          (when (and (= payload.key default-key-mapping.jump)
                      (not grounded-airborne?))
            (set grounded-vertical-velocity jump-speed)
            (set grounded-airborne? true)))))

  (fn on-key-up [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-key-up payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          (set (. grounded-keys payload.key) nil))
        (set (. grounded-keys payload.key) nil)))

  (fn on-mouse-wheel [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-mouse-wheel payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          nil)))  ;; grounded mode: wheel is a no-op

  (fn on-mouse-button-down [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-mouse-button-down payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          (when (= payload.button SDL_BUTTON_LEFT)
            (set grounded-drag-look-start {:x payload.x :y payload.y})))))

  (fn on-mouse-button-up [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-mouse-button-up payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          (when (= payload.button SDL_BUTTON_LEFT)
            (set grounded-drag-look-start nil)))
        (when (= payload.button SDL_BUTTON_LEFT)
          (set grounded-drag-look-start nil))))

  (fn on-mouse-motion [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-mouse-motion payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          (when grounded-drag-look-start
            (local dx (- payload.x grounded-drag-look-start.x))
            (local dy (- payload.y grounded-drag-look-start.y))
            (set grounded-drag-look-start {:x payload.x :y payload.y})
            (camera:yaw (* dx mouse-look-speed))
            (apply-grounded-pitch! (* dy mouse-look-speed))))))

  (fn on-gamepad-button-down [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-gamepad-button-down payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          nil)))

  (fn on-gamepad-axis-motion [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-gamepad-axis-motion payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          nil)))

  (fn on-gamepad-removed [self payload]
    (local mode (current-navigation-mode))
    (if (= mode :flight)
        (flight-controls:on-gamepad-removed payload)
        (= mode :walk)
        (do
          (ensure-grounded-deps!)
          nil)))

  {:update update
   :drop drop
   :drag-active? drag-active?
   :should-suppress-click? should-suppress-click?
   :on-key-down on-key-down
   :on-key-up on-key-up
   :on-mouse-wheel on-mouse-wheel
   :on-mouse-button-down on-mouse-button-down
   :on-mouse-button-up on-mouse-button-up
   :on-mouse-motion on-mouse-motion
   :on-gamepad-button-down on-gamepad-button-down
   :on-gamepad-axis-motion on-gamepad-axis-motion
   :on-gamepad-removed on-gamepad-removed
   :flight-controls flight-controls})

{: SandboxCameraControls}
