(local glm (require :glm))

(local SDL_BUTTON_RIGHT 3)

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn CanvasControls [opts]
  (local options (or opts {}))
  (local canvas (assert (or options.canvas app.canvas)
                        "CanvasControls requires canvas"))
  (local camera (assert (or options.camera (and canvas canvas.camera))
                        "CanvasControls requires camera"))
  (local zoom-step (or options.zoom-step 1.15))
  (local min-scale (or options.min-scale 0.05))
  (local max-scale (or options.max-scale 6.0))
  (local wheel-pan-step (or options.wheel-pan-step 48.0))
  (var drag-start nil)
  (var mouse-pos nil)

  (fn set-pan-origin [payload]
    (set mouse-pos {:x (or payload.x 0)
                    :y (or payload.y 0)})
    (set drag-start {:pointer {:x (or payload.x 0)
                               :y (or payload.y 0)}
                     :position (glm.vec3 camera.position.x
                                         camera.position.y
                                         camera.position.z)}))

  (fn clear-pan-origin []
    (set drag-start nil))

  (fn update-mouse-pos [payload]
    (when payload
      (set mouse-pos {:x (or payload.x 0)
                      :y (or payload.y 0)})))

  (fn pointer-position []
    (if mouse-pos
        mouse-pos
        (if (and app.engine app.engine.input app.engine.input.mouse)
            {:x (or app.engine.input.mouse.x 0)
             :y (or app.engine.input.mouse.y 0)}
            (let [viewport (or app.viewport {:x 0 :y 0 :width 0 :height 0})]
              {:x (+ viewport.x (/ viewport.width 2))
               :y (+ viewport.y (/ viewport.height 2))}))))

  (fn plane-hit [projection]
    (when (and canvas canvas.screen-pos-ray)
      (local pointer (pointer-position))
      (local ray (canvas:screen-pos-ray pointer {:projection projection}))
      (when (and ray ray.origin ray.direction)
        (local dz (or ray.direction.z 0))
        (when (not (= dz 0))
          (local t (/ (- 0 ray.origin.z) dz))
          (+ ray.origin (* ray.direction t))))))

  (fn on-mouse-button-down [_self payload]
    (when (and payload (= payload.button SDL_BUTTON_RIGHT))
      (set-pan-origin payload)))

  (fn on-mouse-button-up [_self payload]
    (update-mouse-pos payload)
    (when (and payload (= payload.button SDL_BUTTON_RIGHT))
      (clear-pan-origin)))

  (fn on-mouse-motion [_self payload]
    (update-mouse-pos payload)
    (when (and drag-start payload)
      (local origin drag-start.pointer)
      (local units (or (and canvas canvas.world-units-per-pixel) 1.0))
      (local dx (- (or payload.x 0) origin.x))
      (local dy (- (or payload.y 0) origin.y))
      (camera:set-position
        (glm.vec3 (- drag-start.position.x (* dx units))
                  (+ drag-start.position.y (* dy units))
                  drag-start.position.z))))

  (fn pan-lateral [steps]
    (when (and (finite-number? steps)
               (not (= steps 0)))
      (local units (or (and canvas canvas.world-units-per-pixel) 1.0))
      (camera:set-position
        (glm.vec3 (+ camera.position.x (* steps units wheel-pan-step))
                  camera.position.y
                  camera.position.z))))

  (fn on-mouse-wheel [_self payload]
    (local lateral-steps (or (and payload payload.x) 0))
    (local zoom-steps (or (and payload payload.y) 0))
    (pan-lateral lateral-steps)
    (when (and (not (= zoom-steps 0))
               canvas
               canvas.set-scale-factor
               (finite-number? canvas.scale-factor))
      (local previous-scale canvas.scale-factor)
      (local anchor-before
        (if (> zoom-steps 0)
            (plane-hit canvas.projection)
            nil))
      (local factor
        (if (> zoom-steps 0)
            (/ 1.0 (^ zoom-step zoom-steps))
            (^ zoom-step (- 0 zoom-steps))))
      (local next-scale
        (clamp (* canvas.scale-factor factor) min-scale max-scale))
      (canvas:set-scale-factor next-scale)
      (when (and anchor-before
                 (not (= next-scale previous-scale)))
        (local anchor-after (plane-hit canvas.projection))
        (when anchor-after
          (camera:set-position
            (+ camera.position
               (glm.vec3 (- anchor-before.x anchor-after.x)
                         (- anchor-before.y anchor-after.y)
                         0)))))))

  (fn drag-active? [_self]
    (not (= drag-start nil)))

  (fn drag-engaged? [self]
    (self:drag-active?))

  (fn update [_self _delta]
    nil)

  (fn drop [_self]
    (clear-pan-origin)
    (set mouse-pos nil))

  {:on-key-down (fn [_self _payload] nil)
   :on-key-up (fn [_self _payload] nil)
   :on-mouse-button-down on-mouse-button-down
   :on-mouse-button-up on-mouse-button-up
   :on-mouse-motion on-mouse-motion
   :on-mouse-wheel on-mouse-wheel
   :on-gamepad-button-down (fn [_self _payload] nil)
   :on-gamepad-axis-motion (fn [_self _payload] nil)
   :on-gamepad-removed (fn [_self _payload] nil)
   :drag-active? drag-active?
   :drag-engaged? drag-engaged?
   :update update
   :drop drop})

CanvasControls
