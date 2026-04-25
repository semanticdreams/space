(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchHandlers (require :state-handlers/touch-pointer))
(local PenPointer (require :state-handlers/pen-pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local Runtime (require :state-runtime))
(local InputState (require :input-state-router))
(local {: entry : section} (require :command-hints))

(local SDLK_ESCAPE 27)
(local SDLK_RETURN 13)
(local SDLK_BACKSPACE 8)
(local SDLK_DELETE 127)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)

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

(fn exit-insert-mode [ctx input]
  (when input
    (input:enter-normal-mode))
  ((. ctx :set-state) :text))

(fn handle-insert-key [ctx payload]
  (local input (active-input))
  (if (not input)
      false
      (do
        (local key (and payload payload.key))
        (if (not key)
            false
            (if (= key SDLK_ESCAPE)
                (do
                  (exit-insert-mode ctx input)
                  (when (> input.cursor-index 0)
                    (input:move-caret -1))
                  true)
                (if (= key SDLK_RETURN)
                    (if input.multiline?
                        (do
                          (input:insert-text "\n")
                          true)
                        (do
                          (exit-insert-mode ctx input)
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

(fn on-key-down [ctx payload]
  (local handled
    (if (handle-submit payload)
        true
        (if (InputState.dispatch-input :on-key-down payload)
            true
            (handle-insert-key ctx payload))))
  (when handled
    ((. ctx :mark-command-executed!)))
  handled)

(fn sync-insert-mode []
  (local input (active-input))
  (when input
    (input:enter-insert-mode)))

(fn InsertState []
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (fn insert-command-sections [payload]
    (local input (and payload payload.active-input))
    (local enter-label (if (and input input.multiline?) "newline" "text-mode"))
    [(section :mode
              "MODE"
              [(entry "esc" "text-mode" {:priority 10})
               (entry "enter" enter-label {:priority 20})
               (entry "ctrl+enter" "submit" {:priority 21 :show-collapsed? false})
               (entry "backspace" "delete-before" {:priority 30})
               (entry "del" "delete-after" {:priority 31})
               (entry "left/right" "move-caret" {:priority 40})])])
  (local InsertLifecycle
    {:enter (fn [_ctx]
              (sync-insert-mode))
     :leave (fn [_ctx]
              (local input (active-input))
              (when input
                (input:enter-normal-mode)))})
  (local InsertCommands
    {:key-down (fn [ctx payload]
                 (on-key-down ctx payload))})
  (local state
    (State
      {:name :insert
       :route-wrappers [Routes.CommandHints]
       :command_hints_provider (fn [_self payload]
                                 (insert-command-sections payload))
       :routes {:touch-down (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseDown])
                :touch-motion (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseMotion])
                :touch-up (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseUp])
                :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseCanceled])
                :pen-proximity-in (Routes.Chain [PenHandlers.PenProximityIn])
                :pen-proximity-out (Routes.Chain [PenHandlers.PenProximityOut])
                :pen-motion (Routes.Chain [PenHandlers.PenMotion])
                :pen-down (Routes.Chain [PenHandlers.PenDown])
                :pen-up (Routes.Chain [PenHandlers.PenUp])
                :pen-button-down (Routes.Chain [PenHandlers.PenButtonDown])
                :pen-button-up (Routes.Chain [PenHandlers.PenButtonUp])
                :pen-axis (Routes.Chain [PenHandlers.PenAxis])
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
       :enter [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               HoverHandlers.HoverLifecycle
               InsertLifecycle]
       :leave [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               HoverHandlers.HoverLifecycle
               InsertLifecycle]}))
  state)

InsertState
