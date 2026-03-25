(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local LauncherLaunchable (require :launchables/launcher))

(local KEY
  {:escape 27
   :q (string.byte "q")
   :c (string.byte "c")
   :p (string.byte "p")})

(fn open-launcher []
  (LauncherLaunchable.open-panel {:hud app.hud}))

(fn LeaderState []
  (local LeaderCommands
    {:key-down (fn [ctx payload]
                 (local key (and payload payload.key))
                 (local set-state (. ctx :set-state))
                 (if (= key KEY.escape)
                     (do (set-state :normal) true)
                     (= key KEY.c) (do (set-state :camera) true)
                     (= key KEY.q) (do (set-state :quit) true)
                     (= key KEY.p) (do
                                     (open-launcher)
                                     true)
                     true))})
  (State
    {:name :leader
     :routes {:text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])
              :text-editing (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch])
              :key-down (Routes.FirstHandlerWins [LeaderCommands])
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
     :enter [HoverHandlers.HoverLifecycle]
     :leave [HoverHandlers.HoverLifecycle]}))

LeaderState
