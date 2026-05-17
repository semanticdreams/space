
(local StateSystemRuntime (require :state-system-runtime))

(fn set-states-provider [provider]
  (StateSystemRuntime.set-states-provider provider))

(fn require-states-host [action]
  (StateSystemRuntime.states-host "TerrainRectPickManager" action))

(fn current-state-name []
  (local states (require-states-host "current-state-name"))
  (assert states.active-name
          "TerrainRectPickManager states host must expose :active-name")
  (states:active-name))

(fn restore-previous-state []
  (local previous app.terrain-rect-pick-previous-state)
  (assert previous
          "TerrainRectPickManager requires a recorded previous state to restore")
  (local states (require-states-host "restore-previous-state"))
  (set app.terrain-rect-pick-previous-state nil)
  (assert states.set-state
          "TerrainRectPickManager states host must expose :set-state")
  (states:set-state previous))

(fn clear-previous-state []
  (set app.terrain-rect-pick-previous-state nil)
  nil)

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
            (if (= (current-state-name) :terrain-rect-pick)
                (restore-previous-state)
                (clear-previous-state))
            true)
          false)))

(fn cleanup-session [session]
  (if (= app.terrain-rect-pick-session session)
      (do
        (clear-active-session)
        (if (= (current-state-name) :terrain-rect-pick)
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
  (assert session "TerrainRectPickManager.begin requires a session")
  (when (active-session)
    (cancel-active-session))
  (local current (current-state-name))
  (assert current
          "TerrainRectPickManager.begin requires an active state")
  (set app.terrain-rect-pick-session session)
  (set app.terrain-rect-pick-previous-state
       (if (= current :terrain-rect-pick)
           (do
             (assert app.terrain-rect-pick-previous-state
                     "TerrainRectPickManager.begin requires previous state when already in terrain-rect-pick")
             app.terrain-rect-pick-previous-state)
           current))
  (session:begin)
  (local states (require-states-host "begin"))
  (assert states.set-state
          "TerrainRectPickManager states host must expose :set-state")
  (states:set-state :terrain-rect-pick)
  session)

{:begin begin
 :active-session active-session
 :cleanup-inactive-session cleanup-inactive-session
 :cleanup-session cleanup-session
 :cancel-active-session cancel-active-session
 :set-states-provider set-states-provider}
