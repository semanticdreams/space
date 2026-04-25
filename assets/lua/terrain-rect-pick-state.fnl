(local State (require :state))
(local Routes (require :state-routes))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchPointer (require :state-handlers/touch-pointer))
(local PenPointer (require :state-handlers/pen-pointer))
(local CameraHandlers (require :state-handlers/camera))
(local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
(local {: entry : section} (require :command-hints))


(fn active-session []
  (TerrainRectPickManager.active-session))

(fn cleanup-if-needed []
  (TerrainRectPickManager.cleanup-inactive-session))

(fn TerrainRectPickState []
  (var pending-motion nil)
  (local PenHandlers
    (PenPointer.PenPointerHandlers
      {:touch-policy {:suppress-touch-when :down
                      :suppression-timeout-ms 150
                      :allow-touch-during-hover? true}}))
  (local TouchHandlers
    (TouchPointer.TouchPointerHandlers
      {:allow-touch? (fn [payload]
                       (PenHandlers:touch-allowed? payload))}))

  (fn flush-pending-motion [session]
    (when (and session pending-motion)
      (session:update-drag pending-motion)
      (set pending-motion nil)))

  (local TerrainRectPick
    {:enter (fn [_ctx]
              (when (not (active-session))
                (cleanup-if-needed)))
     :leave (fn [_ctx]
              (set pending-motion nil)
              nil)
     :key-down (fn [ctx payload]
                 (local session (active-session))
                 (if session
                     (do
                       (local handled (session:on-key-down payload))
                       (when handled
                         ((. ctx :mark-command-executed!)))
                       (cleanup-if-needed)
                       handled)
                     (do
                       (cleanup-if-needed)
                       false)))
     :mouse-button-down (fn [ctx payload]
                          (local session (active-session))
                          (when (and session (= payload.button 1))
                            ((. ctx :mark-command-executed!))
                            (set pending-motion nil)
                            (session:begin-drag {:x payload.x
                                                 :y payload.y
                                                 :mod payload.mod
                                                 :timestamp payload.timestamp})
                            (cleanup-if-needed))
                          true)
     :mouse-button-up (fn [ctx payload]
                        (local session (active-session))
                        (when (and session (= payload.button 1))
                          ((. ctx :mark-command-executed!))
                          (flush-pending-motion session)
                          (session:end-drag {:x payload.x
                                             :y payload.y
                                             :mod payload.mod
                                             :timestamp payload.timestamp})
                          (cleanup-if-needed))
                        true)
     :mouse-motion (fn [_ctx payload]
                     (local session (active-session))
                     (when session
                       (set pending-motion {:x payload.x
                                            :y payload.y
                                            :mod payload.mod
                                            :timestamp payload.timestamp})
                       (cleanup-if-needed))
                     true)
     :updated (fn [_ctx _delta]
                (local session (active-session))
                (flush-pending-motion session)
                (cleanup-if-needed)
                true)})

  (local state
    (State
      {:name :terrain-rect-pick
       :route-wrappers [Routes.CommandHints]
       :command_hints_provider (fn [_ctx]
                                 [(section :mode
                                           "MODE"
                                           [(entry "drag" "select-rect" {:priority 10})
                                            (entry "esc" "cancel" {:priority 20})])])
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
                :key-down (Routes.FirstHandlerWins [TerrainRectPick])
                :mouse-button-down (Routes.FirstHandlerWins [TerrainRectPick])
                :mouse-button-up (Routes.FirstHandlerWins [TerrainRectPick])
                :mouse-motion (Routes.FirstHandlerWins [TerrainRectPick])
                :mouse-wheel (Routes.FirstHandlerWins [PointerHandlers.InputMouseWheelDispatch
                                                      PointerHandlers.HoveredMouseWheel
                                                      PointerHandlers.CameraMouseWheel])
                :updated (Routes.Chain [TerrainRectPick
                                        CameraHandlers.CameraUpdated])}
       :enter [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               TerrainRectPick]
       :leave [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               TerrainRectPick]}))
  state)

TerrainRectPickState
