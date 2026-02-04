(var active-input nil)

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

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
    (when (or (= (current-state-name) :text)
              (= (current-state-name) :insert))
      (set-state :normal))))

(fn connect-input [input]
  (when (not (= input active-input))
    (release-active-input)
    (when input
      (set active-input input)
      (local handler input.on-state-connected)
      (when handler
        (input:on-state-connected {:state (current-state-name)}))))
  active-input)

(fn disconnect-input [input]
  (when (and active-input (= input active-input))
    (release-active-input))
  active-input)

(fn dispatch-input [method payload]
  (local current active-input)
  (if (and current method (. current method))
      ((. current method) current payload)
      false))

{:connect-input connect-input
 :disconnect-input disconnect-input
 :dispatch-input dispatch-input
 :active-input (fn [] active-input)
 :release-active-input release-active-input}

;
