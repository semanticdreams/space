(local tests [])
(local BuildContext (require :build-context))
(local TetrisGame (require :tetris-game))
(local TetrisView (require :tetris-view))

(local icons-stub {:resolve (fn [_self _name] nil)})

(fn tetris-view-builds-blocks []
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme (app.themes.get-active-theme)}))
  (local game (TetrisGame {:width 4 :height 4 :sequence [:O]}))
  (local builder (TetrisView.TetrisBoard {:game game}))
  (local (ok err) (pcall (fn [] (builder ctx))))
  (assert ok (.. "TetrisBoard build failed: " (tostring err))))

(fn tetris-view-builds-dialog []
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme (app.themes.get-active-theme)}))
  (local builder (TetrisView.TetrisDialog {}))
  (var dialog nil)
  (local (ok err)
    (pcall (fn []
             (set dialog (builder ctx)))))
  (assert ok (.. "TetrisDialog build failed: " (tostring err)))
  (assert dialog "TetrisDialog build missing entity")
  (assert dialog.drop "TetrisDialog missing drop")
  (assert dialog.game "TetrisDialog missing game")
  (assert dialog.board "TetrisDialog missing board")
  (dialog:drop))

(fn tetris-dialog-idle-does-not-sync []
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme (app.themes.get-active-theme)}))
  (local builder (TetrisView.TetrisDialog {}))
  (local dialog (builder ctx))
  (var sync-calls 0)
  (local original-sync dialog.board.sync)
  (assert original-sync "TetrisDialog board missing sync method")
  (set dialog.board.sync (fn [_self]
                           (set sync-calls (+ sync-calls 1))))

  (for [_i 1 30]
    (app.engine.events.updated:emit 16))
  (assert (= sync-calls 0) "Idle tetris dialog should not sync board every frame")

  (set sync-calls 0)
  (dialog.game:start)
  (app.engine.events.updated:emit 1000)
  (assert (> sync-calls 0) "Running tetris dialog should sync board on drops")

  (set dialog.board.sync original-sync)
  (dialog:drop))

(fn tetris-dialog-manages-gameplay-performance-lease []
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme (app.themes.get-active-theme)}))
  (local builder (TetrisView.TetrisDialog {}))
  (local dialog (builder ctx))
  (local original-activate app.activate-runtime-performance-gameplay-lease)
  (local original-clear app.clear-runtime-performance-gameplay-lease)
  (local (ok err)
    (pcall
      (fn []
        (var activated nil)
        (var cleared nil)

        (set app.activate-runtime-performance-gameplay-lease
             (fn [id]
               (set activated id)
               {:id id}))
        (set app.clear-runtime-performance-gameplay-lease
             (fn [id]
               (set cleared id)
               true))

        (dialog.game:start)
        (assert activated "starting tetris should activate gameplay lease")
        (assert (= activated (.. "tetris:" (tostring dialog.game))))
        (dialog.game:pause)
        (assert (= cleared activated) "pausing tetris should clear gameplay lease")
        (dialog:drop))))
  (set app.activate-runtime-performance-gameplay-lease original-activate)
  (set app.clear-runtime-performance-gameplay-lease original-clear)
  (if (not ok)
      (error err)))

(fn tetris-dialog-drop-stops-running-updates []
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme (app.themes.get-active-theme)}))
  (local dialog ((TetrisView.TetrisDialog {}) ctx))
  (var sync-calls 0)
  (local original-sync dialog.board.sync)
  (set dialog.board.sync
       (fn [_self]
         (set sync-calls (+ sync-calls 1))))
  (dialog.game:start)
  (app.engine.events.updated:emit 1000)
  (assert (> sync-calls 0) "Running tetris dialog should sync before drop")
  (local calls-before-drop sync-calls)
  (dialog:drop)
  (app.engine.events.updated:emit 1000)
  (assert (= sync-calls calls-before-drop)
          "Dropped tetris dialog should not receive more frame updates")
  (set dialog.board.sync original-sync))

(fn tetris-dialog-double-drop-errors []
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme (app.themes.get-active-theme)}))
  (local dialog ((TetrisView.TetrisDialog {}) ctx))
  (dialog:drop)
  (local (ok err)
    (pcall (fn []
             (dialog:drop))))
  (assert (not ok) "Dropping a tetris dialog twice should error")
  (assert (string.find (tostring err) "TetrisDialog dropped twice" 1 true)))

(table.insert tests {:name "Tetris view builds blocks" :fn tetris-view-builds-blocks})
(table.insert tests {:name "Tetris view builds dialog" :fn tetris-view-builds-dialog})
(table.insert tests {:name "Tetris dialog idle does not sync" :fn tetris-dialog-idle-does-not-sync})
(table.insert tests {:name "Tetris dialog manages gameplay performance lease"
                     :fn tetris-dialog-manages-gameplay-performance-lease})
(table.insert tests {:name "Tetris dialog drop stops running updates"
                     :fn tetris-dialog-drop-stops-running-updates})
(table.insert tests {:name "Tetris dialog double drop errors"
                     :fn tetris-dialog-double-drop-errors})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "tetris-view"
                       :tests tests})))

{:name "tetris-view"
 :tests tests
 :main main}
