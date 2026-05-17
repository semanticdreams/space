(local StateSystemRuntime (require :state-system-runtime))

(fn set-states-provider [provider]
  (StateSystemRuntime.set-states-provider provider))

(fn require-states-host [action]
  (StateSystemRuntime.states-host "TerrainPaintManager" action))

(fn current-state-name []
  (local states (require-states-host "current-state-name"))
  (assert states.active-name
          "TerrainPaintManager states host must expose :active-name")
  (states:active-name))

(fn restore-previous-state []
  (local previous app.terrain-paint-previous-state)
  (assert previous
          "TerrainPaintManager requires a recorded previous state to restore")
  (local states (require-states-host "restore-previous-state"))
  (set app.terrain-paint-previous-state nil)
  (assert states.set-state
          "TerrainPaintManager states host must expose :set-state")
  (states:set-state previous))

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
  (assert current
          "TerrainPaintManager.begin requires an active state")
  (set app.terrain-paint-session session)
  (set app.terrain-paint-previous-state
       (if (= current :terrain-paint)
           (do
             (assert app.terrain-paint-previous-state
                     "TerrainPaintManager.begin requires previous state when already in terrain-paint")
             app.terrain-paint-previous-state)
           current))
  (session:begin)
  (local states (require-states-host "begin"))
  (assert states.set-state
          "TerrainPaintManager states host must expose :set-state")
  (states:set-state :terrain-paint)
  session)

{:begin begin
 :active-session active-session
 :cleanup-inactive-session cleanup-inactive-session
 :cleanup-session cleanup-session
 :cancel-active-session cancel-active-session
 :set-states-provider set-states-provider}
