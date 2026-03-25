(local Routes (require :state-routes))
(local Defaults (require :state-defaults))

(fn routes [overrides]
  (local route-overrides (or overrides {}))
  {:text-input (or route-overrides.text-input
                   (Routes.FirstHandlerWins [Defaults.DefaultTextInput]))
   :text-editing (or route-overrides.text-editing
                     (Routes.FirstHandlerWins [Defaults.DefaultTextEditing]))
   :key-down (or route-overrides.key-down
                 (Routes.FirstHandlerWins [Defaults.DefaultKeyDown]))
   :key-up (or route-overrides.key-up
               (Routes.FirstHandlerWins [Defaults.DefaultKeyUp]))
   :mouse-button-down (or route-overrides.mouse-button-down
                          (Routes.FirstHandlerWins [Defaults.DefaultMouseButtonDown]))
   :mouse-button-up (or route-overrides.mouse-button-up
                        (Routes.FirstHandlerWins [Defaults.DefaultMouseButtonUp]))
   :mouse-motion (or route-overrides.mouse-motion
                     (Routes.FirstHandlerWins [Defaults.DefaultMouseMotion]))
   :mouse-wheel (or route-overrides.mouse-wheel
                    (Routes.FirstHandlerWins [Defaults.DefaultMouseWheel]))
   :gamepad-button-down (or route-overrides.gamepad-button-down
                            (Routes.FirstHandlerWins [Defaults.DefaultGamepad]))
   :gamepad-axis-motion (or route-overrides.gamepad-axis-motion
                            (Routes.FirstHandlerWins [Defaults.DefaultGamepad]))
   :gamepad-removed (or route-overrides.gamepad-removed
                        (Routes.FirstHandlerWins [Defaults.DefaultGamepad]))
   :updated (or route-overrides.updated
                (Routes.FirstHandlerWins [Defaults.DefaultUpdated]))})

{:routes routes
 :enter [Defaults.HoverLifecycle]
 :leave [Defaults.HoverLifecycle]}
