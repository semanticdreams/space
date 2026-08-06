(local glm (require :glm))
(local _ (require :main))
(local {: SandboxCameraControls} (require :sandbox-camera-controls))
(local SandboxToolbarState (require :sandbox-toolbar-state))

(local tests [])

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(local make-fake-camera
  (fn []
    (local self {})
    (set self.position (glm.vec3 0 0 0))
    (set self.yaw-calls [])
    (set self.pitch-calls [])
    (set self.other-calls [])
    (fn self.forward [_self dist]
      (table.insert self.other-calls {:fn :forward :dist dist})
      (set self.position (- self.position (glm.vec3 0 0 dist))))
    (fn self.right [_self dist]
      (table.insert self.other-calls {:fn :right :dist dist})
      (set self.position (+ self.position (glm.vec3 dist 0 0))))
    (fn self.up [_self dist]
      (table.insert self.other-calls {:fn :up :dist dist})
      (set self.position (+ self.position (glm.vec3 0 dist 0))))
    (fn self.yaw [_self angle]
      (table.insert self.yaw-calls angle))
    (fn self.pitch [_self angle]
      (table.insert self.pitch-calls angle))
    (fn self.set-position [_self new-pos]
      (set self.position new-pos))
    (fn self.get-forward [_self] (glm.vec3 0 0 -1))
    (fn self.get-right [_self] (glm.vec3 1 0 0))
    (fn self.get-up [_self] (glm.vec3 0 1 0))
    (fn self.drop [_self] nil)
    self))

(local make-fake-flight-controls
  (fn [camera]
    (local self {})
    (set self.last-update-delta nil)
    (set self.wheel-calls [])
    (set self.mouse-button-calls [])
    (set self.mouse-motion-calls [])
    (set self.gamepad-calls [])
    (set self.key-calls [])
    (set self.drop-called false)
    (fn self.update [_self delta]
      (set self.last-update-delta delta))
    (fn self.drop [_self]
      (set self.drop-called true))
    (fn self.drag-active? [_self] false)
    (fn self.should-suppress-click? [_self payload] false)
    (fn self.on-key-down [_self payload]
      (table.insert self.key-calls {:type :down :payload payload}))
    (fn self.on-key-up [_self payload]
      (table.insert self.key-calls {:type :up :payload payload}))
    (fn self.on-mouse-wheel [_self payload]
      (table.insert self.wheel-calls payload))
    (fn self.on-mouse-button-down [_self payload]
      (table.insert self.mouse-button-calls {:type :down :payload payload}))
    (fn self.on-mouse-button-up [_self payload]
      (table.insert self.mouse-button-calls {:type :up :payload payload}))
    (fn self.on-mouse-motion [_self payload]
      (table.insert self.mouse-motion-calls payload))
    (fn self.on-gamepad-button-down [_self payload]
      (table.insert self.gamepad-calls {:type :button-down :payload payload}))
    (fn self.on-gamepad-axis-motion [_self payload]
      (table.insert self.gamepad-calls {:type :axis-motion :payload payload}))
    (fn self.on-gamepad-removed [_self payload]
      (table.insert self.gamepad-calls {:type :removed :payload payload}))
    self))

(local make-fake-terrain-sampler
  (fn [height]
    (local self {})
    (fn self.height-at-world-point [world-point] height)
    self))

;; ---------------------------------------------------------------------------
;; Tests
;; ---------------------------------------------------------------------------

(fn flight-mode-delegates-update []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (assert (= flight-controls.last-update-delta nil)
          "No update should have been called yet")
  (controls:update 16)
  (assert (not (= flight-controls.last-update-delta nil))
          "Flight controls update must be called in flight mode")
  (controls:drop)
  true)

(fn grounded-mode-skips-flight-update []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler}))
  (controls:update 16)  ; 16ms
  (assert (not flight-controls.last-update-delta)
          "Flight controls update must NOT be called in grounded mode")
  (controls:drop)
  true)

(fn grounded-wheel-is-noop []
  "In grounded mode, on-mouse-wheel must not mutate inner flight controls."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler}))
  (local pre-count (length flight-controls.wheel-calls))
  (controls:on-mouse-wheel {:x 0 :y 5})
  (assert (= (length flight-controls.wheel-calls) pre-count)
          "Grounded wheel must not mutate flight-controls wheel calls")
  (controls:drop)
  true)

(fn flight-mode-delegates-mouse []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (controls:on-mouse-wheel {:x 1 :y 2})
  (assert (> (length flight-controls.wheel-calls) 0)
          "Flight mode must delegate on-mouse-wheel to flight controls")
  (controls:on-mouse-button-down {:button 1 :x 100 :y 200})
  (assert (> (length flight-controls.mouse-button-calls) 0)
          "Flight mode must delegate on-mouse-button-down")
  (controls:on-mouse-motion {:x 110 :y 210})
  (assert (> (length flight-controls.mouse-motion-calls) 0)
          "Flight mode must delegate on-mouse-motion")
  (controls:drop)
  true)

(fn flight-mode-delegates-gamepad []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (controls:on-gamepad-button-down {:button 0 :which 0})
  (assert (> (length flight-controls.gamepad-calls) 0)
          "Flight mode must delegate on-gamepad-button-down")
  (controls:on-gamepad-axis-motion {:axis 0 :value 0.5 :which 0})
  (assert (> (length flight-controls.gamepad-calls) 1)
          "Flight mode must delegate on-gamepad-axis-motion")
  (controls:on-gamepad-removed {:which 0})
  (assert (> (length flight-controls.gamepad-calls) 2)
          "Flight mode must delegate on-gamepad-removed")
  (controls:drop)
  true)

(fn flight-to-grounded-without-sampler-errors []
  "When controls are constructed in :flight without a terrain sampler,
  then the toolbar switches to :walk and update is called, it must error."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  ;; Construct without terrain-sampler (valid in flight mode)
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  ;; Toggle to walk
  (toolbar-state:set-interaction-mode :walk)
  ;; Update must error because terrain-sampler is missing
  (local (ok err) (pcall controls.update controls 16))
  (assert (not ok)
          "Update must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  (controls:drop)
  true)

(fn grounded-mode-requires-terrain-sampler []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local (ok err) (pcall SandboxCameraControls
                          {:camera camera
                           :toolbar-state toolbar-state
                           :flight-controls flight-controls}))
  (assert (not ok)
          "SandboxCameraControls must error when grounded mode is selected but no terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  true)

(fn grounded-mouse-look-clamps-pitch []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :pitch-min -1.2
                                           :pitch-max 1.2
                                           :mouse-look-speed 0.1}))
  ;; Start drag at origin and apply several large upward motions that
  ;; would exceed pitch-min if unclamped. The accumulated pitch (sum of
  ;; camera:pitch deltas) must stay within [pitch-min, pitch-max].
  (controls:on-mouse-button-down {:button 1 :x 0 :y 0 :state true})
  ;; Apply three large upward motions (each raw delta = -2.0)
  (controls:on-mouse-motion {:x 0 :y -20})  ;; dy=-20, raw=-2.0 -> clamped to -1.2
  (controls:on-mouse-motion {:x 0 :y -40})  ;; dy=-20, raw=-2.0 -> already at -1.2, delta=0
  (controls:on-mouse-motion {:x 0 :y -60})  ;; dy=-20, raw=-2.0 -> still at -1.2, delta=0
  ;; Now apply large downward motions
  (controls:on-mouse-motion {:x 0 :y 0})    ;; dy=60, raw=6.0 -> goes to +1.2, delta=2.4
  (controls:on-mouse-motion {:x 0 :y 20})   ;; dy=20, raw=2.0 -> already at +1.2, delta=0
  ;; Sum all applied pitch deltas to compute accumulated pitch
  (var accumulated 0.0)
  (each [_ delta (ipairs camera.pitch-calls)]
    (set accumulated (+ accumulated delta)))
  ;; Accumulated pitch must be within bounds
  (assert (>= accumulated -1.2)
          (.. "Accumulated pitch " (tostring accumulated) " must be >= -1.2"))
  (assert (<= accumulated 1.2)
          (.. "Accumulated pitch " (tostring accumulated) " must be <= 1.2"))
  ;; There must be at least one yaw or pitch call
  (assert (> (+ (length camera.yaw-calls) (length camera.pitch-calls)) 0)
          "Mouse look must call camera:yaw or camera:pitch in grounded mode")
  (controls:drop)
  true)

(fn grounded-space-jumps []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :eye-height 2.0
                                           :jump-speed 8.0}))
  ;; Camera starts on ground (y = 0)
  (controls:on-key-down {:key 32})  ; space
  ;; After one update, camera should move upward
  (controls:update 16)  ; 16ms
  (local pos-y-after-jump camera.position.y)
  (assert (> pos-y-after-jump 0)
          (.. "Camera should move upward on jump, got "
              (tostring pos-y-after-jump)))
  ;; After many frames, camera should fall back and land at eye-height
  (for [_ 1 60]
    (controls:update 16))
  (assert (< (math.abs (- camera.position.y 2.0)) 0.5)
          (.. "Camera should land near eye-height after jump, got "
              (tostring camera.position.y)))
  (controls:drop)
  true)

(fn gravity-lands-at-terrain-plus-eye-height []
  (local camera (make-fake-camera))
  (camera:set-position (glm.vec3 0 10 0))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 3.0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :eye-height 2.0
                                           :gravity 18.0}))
  (for [_ 1 80]
    (controls:update 16))  ; 16ms * 80 = 1.28s — enough to fall and smooth to terrain+eye-height
  (assert (< (math.abs (- camera.position.y 5.0)) 0.5)
          (.. "Camera should settle at terrain height + eye height (5.0), got "
              (tostring camera.position.y)))
  (controls:drop)
  true)

(fn terrain-follow-uses-scaling-channel []
  (local camera (make-fake-camera))
  (camera:set-position (glm.vec3 0 10 0))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler {:height-at-world-point (fn [_self world-point] 3.0)})
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :eye-height 2.0
                                           :gravity 18.0}))
  (controls:update 16)  ; 16ms
  (local after-one camera.position.y)
  (assert (< after-one 10.0)
          (.. "Camera should move toward terrain, got " (tostring after-one)))
  (assert (> after-one 5.0)
          (.. "Camera should not snap to terrain+eye-height in one frame, got "
              (tostring after-one)))
  (controls:drop)
  true)

(fn drop-delegates-to-flight-controls []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (assert (not flight-controls.drop-called)
          "Flight drop should not have been called yet")
  (controls:drop)
  (assert flight-controls.drop-called
          "Drop must delegate to flight controls")
  true)

(fn flight-mode-delegates-key-handlers []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (controls:on-key-down {:key 44 :scancode 44})
  (assert (> (length flight-controls.key-calls) 0)
          "Flight mode must delegate on-key-down")
  (controls:on-key-up {:key 44 :scancode 44})
  (assert (> (length flight-controls.key-calls) 1)
          "Flight mode must delegate on-key-up")
  (controls:drop)
  true)

(fn walk-wasd-uses-canonical-keys []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :movement-speed 10.0}))
  (controls:on-key-down {:key 119})
  (controls:update 1000)
  (controls:on-key-up {:key 119})
  (assert (< camera.position.z -9.9)
          (.. "W must move the walk camera forward, got z=" (tostring camera.position.z)))
  (controls:on-key-down {:key 100})
  (controls:update 1000)
  (controls:on-key-up {:key 100})
  (assert (> camera.position.x 9.9)
          (.. "D must move the walk camera right, got x=" (tostring camera.position.x)))
  (assert (not flight-controls.last-update-delta)
          "Walk WASD must not delegate update to flight controls")
  (controls:drop)
  true)

(fn walk-space-does-not-boost-horizontal-speed []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :movement-speed 10.0
                                           :jump-speed 0.0
                                           :gravity 0.0}))
  (controls:on-key-down {:key 119})
  (controls:update 1000)
  (local forward-without-space (- camera.position.z))
  (camera:set-position (glm.vec3 0 0 0))
  (controls:on-key-down {:key 32})
  (controls:update 1000)
  (local forward-with-space (- camera.position.z))
  (assert (< (math.abs (- forward-with-space forward-without-space)) 0.01)
          (.. "Space must not multiply walk horizontal speed; without="
              (tostring forward-without-space) " with=" (tostring forward-with-space)))
  (controls:drop)
  true)

(fn walk-arrow-keys-yaw-and-clamp-pitch []
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :pitch-min -0.5
                                           :pitch-max 0.5}))
  (controls:on-key-down {:key 1073741904})
  (controls:update 1000)
  (controls:on-key-up {:key 1073741904})
  (assert (< (. camera.yaw-calls 1) 0)
          "Left arrow must yaw left with a negative delta")
  (controls:on-key-down {:key 1073741903})
  (controls:update 1000)
  (controls:on-key-up {:key 1073741903})
  (assert (> (. camera.yaw-calls 2) 0)
          "Right arrow must yaw right with a positive delta")
  (controls:on-key-down {:key 1073741906})
  (for [_ 1 4]
    (controls:update 1000))
  (var accumulated 0.0)
  (each [_ delta (ipairs camera.pitch-calls)]
    (set accumulated (+ accumulated delta)))
  (assert (<= accumulated 0.5)
          (.. "Up arrow pitch must clamp to max, got " (tostring accumulated)))
  (controls:drop)
  true)

(fn object-modes-ignore-camera-controls []
  (each [_ mode (ipairs [:move :grab])]
    (local camera (make-fake-camera))
    (local toolbar-state (SandboxToolbarState {:interaction-mode mode}))
    (local flight-controls (make-fake-flight-controls camera))
    (local fake-sampler (make-fake-terrain-sampler 0))
    (local controls (SandboxCameraControls {:camera camera
                                             :toolbar-state toolbar-state
                                             :flight-controls flight-controls
                                             :terrain-sampler fake-sampler}))
    (controls:on-key-down {:key 119})
    (controls:on-key-down {:key 1073741904})
    (controls:update 1000)
    (assert (= camera.position.x 0)
            (.. (tostring mode) " must not mutate camera x"))
    (assert (= camera.position.y 0)
            (.. (tostring mode) " must not mutate camera y"))
    (assert (= camera.position.z 0)
            (.. (tostring mode) " must not mutate camera z"))
    (assert (= (length flight-controls.key-calls) 0)
            (.. (tostring mode) " must not delegate key events to flight controls"))
    (assert (not flight-controls.last-update-delta)
            (.. (tostring mode) " must not delegate update to flight controls"))
    (controls:drop))
  true)

(fn object-mode-releases-clear-walk-input-state []
  (each [_ mode (ipairs [:move :grab])]
    (local camera (make-fake-camera))
    (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
    (local flight-controls (make-fake-flight-controls camera))
    (local fake-sampler (make-fake-terrain-sampler 0))
    (local controls (SandboxCameraControls {:camera camera
                                             :toolbar-state toolbar-state
                                             :flight-controls flight-controls
                                             :terrain-sampler fake-sampler
                                             :eye-height 0.0
                                             :gravity 0.0
                                             :movement-speed 10.0}))
    (controls:on-key-down {:key 119})
    (controls:on-mouse-button-down {:button 1 :x 0 :y 0})
    (toolbar-state:set-interaction-mode mode)
    (controls:on-key-up {:key 119})
    (controls:on-mouse-button-up {:button 1 :x 0 :y 0})
    (toolbar-state:set-interaction-mode :walk)
    (controls:update 1000)
    (controls:on-mouse-motion {:x 100 :y 0})
    (assert (= camera.position.z 0)
            (.. (tostring mode) " release must clear stale Walk W state"))
    (assert (= (length camera.yaw-calls) 0)
            (.. (tostring mode) " release must clear stale Walk mouse-look state"))
    (assert (= (length flight-controls.key-calls) 0)
            (.. (tostring mode) " release must not delegate to flight controls"))
    (controls:drop))
  true)

(fn flight-to-grounded-on-key-down-without-sampler-errors []
  "When toggled to grounded without terrain sampler, on-key-down must error
  before mutating any grounded state."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  ;; Toggle to walk
  (toolbar-state:set-interaction-mode :walk)
  ;; Store pre-call camera position to verify no mutation
  (local pre-y (glm.vec3 camera.position.x camera.position.y camera.position.z))
  (local (ok err) (pcall controls.on-key-down controls {:key 32}))
  (assert (not ok)
          "on-key-down must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  ;; Camera position must not have been mutated before the error
  (assert (= (. camera.position 2) (. pre-y 2))
          (.. "Camera y must not change before dependency guard errors, got "
              (tostring (. camera.position 2)) " (was " (tostring (. pre-y 2)) ")"))
  (controls:drop)
  true)

(fn flight-to-grounded-on-mouse-button-down-without-sampler-errors []
  "When toggled to grounded without terrain sampler, on-mouse-button-down must
  error before mutating any grounded state."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  ;; Toggle to walk
  (toolbar-state:set-interaction-mode :walk)
  (local (ok err) (pcall controls.on-mouse-button-down controls {:button 1 :x 100 :y 200}))
  (assert (not ok)
          "on-mouse-button-down must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  (controls:drop)
  true)

(fn flight-to-grounded-on-mouse-motion-without-sampler-errors []
  "When toggled to grounded without terrain sampler, on-mouse-motion must error
  before mutating the camera, even when no drag is active."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  ;; Toggle to walk
  (toolbar-state:set-interaction-mode :walk)
  (local (ok err) (pcall controls.on-mouse-motion controls {:x 110 :y 210}))
  (assert (not ok)
          "on-mouse-motion must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  (controls:drop)
  true)

;; R1-1: y-channel syncs from current camera Y when entering grounded mode
(fn flight-to-grounded-syncs-y-channel-from-current-camera-y []
  "When camera is at Y=20 in flight mode and toggles to grounded,
  the first grounded frame must start terrain smoothing from
  current camera Y (20), not from the Y value captured at construction (0)."
  (local camera (make-fake-camera))
  (camera:set-position (glm.vec3 0 20 0))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 0))
  ;; Construct controls in flight mode at camera Y=0 (construction time)
  (camera:set-position (glm.vec3 0 0 0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler}))
  ;; Move camera to Y=20 while in flight mode
  (camera:set-position (glm.vec3 0 20 0))
  ;; Toggle to walk
  (toolbar-state:set-interaction-mode :walk)
  ;; First grounded update: should start smoothing from current Y (20),
  ;; not from the Y at construction (0). With terrain=0, eye-height=2,
  ;; target = 2. Smoothing should move from 20 toward 2 without jumping.
  (controls:update 16)
  (local after-one camera.position.y)
  (assert (< after-one 20.0)
          (.. "Camera should move toward terrain from 20, got " (tostring after-one)))
  (assert (> after-one 5.0)
          (.. "Camera should not jump far in one frame from 20, got " (tostring after-one)))
  (controls:drop)
  true)

;; R1-1: on landing, y-channel snaps to target-y (terrain+eye-height),
;; not to the potentially-below-target integrated new-y.
(fn grounded-landing-snaps-channel-to-target-y-not-below-terrain []
  "After an airborne descent where the integrated new-y falls below
  terrain+eye-height, landing must snap the smoothing channel to
  target-y (terrain+eye-height), not to the below-ground new-y.
  After landing, camera must remain at terrain+eye-height without
  dipping below it."
  (local camera (make-fake-camera))
  (camera:set-position (glm.vec3 0 10 0))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :walk}))
  (local flight-controls (make-fake-flight-controls camera))
  (local fake-sampler (make-fake-terrain-sampler 3.0))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls
                                           :terrain-sampler fake-sampler
                                           :eye-height 2.0
                                           :gravity 50.0}))
  ;; Let the camera fall and land. With gravity 50.0, it will overshoot.
  ;; The target is 3.0 + 2.0 = 5.0 — this should settle after many frames.
  (for [_ 1 100]
    (controls:update 16))
  ;; After settling, camera should be at or near terrain + eye-height = 5.0
  (assert (>= camera.position.y 4.8)
          (.. "Camera should not go below terrain+eye-height after landing, got "
              (tostring camera.position.y)))
  (assert (<= camera.position.y 5.2)
          (.. "Camera should land near terrain+eye-height (5.0), got "
              (tostring camera.position.y)))
  (controls:drop)
  true)

;; R1-2: grounded gamepad/wheel handlers error when terrain sampler is missing
(fn grounded-wheel-errors-without-terrain-sampler []
  "When toggled to grounded without terrain sampler, on-mouse-wheel must error."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (toolbar-state:set-interaction-mode :walk)
  (local (ok err) (pcall controls.on-mouse-wheel controls {:x 0 :y 5}))
  (assert (not ok)
          "on-mouse-wheel must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  (controls:drop)
  true)

(fn grounded-gamepad-button-down-errors-without-terrain-sampler []
  "When toggled to grounded without terrain sampler, on-gamepad-button-down must error."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (toolbar-state:set-interaction-mode :walk)
  (local (ok err) (pcall controls.on-gamepad-button-down controls {:button 0 :which 0}))
  (assert (not ok)
          "on-gamepad-button-down must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  (controls:drop)
  true)

(fn grounded-gamepad-axis-motion-errors-without-terrain-sampler []
  "When toggled to grounded without terrain sampler, on-gamepad-axis-motion must error."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (toolbar-state:set-interaction-mode :walk)
  (local (ok err) (pcall controls.on-gamepad-axis-motion controls {:axis 0 :value 0.5 :which 0}))
  (assert (not ok)
          "on-gamepad-axis-motion must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  (controls:drop)
  true)

(fn grounded-gamepad-removed-errors-without-terrain-sampler []
  "When toggled to grounded without terrain sampler, on-gamepad-removed must error."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:interaction-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  (toolbar-state:set-interaction-mode :walk)
  (local (ok err) (pcall controls.on-gamepad-removed controls {:which 0}))
  (assert (not ok)
          "on-gamepad-removed must error when toggled to grounded without terrain sampler")
  (assert (or (string.find err "terrain sampler")
              (string.find err "terrain-sampler"))
          (.. "Error must mention terrain sampler, got: " (tostring err)))
  (controls:drop)
  true)

(table.insert tests {:name "flight mode delegates update to flight controls"
                     :fn flight-mode-delegates-update})
(table.insert tests {:name "grounded mode skips flight update"
                      :fn grounded-mode-skips-flight-update})
(table.insert tests {:name "grounded wheel is noop"
                      :fn grounded-wheel-is-noop})
(table.insert tests {:name "flight mode delegates mouse handlers"
                      :fn flight-mode-delegates-mouse})
(table.insert tests {:name "flight mode delegates gamepad handlers"
                      :fn flight-mode-delegates-gamepad})
(table.insert tests {:name "grounded mode requires terrain sampler at construction"
                      :fn grounded-mode-requires-terrain-sampler})
(table.insert tests {:name "flight to grounded without sampler errors on update"
                      :fn flight-to-grounded-without-sampler-errors})
(table.insert tests {:name "flight to grounded without sampler errors on key-down"
                      :fn flight-to-grounded-on-key-down-without-sampler-errors})
(table.insert tests {:name "flight to grounded without sampler errors on mouse-button-down"
                      :fn flight-to-grounded-on-mouse-button-down-without-sampler-errors})
(table.insert tests {:name "flight to grounded without sampler errors on mouse-motion"
                      :fn flight-to-grounded-on-mouse-motion-without-sampler-errors})
(table.insert tests {:name "grounded mouse look clamps pitch"
                     :fn grounded-mouse-look-clamps-pitch})
(table.insert tests {:name "grounded Space sets positive vertical velocity"
                     :fn grounded-space-jumps})
(table.insert tests {:name "gravity lands camera at terrain height plus eye height"
                     :fn gravity-lands-at-terrain-plus-eye-height})
(table.insert tests {:name "terrain follow uses scalar channel not snap"
                     :fn terrain-follow-uses-scaling-channel})
(table.insert tests {:name "drop delegates to flight controls"
                     :fn drop-delegates-to-flight-controls})
(table.insert tests {:name "flight mode delegates key handlers"
                       :fn flight-mode-delegates-key-handlers})
(table.insert tests {:name "walk WASD uses canonical key codes"
                       :fn walk-wasd-uses-canonical-keys})
(table.insert tests {:name "walk Space does not boost horizontal speed"
                       :fn walk-space-does-not-boost-horizontal-speed})
(table.insert tests {:name "walk arrow keys yaw and clamp pitch"
                       :fn walk-arrow-keys-yaw-and-clamp-pitch})
(table.insert tests {:name "object modes ignore camera controls"
                       :fn object-modes-ignore-camera-controls})
(table.insert tests {:name "object-mode releases clear Walk input state"
                       :fn object-mode-releases-clear-walk-input-state})
(table.insert tests {:name "flight to grounded syncs y-channel from current camera Y"
                       :fn flight-to-grounded-syncs-y-channel-from-current-camera-y})
(table.insert tests {:name "grounded landing snaps channel to target-y not below terrain"
                      :fn grounded-landing-snaps-channel-to-target-y-not-below-terrain})
(table.insert tests {:name "grounded wheel errors without terrain sampler"
                      :fn grounded-wheel-errors-without-terrain-sampler})
(table.insert tests {:name "grounded gamepad-button-down errors without terrain sampler"
                      :fn grounded-gamepad-button-down-errors-without-terrain-sampler})
(table.insert tests {:name "grounded gamepad-axis-motion errors without terrain sampler"
                      :fn grounded-gamepad-axis-motion-errors-without-terrain-sampler})
(table.insert tests {:name "grounded gamepad-removed errors without terrain sampler"
                      :fn grounded-gamepad-removed-errors-without-terrain-sampler})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-camera-controls"
                       :tests tests})))

{:name "sandbox-camera-controls"
 :tests tests
 :main main}
