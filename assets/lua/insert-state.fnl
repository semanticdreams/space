(local StateBase (require :state-base))
(local InputState (require :input-state-router))

(local SDLK_ESCAPE 27)
(local SDLK_RETURN 13)
(local SDLK_BACKSPACE 8)
(local SDLK_DELETE 127)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn active-input []
  (and InputState InputState.active-input (InputState.active-input)))

(fn exit-insert-mode [input]
  (when input
    (input:enter-normal-mode))
  (set-state :text))

(fn handle-insert-key [payload]
  (local input (active-input))
  (if (not input)
      false
      (let [key (and payload payload.key)]
        (if (not key)
            false
            (if (= key SDLK_ESCAPE)
                (do
                  (exit-insert-mode input)
                  (when (> input.cursor-index 0)
                    (input:move-caret -1))
                  true)
                (if (= key SDLK_RETURN)
                    (if input.multiline?
                        (do
                          (input:insert-text "\n")
                          true)
                        (do
                          (exit-insert-mode input)
                          true))
                    (if (= key SDLK_BACKSPACE)
                        (input:delete-before-cursor)
                        (if (= key SDLK_DELETE)
                            (input:delete-at-cursor)
                            (if (= key SDLK_LEFT)
                                (input:move-caret -1)
                                (if (= key SDLK_RIGHT)
                                    (input:move-caret 1)
                                    false))))))))))

(fn on-key-down [payload]
  (handle-insert-key payload)
  true)

(fn sync-insert-mode []
  (local input (active-input))
  (when input
    (input:enter-insert-mode)))

(fn InsertState []
  (StateBase.make-state {:name :insert
                         :on-key-down on-key-down
                         :on-enter sync-insert-mode
                         :on-leave (fn []
                                     (local input (active-input))
                                     (when input
                                       (input:enter-normal-mode)))
                         :on-text-input StateBase.dispatch-text-input}))

InsertState
