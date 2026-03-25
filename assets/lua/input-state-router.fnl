(var active-input nil)

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn set-text-input-enabled [enabled?]
  (when (and app.engine app.engine.set-text-input-enabled)
    (app.engine.set-text-input-enabled enabled?)))

(fn current-state-name []
  (and app.engine
       app.states
       app.states.active-name
       (app.states.active-name)))

(fn release-active-input []
  (when active-input
    (local handler active-input.on-state-disconnected)
    (when handler
      (active-input:on-state-disconnected {:state (current-state-name)}))
    (set active-input nil)
    (set-text-input-enabled false)
    (when (or (= (current-state-name) :text)
              (= (current-state-name) :insert))
      (set-state :normal))))

(fn connect-input [input]
  (when (not (= input active-input))
    (release-active-input)
    (when input
      (set active-input input)
      (set-text-input-enabled true)
      (local handler input.on-state-connected)
      (when handler
        (input:on-state-connected {:state (current-state-name)}))))
  active-input)

(fn disconnect-input [input]
  (when (and active-input (= input active-input))
    (release-active-input))
  active-input)

(fn reset []
  (set active-input nil)
  (set-text-input-enabled false)
  nil)

(fn dispatch-input [method payload]
  (local current active-input)
  (if (and current method (. current method))
      ((. current method) current payload)
      false))

{:connect-input connect-input
 :disconnect-input disconnect-input
 :dispatch-input dispatch-input
 :active-input (fn [] active-input)
 :reset reset
 :release-active-input release-active-input}

;
