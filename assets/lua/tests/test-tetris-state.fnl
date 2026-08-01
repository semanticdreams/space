(local tests [])
(local States (require :states))
(local TetrisState (require :tetris-state))
(local TetrisStateRouter (require :tetris-state-router))
(local StateSystemBindings (require :state-system-bindings))

(local SDLK_ESCAPE 27)
(local SDLK_LEFT 1073741904)

(fn make-command-hints-stub []
  {:handle-toggle-key (fn [_self _payload] true)
   :close-on-handled-event (fn [_self _route-key _payload] false)})

(fn command-hints-hud-provider [_self]
  {:command-hints (make-command-hints-stub)})

(fn with-state-stub [body]
  (local original-states app.states)
  (local original-engine app.engine)
  (local states (States {:hud_provider command-hints-hud-provider}))
  (local state-record {:transitions []
                       :states states})
  (set app.engine (or app.engine {}))
  (states:add-state :normal {})
  (states:add-state :tetris {})
  (states:set-state :normal)
  (local changed-handler
    (states.changed:connect
      (fn [event]
        (table.insert state-record.transitions event.current))))
  (set app.states states)
  (StateSystemBindings.bind-states-host states)
  (local (ok result) (pcall (fn [] (body state-record))))
  (do
    (states.changed:disconnect changed-handler true)
    (StateSystemBindings.bind-states-host original-states)
    (set app.states original-states)
    (set app.engine original-engine)
    (when (not ok)
      (error result))
    result))

(fn tetris-router-connects-and-releases []
  (with-state-stub
    (fn [record]
      (var connected false)
      (var disconnected false)
      (local board {:on-state-connected (fn [_self _event] (set connected true))
                    :on-state-disconnected (fn [_self _event] (set disconnected true))})
      (TetrisStateRouter.connect-board board)
      (assert connected "Expected board to connect")
      (assert (= (. record.transitions 1) :tetris))
      (TetrisStateRouter.disconnect-board board)
      (TetrisStateRouter.release-active-board)
      (assert disconnected "Expected board to disconnect")
      (assert (= (. record.transitions 2) :normal)))))

(fn tetris-state-dispatches-pause []
  (with-state-stub
    (fn [record]
      (var paused false)
      (local board {:on-pause (fn [_self _payload] (set paused true))})
      (local state (TetrisState))
      (record.states:add-state :tetris state)
      (TetrisStateRouter.connect-board board)
      (state.on-key-down {:key SDLK_ESCAPE})
      (TetrisStateRouter.release-active-board)
      (assert paused "Escape should pause the board"))))

(fn tetris-state-dispatches-keydown []
  (with-state-stub
    (fn [record]
      (var last-key nil)
      (local board {:on-key-down (fn [_self payload] (set last-key payload.key))})
      (local state (TetrisState))
      (record.states:add-state :tetris state)
      (TetrisStateRouter.connect-board board)
      (state.on-key-down {:key SDLK_LEFT})
      (TetrisStateRouter.release-active-board)
      (assert (= last-key SDLK_LEFT) "Arrow key should dispatch to board"))))

(table.insert tests {:name "Tetris router connects and releases" :fn tetris-router-connects-and-releases})
(table.insert tests {:name "Tetris state dispatches pause" :fn tetris-state-dispatches-pause})
(table.insert tests {:name "Tetris state dispatches keydown" :fn tetris-state-dispatches-keydown})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "tetris-state"
                       :tests tests})))

{:name "tetris-state"
 :tests tests
 :main main}
