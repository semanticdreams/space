(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchHandlers (require :state-handlers/touch-pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local Runtime (require :state-runtime))
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

(fn handle-submit [payload]
  (local input (active-input))
  (if (not input)
      false
      (if (and payload
               (= payload.key SDLK_RETURN)
               (Runtime.ctrl-held? payload))
          (do
            (input:submit payload)
            true)
          false)))

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
  (if (handle-submit payload)
      true
      (if (InputState.dispatch-input :on-key-down payload)
          true
          (handle-insert-key payload)))
  true)

(fn sync-insert-mode []
  (local input (active-input))
  (when input
    (input:enter-insert-mode)))

(fn InsertState []
  (local InsertLifecycle
    {:enter (fn [_ctx]
              (sync-insert-mode))
     :leave (fn [_ctx]
              (local input (active-input))
              (when input
                (input:enter-normal-mode)))})
  (local InsertCommands
    {:key-down (fn [_ctx payload]
                 (on-key-down payload))})
  (State
    {:name :insert
     :routes {:touch-down (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseDown])
              :touch-motion (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseMotion])
              :touch-up (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseUp])
              :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseCanceled])
              :text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])
              :text-editing (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch])
              :key-down (Routes.FirstHandlerWins [InsertCommands])
              :key-up (Routes.FirstHandlerWins [FocusHandlers.InputKeyUpDispatch
                                               FocusHandlers.ActiveInputKeyBlock])
              :mouse-button-down (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                                PointerHandlers.ResizableMouseButtonDown
                                                PointerHandlers.ClickableMouseButtonDown
                                                PointerHandlers.MovableMouseButtonDown
                                                PointerHandlers.SelectionMouseButtonDown
                                                PointerHandlers.CameraMouseButtonDown])
              :mouse-button-up (Routes.Chain [PointerHandlers.InputMouseButtonUpDispatch
                                              PointerHandlers.ResizableMouseButtonUp
                                              PointerHandlers.ClickableMouseButtonUp
                                              PointerHandlers.MovableMouseButtonUp
                                              PointerHandlers.SelectionMouseButtonUp
                                              PointerHandlers.CameraMouseButtonUp
                                              HoverHandlers.HoverAfterMouseButtonUp])
              :mouse-motion (Routes.Chain [PointerHandlers.InputMouseMotionDispatch
                                           PointerHandlers.MovableMouseMotion
                                           PointerHandlers.ResizableMouseMotion
                                           PointerHandlers.CameraDragMouseMotion
                                           PointerHandlers.SelectionMouseMotion
                                           PointerHandlers.CameraMouseMotion
                                           HoverHandlers.HoverMouseMotion])
              :mouse-wheel (Routes.FirstHandlerWins [PointerHandlers.InputMouseWheelDispatch
                                                    PointerHandlers.HoveredMouseWheel
                                                    PointerHandlers.CameraMouseWheel])
              :gamepad-button-down (Routes.FirstHandlerWins [GamepadHandlers.GamepadButtonDown])
              :gamepad-axis-motion (Routes.FirstHandlerWins [GamepadHandlers.GamepadAxisMotion])
              :gamepad-removed (Routes.FirstHandlerWins [GamepadHandlers.GamepadRemoved])
              :updated (Routes.Chain [CameraHandlers.CameraUpdated
                                      HoverHandlers.HoverUpdated])}
     :enter [TouchHandlers.TouchLifecycle
             HoverHandlers.HoverLifecycle
             InsertLifecycle]
     :leave [TouchHandlers.TouchLifecycle
             HoverHandlers.HoverLifecycle
             InsertLifecycle]}))

InsertState
