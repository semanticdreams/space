(local State (require :state))
(local Routes (require :state-routes))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchHandlers (require :state-handlers/touch-pointer))
(local CameraHandlers (require :state-handlers/camera))
(local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))


(fn active-session []
  (TerrainRectPickManager.active-session))

(fn cleanup-if-needed []
  (TerrainRectPickManager.cleanup-inactive-session))

(fn TerrainRectPickState []
  (var pending-motion nil)

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
     :key-down (fn [_ctx payload]
                 (local session (active-session))
                 (if session
                     (do
                       (session:on-key-down payload)
                       (cleanup-if-needed)
                       true)
                     (do
                       (cleanup-if-needed)
                       true)))
     :mouse-button-down (fn [_ctx payload]
                          (local session (active-session))
                          (when (and session (= payload.button 1))
                            (set pending-motion nil)
                            (session:begin-drag {:x payload.x
                                                 :y payload.y
                                                 :mod payload.mod
                                                 :timestamp payload.timestamp})
                            (cleanup-if-needed))
                          true)
     :mouse-button-up (fn [_ctx payload]
                        (local session (active-session))
                        (when (and session (= payload.button 1))
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

  (State
    {:name :terrain-rect-pick
     :routes {:touch-down (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseDown])
              :touch-motion (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseMotion])
              :touch-up (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseUp])
              :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseCanceled])
              :key-down (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-button-down (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-button-up (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-motion (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-wheel (Routes.FirstHandlerWins [PointerHandlers.InputMouseWheelDispatch
                                                    PointerHandlers.HoveredMouseWheel
                                                    PointerHandlers.CameraMouseWheel])
              :updated (Routes.Chain [TerrainRectPick
                                      CameraHandlers.CameraUpdated])}
     :enter [TouchHandlers.TouchLifecycle
             TerrainRectPick]
     :leave [TouchHandlers.TouchLifecycle
             TerrainRectPick]}))

TerrainRectPickState
