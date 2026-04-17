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
  (var touch-transform-active? false)

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

  (fn plane-hit-at [pointer projection]
    (when (and canvas canvas.screen-pos-ray pointer)
      (local ray (canvas:screen-pos-ray pointer {:projection projection}))
      (when (and ray ray.origin ray.direction)
        (local dz (or ray.direction.z 0))
        (when (not (= dz 0))
          (local t (/ (- 0 ray.origin.z) dz))
          (+ ray.origin (* ray.direction t))))))

  (fn plane-hit [projection]
    (plane-hit-at (pointer-position) projection))

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

  (fn clamp-scale [value]
    (clamp value min-scale max-scale))

  (fn valid-touch-gesture? [gesture]
    (and gesture
         gesture.centroid
         gesture.previous-centroid
         (= (or gesture.count 0) 2)))

  (fn on-touch-transform-start [_self gesture]
    (if (valid-touch-gesture? gesture)
        (do
          (set touch-transform-active? true)
          true)
        false))

  (fn on-touch-transform [_self gesture]
    (if (not (valid-touch-gesture? gesture))
        false
        (do
          (set touch-transform-active? true)
          (local previous-projection canvas.projection)
          (local anchor-before
            (plane-hit-at gesture.previous-centroid previous-projection))
          (local previous-span (or gesture.previous-span 0))
          (local span (or gesture.span 0))
          (when (and (> previous-span 1e-5)
                     (> span 1e-5)
                     canvas.set-scale-factor
                     (finite-number? canvas.scale-factor))
            (canvas:set-scale-factor
              (clamp-scale (* canvas.scale-factor (/ previous-span span)))))
          (local anchor-after
            (plane-hit-at gesture.centroid canvas.projection))
          (when (and anchor-before anchor-after)
            (camera:set-position
              (+ camera.position
                 (glm.vec3 (- anchor-before.x anchor-after.x)
                           (- anchor-before.y anchor-after.y)
                           0))))
          true)))

  (fn on-touch-transform-end [_self _payload]
    (set touch-transform-active? false)
    true)

  (fn drag-active? [_self]
    (or (not (= drag-start nil))
        touch-transform-active?))

  (fn drag-engaged? [self]
    (self:drag-active?))

  (fn update [_self _delta]
    nil)

  (fn drop [_self]
    (clear-pan-origin)
    (set touch-transform-active? false)
    (set mouse-pos nil))

  {:on-key-down (fn [_self _payload] nil)
   :on-key-up (fn [_self _payload] nil)
   :on-mouse-button-down on-mouse-button-down
   :on-mouse-button-up on-mouse-button-up
   :on-mouse-motion on-mouse-motion
   :on-mouse-wheel on-mouse-wheel
   :on-touch-transform-start on-touch-transform-start
   :on-touch-transform on-touch-transform
   :on-touch-transform-end on-touch-transform-end
   :on-gamepad-button-down (fn [_self _payload] nil)
   :on-gamepad-axis-motion (fn [_self _payload] nil)
   :on-gamepad-removed (fn [_self _payload] nil)
   :drag-active? drag-active?
   :drag-engaged? drag-engaged?
   :update update
   :drop drop})

CanvasControls
