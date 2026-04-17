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
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (local TetrisCommands
    {:key-down (fn [_ctx payload]
                 (handle-key-down payload))})
  (State
    {:name :tetris
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
              :key-down (Routes.FirstHandlerWins [TetrisCommands
                                                 FocusHandlers.InputKeyDownDispatch
                                                 FocusHandlers.ActiveInputKeyBlock])
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

TetrisState
