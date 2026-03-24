

(fn current-state-name []
  (and app.states app.states.active-name (app.states.active-name)))

(fn restore-previous-state []
  (local previous (or app.terrain-rect-pick-previous-state :normal))
  (set app.terrain-rect-pick-previous-state nil)
  (when (and app.states app.states.set-state)
    (app.states.set-state previous)))

(fn clear-active-session []
  (set app.terrain-rect-pick-session nil)
  nil)

(fn active-session []
  (local session app.terrain-rect-pick-session)
  (if (and session session.active? (session:active?))
      session
      nil))

(fn cleanup-inactive-session []
  (local session app.terrain-rect-pick-session)
  (if (active-session)
      false
      (if (or session
              (= (current-state-name) :terrain-rect-pick))
          (do
            (clear-active-session)
            (restore-previous-state)
            true)
          false)))

(fn cancel-active-session []
  (local session (active-session))
  (when session
    (session:cancel-selection))
  (clear-active-session)
  (restore-previous-state)
  true)

(fn begin [session]
  (assert session "TerrainRectPickManager.begin requires a session")
  (when (active-session)
    (cancel-active-session))
  (local current (current-state-name))
  (set app.terrain-rect-pick-session session)
  (set app.terrain-rect-pick-previous-state
       (if (= current :terrain-rect-pick)
           (or app.terrain-rect-pick-previous-state :normal)
           (or current :normal)))
  (session:begin)
  (when (and app.states app.states.set-state)
    (app.states.set-state :terrain-rect-pick))
  session)

{:begin begin
 :active-session active-session
 :cleanup-inactive-session cleanup-inactive-session
 :cancel-active-session cancel-active-session}
