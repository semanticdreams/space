(var active-board nil)

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn current-state-name []
  (and app.engine
       app.states
       app.states.active-name
       (app.states.active-name)))

(fn release-active-board []
  (when active-board
    (local handler active-board.on-state-disconnected)
    (when handler
      (active-board:on-state-disconnected {:state (current-state-name)}))
    (set active-board nil)
    (when (= (current-state-name) :tetris)
      (set-state :normal))))

(fn connect-board [board]
  (when (not (= board active-board))
    (release-active-board)
    (when board
      (set active-board board)
      (local handler board.on-state-connected)
      (when handler
        (board:on-state-connected {:state (current-state-name)}))))
  (when (= (current-state-name) :normal)
    (set-state :tetris))
  active-board)

(fn disconnect-board [board]
  (when (and active-board (= board active-board))
    (release-active-board))
  active-board)

(fn dispatch [method payload]
  (local current active-board)
  (if (and current method (. current method))
      ((. current method) current payload)
      false))

{:connect-board connect-board
 :disconnect-board disconnect-board
 :dispatch dispatch
 :active-board (fn [] active-board)
 :release-active-board release-active-board}
