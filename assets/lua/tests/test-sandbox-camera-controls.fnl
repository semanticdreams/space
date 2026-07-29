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
  (local toolbar-state (SandboxToolbarState {:camera-mode :flight}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :grounded}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :grounded}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :flight}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :flight}))
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
  then the toolbar toggles to :grounded and update is called, it must error."
  (local camera (make-fake-camera))
  (local toolbar-state (SandboxToolbarState {:camera-mode :flight}))
  (local flight-controls (make-fake-flight-controls camera))
  ;; Construct without terrain-sampler (valid in flight mode)
  (local controls (SandboxCameraControls {:camera camera
                                           :toolbar-state toolbar-state
                                           :flight-controls flight-controls}))
  ;; Toggle to grounded
  (toolbar-state:toggle-camera-mode)
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :grounded}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :grounded}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :grounded}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :grounded}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :grounded}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :flight}))
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
  (local toolbar-state (SandboxToolbarState {:camera-mode :flight}))
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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-camera-controls"
                       :tests tests})))

{:name "sandbox-camera-controls"
 :tests tests
 :main main}
