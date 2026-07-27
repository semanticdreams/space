(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchHandlers (require :state-handlers/touch-camera))
(local PenPointer (require :state-handlers/pen-pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local glm (require :glm))
(local Runtime (require :state-runtime))
(local {: entry : section} (require :command-hints))

(local KEY
  {:escape 27
   :f (string.byte "f")
   :zero (string.byte "0")})

(fn reset-camera! []
  (local cam (and app.presentation-camera
                  (app.presentation-camera {:required? true})))
  (assert cam.set-position "camera-state expects camera:set-position")
  (assert cam.set-rotation "camera-state expects camera:set-rotation")
  (cam:set-position (glm.vec3 0 0 0))
  (cam:set-rotation (glm.quat 1 0 0 0)))

(fn CameraState []
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (fn camera-command-sections [payload]
    (local entries [(entry "esc" "normal-mode" {:priority 10})
                    (entry "f" "drive-mode" {:priority 20})
                    (entry "0" "reset-camera" {:priority 30})])
    (local focus-manager (and payload payload.focus-manager))
    (local active-input (and payload payload.active-input))
    (when focus-manager
      (table.insert entries (entry "tab" "focus-next" {:priority 40 :show-collapsed? false}))
      (when (not active-input)
        (table.insert entries (entry "h/j/k/l" "focus-direction" {:priority 41 :show-collapsed? false}))))
    [(section :mode "MODE" entries)])
  (local CameraCommands
    {:key-down (fn [ctx payload]
                 (local key (and payload payload.key))
                 (local set-state (. ctx :set-state))
                 (if (= key KEY.escape)
                     (do ((. ctx :mark-command-executed!)) (set-state :normal) true)
                     (= key KEY.f)
                     (do ((. ctx :mark-command-executed!)) (set-state :fpc) true)
                     (= key KEY.zero)
                     (do ((. ctx :mark-command-executed!)) (reset-camera!) true)
                     false))})
  (local state
    (State
      {:name :camera
       :route-wrappers [Routes.CommandHints]
       :command_hints_provider (fn [_self payload]
                                 (camera-command-sections payload))
       :routes {:text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])
                :text-editing (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch])
                :touch-down (Routes.FirstHandlerWins [TouchHandlers.CameraTouchDown])
                :touch-motion (Routes.FirstHandlerWins [TouchHandlers.CameraTouchMotion])
                :touch-up (Routes.FirstHandlerWins [TouchHandlers.CameraTouchUp])
                :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.CameraTouchCanceled])
                :pen-proximity-in (Routes.Chain [PenHandlers.PenProximityIn])
                :pen-proximity-out (Routes.Chain [PenHandlers.PenProximityOut])
                :pen-motion (Routes.Chain [PenHandlers.PenMotion])
                :pen-down (Routes.Chain [PenHandlers.PenDown])
                :pen-up (Routes.Chain [PenHandlers.PenUp])
                :pen-button-down (Routes.Chain [PenHandlers.PenButtonDown])
                :pen-button-up (Routes.Chain [PenHandlers.PenButtonUp])
                :pen-axis (Routes.Chain [PenHandlers.PenAxis])
                :key-down (Routes.FirstHandlerWins [CameraCommands
                                                   FocusHandlers.InputKeyDownDispatch
                                                   FocusHandlers.FocusTabKeyDown
                                                   FocusHandlers.FocusDirectionKeyDown
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
  state)

CameraState
