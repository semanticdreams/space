(local PenActivity (require :pen-activity))

(local SDL_BUTTON_LEFT 1)
(local SDL_PEN_MOUSEID -2)

(fn ensure-mouse-signal [name]
  (local events (and app.engine app.engine.events))
  (assert events "PenPointerHandlers requires app.engine.events")
  (local signal (. events name))
  (assert signal (.. "PenPointerHandlers requires engine event signal " name))
  signal)

(fn make-pen-mouse-payload [payload]
  {:button SDL_BUTTON_LEFT
   :state true
   :clicks 1
   :x (or (and payload payload.x) 0)
   :y (or (and payload payload.y) 0)
   :xrel (or (and payload payload.xrel) 0)
   :yrel (or (and payload payload.yrel) 0)
   :which SDL_PEN_MOUSEID
   :mod (or (and payload payload.mod) 0)
   :timestamp (and payload payload.timestamp)
   :synthetic? true
   :source :pen
   :pen-id (and payload payload.pen-id)
   :pen-state (and payload payload.pen-state)
   :eraser (and payload payload.eraser)
   :in-range (and payload payload.in-range)
   :pressure (and payload payload.pressure)
   :x-tilt (and payload payload.x-tilt)
   :y-tilt (and payload payload.y-tilt)
   :distance (and payload payload.distance)
   :rotation (and payload payload.rotation)
   :slider (and payload payload.slider)
   :tangential-pressure (and payload payload.tangential-pressure)})

(fn emit-mouse-motion [payload]
  (local signal (ensure-mouse-signal "mouse-motion"))
  (signal:emit (make-pen-mouse-payload payload)))

(fn emit-mouse-button-down [payload]
  (local signal (ensure-mouse-signal "mouse-button-down"))
  (signal:emit (make-pen-mouse-payload payload)))

(fn emit-mouse-button-up [payload]
  (local signal (ensure-mouse-signal "mouse-button-up"))
  (local mouse-payload (make-pen-mouse-payload payload))
  (set mouse-payload.state false)
  (signal:emit mouse-payload))

(fn PenPointerHandlers [opts]
  (local options (or opts {}))
  (local synthesize-hover? (not (= options.synthesize-hover? false)))
  (local synthesize-pointer? (not (= options.synthesize-pointer? false)))
  (local clear-hover-on-proximity-out? (not (= options.clear-hover-on-proximity-out? false)))
  (local activity (PenActivity (or options.touch-policy {})))

  (fn update-pointer-override! [payload]
    (set app.pointer-input-override
         {:x (or (and payload payload.x) 0)
          :y (or (and payload payload.y) 0)
          :xrel (or (and payload payload.xrel) 0)
          :yrel (or (and payload payload.yrel) 0)
          :source :pen
          :pen-id (and payload payload.pen-id)
          :timestamp (and payload payload.timestamp)}))

  (fn clear-pointer-override! []
    (when (= (and app.pointer-input-override app.pointer-input-override.source) :pen)
      (set app.pointer-input-override nil)))

  (fn clear-hover! []
    (when (and clear-hover-on-proximity-out? app.hoverables app.hoverables.clear-active)
      (app.hoverables:clear-active)))

  (local PenProximityIn
    {:pen-proximity-in
     (fn [_ctx payload]
       (activity:on-pen-proximity-in payload)
       (when synthesize-hover?
         (update-pointer-override! payload))
       false)})

  (local PenProximityOut
    {:pen-proximity-out
     (fn [_ctx payload]
       (activity:on-pen-proximity-out payload)
       (clear-pointer-override!)
       (clear-hover!)
       false)})

  (local PenMotion
    {:pen-motion
     (fn [_ctx payload]
       (activity:on-pen-motion payload)
       (when synthesize-hover?
         (update-pointer-override! payload)
         (emit-mouse-motion payload))
       false)})

  (local PenDown
    {:pen-down
     (fn [_ctx payload]
       (activity:on-pen-down payload)
       (update-pointer-override! payload)
       (when synthesize-pointer?
         (emit-mouse-button-down payload))
       false)})

  (local PenUp
    {:pen-up
     (fn [_ctx payload]
       (activity:on-pen-up payload)
       (when synthesize-pointer?
         (emit-mouse-button-up payload))
       false)})

  (local PenButtonDown
    {:pen-button-down
     (fn [_ctx payload]
       (activity:on-pen-button payload)
       false)})

  (local PenButtonUp
    {:pen-button-up
     (fn [_ctx payload]
       (activity:on-pen-button payload)
       false)})

  (local PenAxis
    {:pen-axis
     (fn [_ctx payload]
       (activity:on-pen-axis payload)
       false)})

  (local PenLifecycle
    {:enter (fn [_ctx]
              (activity:reset)
              (clear-pointer-override!))
     :leave (fn [_ctx]
              (activity:reset)
              (clear-pointer-override!)
              (clear-hover!))})

  {:PenProximityIn PenProximityIn
   :PenProximityOut PenProximityOut
   :PenMotion PenMotion
   :PenDown PenDown
   :PenUp PenUp
   :PenButtonDown PenButtonDown
   :PenButtonUp PenButtonUp
   :PenAxis PenAxis
   :PenLifecycle PenLifecycle
   :touch-allowed? (fn [_self payload]
                     (activity:touch-allowed? payload))
   :pen-active? (fn [_self payload]
                  (activity:pen-active? (and payload payload.timestamp)))
   :reset (fn []
            (activity:reset)
            (clear-pointer-override!)
            true)})

(local default-handlers (PenPointerHandlers {}))

{:PenPointerHandlers PenPointerHandlers
 :PenProximityIn default-handlers.PenProximityIn
 :PenProximityOut default-handlers.PenProximityOut
 :PenMotion default-handlers.PenMotion
 :PenDown default-handlers.PenDown
 :PenUp default-handlers.PenUp
 :PenButtonDown default-handlers.PenButtonDown
 :PenButtonUp default-handlers.PenButtonUp
 :PenAxis default-handlers.PenAxis
 :PenLifecycle default-handlers.PenLifecycle
 :touch-allowed? default-handlers.touch-allowed?
 :pen-active? default-handlers.pen-active?
 :reset default-handlers.reset}
