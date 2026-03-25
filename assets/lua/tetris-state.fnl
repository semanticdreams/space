(local State (require :state))
(local Routes (require :state-routes))
(local Defaults (require :state-defaults))
(local DefaultConfig (require :state-default-config))
(local Runtime (require :state-runtime))
(local TetrisStateRouter (require :tetris-state-router))

(local SDLK_ESCAPE 27)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local SDLK_UP 1073741906)
(local SDLK_DOWN 1073741905)
(local SDLK_SPACE 32)

(fn handle-key-down [payload]
  (local key (and payload payload.key))
  (if (not key)
      false
      (if (= key SDLK_ESCAPE)
          (do
            (TetrisStateRouter.dispatch :on-pause payload)
            true)
          (if (Runtime.handle-focus-tab payload)
              true
              (if (or (= key SDLK_LEFT)
                      (= key SDLK_RIGHT)
                      (= key SDLK_UP)
                      (= key SDLK_DOWN)
                      (= key SDLK_SPACE))
                  (TetrisStateRouter.dispatch :on-key-down payload)
                  false)))))

(fn TetrisState []
  (local TetrisCommands
    {:key-down (fn [_ctx payload]
                 (handle-key-down payload))})
  (State
    {:name :tetris
     :routes (DefaultConfig.routes
               {:key-down (Routes.FirstHandlerWins [TetrisCommands Defaults.DefaultKeyDown])})
     :enter DefaultConfig.enter
     :leave DefaultConfig.leave}))

TetrisState
