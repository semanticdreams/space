
(fn current-state-name []
  (and app.states app.states.active-name (app.states.active-name)))

(fn restore-previous-state []
  (local previous (or app.terrain-paint-previous-state :normal))
  (set app.terrain-paint-previous-state nil)
  (when (and app.states app.states.set-state)
    (app.states.set-state previous)))

(fn clear-previous-state []
  (set app.terrain-paint-previous-state nil)
  nil)

(fn clear-active-session []
  (set app.terrain-paint-session nil)
  nil)

(fn active-session []
  (local session app.terrain-paint-session)
  (if (and session session.active? (session:active?))
      session
      nil))

(fn cleanup-inactive-session []
  (local session app.terrain-paint-session)
  (if (active-session)
      false
      (if (or session
              (= (current-state-name) :terrain-paint))
          (do
            (clear-active-session)
            (if (= (current-state-name) :terrain-paint)
                (restore-previous-state)
                (clear-previous-state))
            true)
          false)))

(fn cleanup-session [session]
  (if (= app.terrain-paint-session session)
      (do
        (clear-active-session)
        (if (= (current-state-name) :terrain-paint)
            (restore-previous-state)
            (clear-previous-state))
        true)
      false))

(fn cancel-active-session []
  (local session (active-session))
  (when session
    (session:cancel-selection))
  (clear-active-session)
  (restore-previous-state)
  true)

(fn begin [session]
  (assert session "TerrainPaintManager.begin requires a session")
  (when (active-session)
    (cancel-active-session))
  (local current (current-state-name))
  (set app.terrain-paint-session session)
  (set app.terrain-paint-previous-state
       (if (= current :terrain-paint)
           (or app.terrain-paint-previous-state :normal)
           (or current :normal)))
  (session:begin)
  (when (and app.states app.states.set-state)
    (app.states.set-state :terrain-paint))
  session)

{:begin begin
 :active-session active-session
 :cleanup-inactive-session cleanup-inactive-session
 :cleanup-session cleanup-session
 :cancel-active-session cancel-active-session}
