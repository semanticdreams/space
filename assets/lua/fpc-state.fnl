(local State (require :state))
(local Routes (require :state-routes))
(local TouchHandlers (require :state-handlers/touch-pointer))
(local PenPointer (require :state-handlers/pen-pointer))

(local KEY_ESCAPE 27)

(fn dispatch-control [handler payload]
  (when (and app.first-person-controls handler)
    (handler app.first-person-controls payload)))

(fn FpcState []
  (local PenHandlers (PenPointer.PenPointerHandlers {}))

  (local ControlsOnly
    {:text-input (fn [_ctx _payload] false)
     :key-down (fn [ctx payload]
                 (if (= (and payload payload.key) KEY_ESCAPE)
                     (do ((. ctx :set-state) :normal) true)
                     (dispatch-control (. app.first-person-controls :on-key-down) payload)))
     :key-up (fn [_ctx payload]
               (dispatch-control (. app.first-person-controls :on-key-up) payload))
     :mouse-button-up (fn [_ctx payload]
                        (dispatch-control (. app.first-person-controls :on-mouse-button-up) payload))
     :mouse-button-down (fn [_ctx payload]
                          (dispatch-control (. app.first-person-controls :on-mouse-button-down) payload))
     :mouse-motion (fn [_ctx payload]
                     (dispatch-control (. app.first-person-controls :on-mouse-motion) payload))
     :mouse-wheel (fn [_ctx payload]
                    (dispatch-control (. app.first-person-controls :on-mouse-wheel) payload))
     :gamepad-button-down (fn [_ctx payload]
                            (dispatch-control (. app.first-person-controls :on-gamepad-button-down) payload))
     :gamepad-axis-motion (fn [_ctx payload]
                            (dispatch-control (. app.first-person-controls :on-gamepad-axis-motion) payload))
     :gamepad-removed (fn [_ctx payload]
                        (dispatch-control (. app.first-person-controls :on-gamepad-removed) payload))
     :updated (fn [_ctx delta]
                (dispatch-control (. app.first-person-controls :update) delta))})

  (State
    {:name :fpc
     :routes {:touch-down (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseDown])
              :touch-motion (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseMotion])
              :touch-up (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseUp])
              :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseCanceled])
              :pen-proximity-in (Routes.Chain [PenHandlers.PenProximityIn])
              :pen-proximity-out (Routes.Chain [PenHandlers.PenProximityOut])
              :pen-motion (Routes.Chain [PenHandlers.PenMotion])
              :pen-down (Routes.Chain [PenHandlers.PenDown])
              :pen-up (Routes.Chain [PenHandlers.PenUp])
              :pen-button-down (Routes.Chain [PenHandlers.PenButtonDown])
              :pen-button-up (Routes.Chain [PenHandlers.PenButtonUp])
              :pen-axis (Routes.Chain [PenHandlers.PenAxis])
              :text-input (Routes.FirstHandlerWins [ControlsOnly])
              :key-down (Routes.FirstHandlerWins [ControlsOnly])
              :key-up (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-button-up (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-button-down (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-motion (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-wheel (Routes.FirstHandlerWins [ControlsOnly])
              :gamepad-button-down (Routes.FirstHandlerWins [ControlsOnly])
              :gamepad-axis-motion (Routes.FirstHandlerWins [ControlsOnly])
              :gamepad-removed (Routes.FirstHandlerWins [ControlsOnly])
              :updated (Routes.FirstHandlerWins [ControlsOnly])}
     :enter [PenHandlers.PenLifecycle
             TouchHandlers.TouchLifecycle]
     :leave [PenHandlers.PenLifecycle
             TouchHandlers.TouchLifecycle]}))

FpcState
