(local State (require :state))
(local Routes (require :state-routes))
(local Defaults (require :state-defaults))
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
     :mouse-wheel (fn [_ctx _payload] true)
     :updated (fn [_ctx _delta]
                (local session (active-session))
                (flush-pending-motion session)
                (cleanup-if-needed)
                true)})

  (State
    {:name :terrain-rect-pick
     :routes {:key-down (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-button-down (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-button-up (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-motion (Routes.FirstHandlerWins [TerrainRectPick])
              :mouse-wheel (Routes.FirstHandlerWins [TerrainRectPick])
              :updated (Routes.Broadcast [TerrainRectPick])}
     :enter [Defaults.HoverLifecycle TerrainRectPick]
     :leave [Defaults.HoverLifecycle TerrainRectPick]}))

TerrainRectPickState
