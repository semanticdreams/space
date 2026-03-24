(local StateBase (require :state-base))
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

  (fn handle-enter []
    (when (not (active-session))
      (cleanup-if-needed)))

  (fn handle-leave []
    (set pending-motion nil))

  (fn handle-key-down [payload]
    (local session (active-session))
    (if session
        (do
          (session:on-key-down payload)
          (cleanup-if-needed)
          true)
        (do
          (cleanup-if-needed)
          true)))

  (fn handle-mouse-button-down [payload]
    (local session (active-session))
    (when (and session (= payload.button 1))
      (set pending-motion nil)
      (session:begin-stroke {:x payload.x
                             :y payload.y
                             :mod payload.mod
                             :timestamp payload.timestamp})
      (cleanup-if-needed))
    true)

  (fn handle-mouse-button-up [payload]
    (local session (active-session))
    (when (and session (= payload.button 1))
      (flush-pending-motion session)
      (session:end-stroke {:x payload.x
                           :y payload.y
                           :mod payload.mod
                           :timestamp payload.timestamp})
      (cleanup-if-needed))
    true)

  (fn handle-mouse-motion [payload]
    (local session (active-session))
    (when session
      (set pending-motion {:x payload.x
                           :y payload.y
                           :mod payload.mod
                           :timestamp payload.timestamp})
      (cleanup-if-needed))
    true)

  (fn handle-updated [_delta]
    (local session (active-session))
    (flush-pending-motion session)
    (cleanup-if-needed)
    true)

  (StateBase.make-state
    {:name :terrain-paint
     :on-enter handle-enter
     :on-leave handle-leave
     :on-key-down handle-key-down
     :on-mouse-button-down handle-mouse-button-down
     :on-mouse-button-up handle-mouse-button-up
     :on-mouse-motion handle-mouse-motion
     :on-updated handle-updated}))

TerrainPaintState
