(local InputState (require :input-state-router))
(local TetrisStateRouter (require :tetris-state-router))
(local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
(local TerrainPaintManager (require :graph/view/terrain-paint-manager))

(fn bind-states-host [states]
  (local provider
    (and states
         (fn []
           states)))
  (InputState.set-states-provider provider)
  (TetrisStateRouter.set-states-provider provider)
  (TerrainRectPickManager.set-states-provider provider)
  (TerrainPaintManager.set-states-provider provider)
  states)

{:bind-states-host bind-states-host}
