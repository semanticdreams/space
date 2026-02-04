(local StateBase (require :state-base))
(local TetrisStateRouter (require :tetris-state-router))

(local SDLK_ESCAPE 27)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local SDLK_UP 1073741906)
(local SDLK_DOWN 1073741905)
(local SDLK_SPACE 32)

(fn TetrisState []
  (local base (StateBase.make-state {:name :tetris}))
  (local base-on-key-down base.on-key-down)
  (fn handle-key-down [payload]
    (local key (and payload payload.key))
    (if (not key)
        false
        (if (= key SDLK_ESCAPE)
            (do
              (TetrisStateRouter.dispatch :on-pause payload)
              true)
            (if (StateBase.handle-focus-tab payload)
                true
                (if (or (= key SDLK_LEFT)
                        (= key SDLK_RIGHT)
                        (= key SDLK_UP)
                        (= key SDLK_DOWN)
                        (= key SDLK_SPACE))
                    (TetrisStateRouter.dispatch :on-key-down payload)
                    (base-on-key-down payload))))))
  (StateBase.make-state {:name :tetris
                         :on-key-down handle-key-down}))

TetrisState
