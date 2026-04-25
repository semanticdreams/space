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
(local {: entry : section} (require :command-hints))

(local KEY
  {:escape 27
   :q (string.byte "q")})

(fn QuitState []
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (local QuitCommands
    {:key-down (fn [ctx payload]
                 (local key (and payload payload.key))
                 (local set-state (. ctx :set-state))
                 (if (= key KEY.escape)
                     (do ((. ctx :mark-command-executed!)) (set-state :normal) true)
                     (= key KEY.q) (do
                                     ((. ctx :mark-command-executed!))
                                     (assert app.engine.quit "app.engine.quit binding missing")
                                     (app.engine.quit)
                                     true)
                     false))})
  (local state
    (State
      {:name :quit
       :route-wrappers [Routes.CommandHints]
       :command_hints_provider (fn [_ctx]
                                 [(section :mode
                                           "MODE"
                                           [(entry "q" "quit-app" {:priority 10})
                                            (entry "esc" "normal-mode" {:priority 20})])])
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
                :key-down (Routes.FirstHandlerWins [QuitCommands])
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
               HoverHandlers.HoverLifecycle]
       :leave [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               HoverHandlers.HoverLifecycle]}))
  state)

QuitState
