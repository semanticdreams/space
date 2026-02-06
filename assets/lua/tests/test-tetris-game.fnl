(local tests [])
(local TetrisGame (require :tetris-game))

(fn tetris-spawns-sequence-piece []
  (local game (TetrisGame {:width 4 :height 4 :sequence [:O]}))
  (game:start)
  (assert game.active "Expected active piece after start")
  (assert (= game.active.id :O)))

(fn tetris-respects-wall-collisions []
  (local game (TetrisGame {:width 6 :height 4 :sequence [:I]}))
  (game:start)
  (local start-x (and game.active game.active.x))
  (game:move -1 0)
  (game:move -1 0)
  (assert (= game.active.x 1) "Piece should stop at left wall")
  (game:move 1 0)
  (assert (= game.active.x 2) "Piece should move right when space exists"))

(fn tetris-clears-lines []
  (local game (TetrisGame {:width 4 :height 4}))
  (var bottom-row (. game.grid 1))
  (tset bottom-row 1 :J)
  (tset bottom-row 2 :J)
  (set game.active {:id :O :rotation 1 :x 3 :y 1})
  (game:soft-drop)
  (assert (= game.lines-cleared 1) "Clearing a full row should increment lines")
  (set bottom-row (. game.grid 1))
  (assert (= (. bottom-row 1) false))
  (assert (= (. bottom-row 2) false))
  (assert (= (. bottom-row 3) :O))
  (assert (= (. bottom-row 4) :O)))

(fn tetris-detects-game-over []
  (local game (TetrisGame {:width 4 :height 4 :sequence [:O]}))
  (set game.grid
       [[ :J :J :J :J]
        [ :J :J :J :J]
        [ :J :J :J :J]
        [ :J :J :J :J]])
  (game:start)
  (assert game.game-over? "Spawn collision should set game-over"))

(fn count-stamped-cells [grid]
  (var cells 0)
  (each [_y row (ipairs (or grid []))]
    (each [_x value (ipairs (or row []))]
      (when value
        (set cells (+ cells 1)))))
  cells)

(fn tetris-game-update-uses-ms-delta []
  (local game (TetrisGame {:width 10 :height 20 :sequence [:I]}))
  (game:start)

  (local before (count-stamped-cells game.grid))
  (assert (= before 0) "New game should start with empty grid")

  (game:update 16)

  (local after (count-stamped-cells game.grid))
  (assert (= after 0)
          "A single ~16ms update should not hard-drop/lock pieces into the grid"))

(table.insert tests {:name "Tetris spawns from sequence" :fn tetris-spawns-sequence-piece})
(table.insert tests {:name "Tetris respects wall collisions" :fn tetris-respects-wall-collisions})
(table.insert tests {:name "Tetris clears full lines" :fn tetris-clears-lines})
(table.insert tests {:name "Tetris detects game over" :fn tetris-detects-game-over})
(table.insert tests {:name "Tetris game uses ms delta" :fn tetris-game-update-uses-ms-delta})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "tetris-game"
                       :tests tests})))

{:name "tetris-game"
 :tests tests
 :main main}
