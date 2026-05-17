(var active-board nil)
(local StateSystemRuntime (require :state-system-runtime))

(fn states-host [action]
  (StateSystemRuntime.states-host "TetrisStateRouter" action))

(fn set-states-provider [provider]
  (StateSystemRuntime.set-states-provider provider))

(fn set-state [name]
  (local states (states-host "state transitions"))
  (assert (and states states.set-state)
          "TetrisStateRouter requires a states host for state transitions")
  (states:set-state name))

(fn current-state-name []
  (local states (states-host "current-state-name"))
  (assert states.active-name
          "TetrisStateRouter states host must expose :active-name")
  (states:active-name))

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
 :current-state-name current-state-name
 :set-state set-state
 :set-states-provider set-states-provider
 :release-active-board release-active-board}
