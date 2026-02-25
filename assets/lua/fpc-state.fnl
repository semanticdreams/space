(local StateBase (require :state-base))

(local KEY_ESCAPE 27)

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn dispatch-control [handler payload]
  (when (and app.first-person-controls handler)
    (handler app.first-person-controls payload)))

(fn FpcState []
  (local handlers
    {:on-text-input (fn [_payload] false)
     :on-key-down (fn [payload]
                    (if (= (and payload payload.key) KEY_ESCAPE)
                        (do (set-state :normal) true)
                        (dispatch-control (. app.first-person-controls :on-key-down) payload)))
     :on-key-up (fn [payload]
                  (dispatch-control (. app.first-person-controls :on-key-up) payload))
     :on-mouse-button-up (fn [payload]
                           (dispatch-control (. app.first-person-controls :on-mouse-button-up) payload))
     :on-mouse-button-down (fn [payload]
                             (dispatch-control (. app.first-person-controls :on-mouse-button-down) payload))
     :on-mouse-motion (fn [payload]
                        (dispatch-control (. app.first-person-controls :on-mouse-motion) payload))
     :on-mouse-wheel (fn [payload]
                       (dispatch-control (. app.first-person-controls :on-mouse-wheel) payload))
     :on-gamepad-button-down (fn [payload]
                                  (dispatch-control (. app.first-person-controls :on-gamepad-button-down) payload))
     :on-gamepad-axis-motion (fn [payload]
                                  (dispatch-control (. app.first-person-controls :on-gamepad-axis-motion) payload))
     :on-gamepad-removed (fn [payload]
                                     (dispatch-control (. app.first-person-controls :on-gamepad-removed) payload))
     :on-updated (fn [delta]
                   (dispatch-control (. app.first-person-controls :update) delta))})

  (fn on-enter []
    (app.engine.events.text-input.connect handlers.on-text-input)
    (app.engine.events.key-up.connect handlers.on-key-up)
    (app.engine.events.key-down.connect handlers.on-key-down)
    (app.engine.events.mouse-button-up.connect handlers.on-mouse-button-up)
    (app.engine.events.mouse-button-down.connect handlers.on-mouse-button-down)
    (app.engine.events.mouse-motion.connect handlers.on-mouse-motion)
    (app.engine.events.mouse-wheel.connect handlers.on-mouse-wheel)
    (app.engine.events.gamepad-button-down.connect handlers.on-gamepad-button-down)
    (app.engine.events.gamepad-axis-motion.connect handlers.on-gamepad-axis-motion)
    (app.engine.events.gamepad-removed.connect handlers.on-gamepad-removed)
    (app.engine.events.updated.connect handlers.on-updated))

  (fn on-leave []
    (app.engine.events.text-input.disconnect handlers.on-text-input)
    (app.engine.events.key-up.disconnect handlers.on-key-up)
    (app.engine.events.key-down.disconnect handlers.on-key-down)
    (app.engine.events.mouse-button-up.disconnect handlers.on-mouse-button-up)
    (app.engine.events.mouse-button-down.disconnect handlers.on-mouse-button-down)
    (app.engine.events.mouse-motion.disconnect handlers.on-mouse-motion)
    (app.engine.events.mouse-wheel.disconnect handlers.on-mouse-wheel)
    (app.engine.events.gamepad-button-down.disconnect handlers.on-gamepad-button-down)
    (app.engine.events.gamepad-axis-motion.disconnect handlers.on-gamepad-axis-motion)
    (app.engine.events.gamepad-removed.disconnect handlers.on-gamepad-removed)
    (app.engine.events.updated.disconnect handlers.on-updated))

  {:name :fpc
   :on-enter on-enter
   :on-leave on-leave
   :on-key-down handlers.on-key-down
   :on-key-up handlers.on-key-up
   :on-mouse-button-up handlers.on-mouse-button-up
   :on-mouse-button-down handlers.on-mouse-button-down
   :on-mouse-motion handlers.on-mouse-motion
   :on-mouse-wheel handlers.on-mouse-wheel
   :on-gamepad-button-down handlers.on-gamepad-button-down
   :on-gamepad-axis-motion handlers.on-gamepad-axis-motion
   :on-gamepad-removed handlers.on-gamepad-removed
   :on-updated handlers.on-updated
   :on-text-input handlers.on-text-input
   :handle-focus-tab StateBase.handle-focus-tab
   :shift-held? StateBase.shift-held?})

FpcState
