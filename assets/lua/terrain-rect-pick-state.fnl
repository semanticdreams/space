(local StateBase (require :state-base))
(local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
(local TerrainPickOverlay (require :graph/view/terrain-pick-overlay))


(fn active-session []
  (TerrainRectPickManager.active-session))

(fn cleanup-if-needed []
  (TerrainRectPickManager.cleanup-inactive-session))

(fn TerrainRectPickState []
  (var overlay nil)
  (var pending-motion nil)

  (fn request-hud [request]
    (or (and request request.hud)
        app.hud))

  (fn ensure-overlay [request]
    (if overlay
        overlay
        (do
          (set overlay (TerrainPickOverlay {:hud (request-hud request)}))
          overlay)))

  (fn clear-overlay []
    (when overlay
      (overlay:drop)
      (set overlay nil)))

  (fn cancel-overlay []
    (when overlay
      (overlay:cancel)))

  (fn sync-overlay [session payload]
    (when (and session payload (session:drag-active?))
      (local next-overlay (ensure-overlay session))
      (if (next-overlay:active?)
          (next-overlay:update payload)
          (next-overlay:begin payload))))

  (fn flush-pending-motion [session]
    (when (and session pending-motion)
      (session:update-drag pending-motion)
      (sync-overlay session pending-motion)
      (set pending-motion nil)))

  (fn handle-enter []
    (when (not (active-session))
      (cleanup-if-needed)))

  (fn handle-leave []
    (set pending-motion nil)
    (clear-overlay))

  (fn handle-key-down [payload]
    (local session (active-session))
    (if session
        (do
          (cancel-overlay)
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
      (session:begin-drag {:x payload.x
                           :y payload.y
                           :mod payload.mod
                           :timestamp payload.timestamp})
      (sync-overlay session payload)
      (cleanup-if-needed))
    true)

  (fn handle-mouse-button-up [payload]
    (local session (active-session))
    (when (and session (= payload.button 1))
      (flush-pending-motion session)
      (when overlay
        (overlay:finish))
      (session:end-drag {:x payload.x
                         :y payload.y
                         :mod payload.mod
                         :timestamp payload.timestamp})
      (cleanup-if-needed))
    true)

  (fn handle-mouse-motion [payload]
    (local session (active-session))
    (when session
      (sync-overlay session payload)
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
    {:name :terrain-rect-pick
     :on-enter handle-enter
     :on-leave handle-leave
     :on-key-down handle-key-down
     :on-mouse-button-down handle-mouse-button-down
     :on-mouse-button-up handle-mouse-button-up
     :on-mouse-motion handle-mouse-motion
     :on-updated handle-updated}))

TerrainRectPickState
