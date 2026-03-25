(local State (require :state))
(local Routes (require :state-routes))

(local KEY_ESCAPE 27)

(fn dispatch-control [handler payload]
  (when (and app.first-person-controls handler)
    (handler app.first-person-controls payload)))

(fn FpcState []
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
     :routes {:text-input (Routes.FirstHandlerWins [ControlsOnly])
              :key-down (Routes.FirstHandlerWins [ControlsOnly])
              :key-up (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-button-up (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-button-down (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-motion (Routes.FirstHandlerWins [ControlsOnly])
              :mouse-wheel (Routes.FirstHandlerWins [ControlsOnly])
              :gamepad-button-down (Routes.FirstHandlerWins [ControlsOnly])
              :gamepad-axis-motion (Routes.FirstHandlerWins [ControlsOnly])
              :gamepad-removed (Routes.FirstHandlerWins [ControlsOnly])
              :updated (Routes.FirstHandlerWins [ControlsOnly])}}))

FpcState
