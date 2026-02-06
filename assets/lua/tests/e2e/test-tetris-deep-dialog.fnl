(local Harness (require :tests.e2e.harness))
(local Camera (require :camera))
(local glm (require :glm))
(local TetrisView (require :tetris-view))

(fn stamp-cell! [grid x y id]
  (local row (and grid (. grid y)))
  (when row
    (tset row x id)))

(fn seed-board! [grid]
  ; Bottom row (y=1) with a gap.
  (stamp-cell! grid 1 1 :I)
  (stamp-cell! grid 2 1 :I)
  (stamp-cell! grid 3 1 :I)
  (stamp-cell! grid 5 1 :Z)
  (stamp-cell! grid 6 1 :Z)
  (stamp-cell! grid 7 1 :Z)
  (stamp-cell! grid 8 1 :Z)
  ; Second row.
  (stamp-cell! grid 1 2 :J)
  (stamp-cell! grid 2 2 :J)
  (stamp-cell! grid 7 2 :L)
  (stamp-cell! grid 8 2 :L)
  ; A small mid-stack.
  (stamp-cell! grid 4 4 :T)
  (stamp-cell! grid 5 4 :T)
  (stamp-cell! grid 4 5 :T)
  grid)

(fn run [ctx]
  (local camera (Camera {:position (glm.vec3 0 0 18)}))
  (camera:look-at (glm.vec3 0 0 0))

  (local dialog-builder
    (TetrisView.TetrisDialog {:title "Tetris"
                              :cell-size 1.0
                              :game {:width 8
                                     :height 10
                                     :sequence [:T]}}))

  (local scene-target
    (Harness.make-scene-target
      {:builder (fn [child-ctx]
                  (local dialog (dialog-builder child-ctx))
                  (local game dialog.game)
                  (assert game "tetris dialog missing game")
                  (seed-board! game.grid)
                  (set game.active nil)
                  (set game.running? false)
                  (set game.paused? true)
                  (set game.game-over? false)
                  (set game.lines-cleared 3)
                  (set game.score 900)
                  (dialog.board:sync)
                  (when dialog.update_status
                    (dialog.update_status))
                  dialog)
       :view-matrix (camera:get-view-matrix)
       :child-position (glm.vec3 0 0 0)
       :child-rotation (* (glm.quat (math.rad -8) (glm.vec3 1 0 0))
                          (glm.quat (math.rad 12) (glm.vec3 0 1 0)))}))

  (Harness.draw-targets ctx.width ctx.height [{:target scene-target}])
  (Harness.capture-snapshot {:name "tetris-deep-dialog"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (Harness.cleanup-target scene-target)
  (camera:drop))

(fn main []
  (Harness.with-app {:width 900 :height 540}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E tetris deep dialog snapshot complete"))

{:run run
 :main main}
