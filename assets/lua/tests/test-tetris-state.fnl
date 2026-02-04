(local tests [])
(local TetrisState (require :tetris-state))
(local TetrisStateRouter (require :tetris-state-router))

(local SDLK_ESCAPE 27)
(local SDLK_LEFT 1073741904)

(fn with-state-stub [body]
  (local original-states app.states)
  (local original-engine app.engine)
  (local state-record {:name :normal :transitions []})
  (set app.engine (or app.engine {}))
  (set app.states {:set-state (fn [name]
                                 (set state-record.name name)
                                 (table.insert state-record.transitions name))
                   :active-name (fn [] state-record.name)})
  (let [(ok result) (pcall (fn [] (body state-record)))]
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
    (fn [_record]
      (var paused false)
      (local board {:on-pause (fn [_self _payload] (set paused true))})
      (TetrisStateRouter.connect-board board)
      (local state (TetrisState))
      (state.on-key-down {:key SDLK_ESCAPE})
      (TetrisStateRouter.release-active-board)
      (assert paused "Escape should pause the board"))))

(fn tetris-state-dispatches-keydown []
  (with-state-stub
    (fn [_record]
      (var last-key nil)
      (local board {:on-key-down (fn [_self payload] (set last-key payload.key))})
      (TetrisStateRouter.connect-board board)
      (local state (TetrisState))
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
