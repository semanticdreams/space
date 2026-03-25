(local State (require :state))
(local Routes (require :state-routes))
(local TerrainPaintManager (require :graph/view/terrain-paint-manager))

(fn active-session []
  (TerrainPaintManager.active-session))

(fn cleanup-if-needed []
  (TerrainPaintManager.cleanup-inactive-session))

(fn TerrainPaintState []
  (var pending-motion nil)

  (fn flush-pending-motion [session]
    (when (and session pending-motion)
      (session:update-stroke pending-motion)
      (set pending-motion nil)))

  (local TerrainPaint
    {:enter (fn [_ctx]
              (when (not (active-session))
                (cleanup-if-needed)))
     :leave (fn [_ctx]
              (set pending-motion nil))
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
                            (session:begin-stroke {:x payload.x
                                                   :y payload.y
                                                   :mod payload.mod
                                                   :timestamp payload.timestamp})
                            (cleanup-if-needed))
                          true)
     :mouse-button-up (fn [_ctx payload]
                        (local session (active-session))
                        (when (and session (= payload.button 1))
                          (flush-pending-motion session)
                          (session:end-stroke {:x payload.x
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
    {:name :terrain-paint
     :routes {:key-down (Routes.FirstHandlerWins [TerrainPaint])
              :mouse-button-down (Routes.FirstHandlerWins [TerrainPaint])
              :mouse-button-up (Routes.FirstHandlerWins [TerrainPaint])
              :mouse-motion (Routes.FirstHandlerWins [TerrainPaint])
              :updated (Routes.Broadcast [TerrainPaint])}
     :enter [TerrainPaint]
     :leave [TerrainPaint]}))

TerrainPaintState
