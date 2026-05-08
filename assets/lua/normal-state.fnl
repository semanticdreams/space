(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchPointer (require :state-handlers/touch-pointer))
(local TouchTransform (require :state-handlers/touch-transform))
(local PenPointer (require :state-handlers/pen-pointer))
(local PenToolOverride (require :state-handlers/pen-tool-override))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local Runtime (require :state-runtime))
(local {: entry : section} (require :command-hints))

(local KEY_SPACE (string.byte " "))
(local KEY_BACKQUOTE (string.byte "`"))
(local SDLK_RETURN 13)
(local SDLK_DELETE 127)
(local SDLK_F4 1073741885)

(local {: normalize-handlers : resolve-handler} (require :state-routes))

(fn NormalState []
  (local PenHandlers
    (PenPointer.PenPointerHandlers
      {:touch-policy {:suppress-touch-when :down
                      :suppression-timeout-ms 150
                      :allow-touch-during-hover? true}}))

  (fn touch-allowed? [payload]
    (if (= app.canvas-mode-drawing-enabled? true)
        (PenHandlers:touch-allowed? payload)
        true))

  (local TouchHandlers
    (TouchPointer.TouchPointerHandlers
      {:allow-touch? touch-allowed?
       :on-multitouch-start TouchTransform.handle-transform-start
       :on-multitouch-motion TouchTransform.handle-transform-motion
       :on-multitouch-end TouchTransform.handle-transform-end}))

  (local DrawingPenOverride
    ((. PenToolOverride :PenToolOverrideHandlers)
      {:active? (fn []
                  (and app.drawing-controller
                       (= app.canvas-interactive? true)
                       (= app.canvas-mode-drawing-enabled? true)
                       app.drawing-controller.active-layer
                       (app.drawing-controller:active-layer)))
       :get-tool (fn []
                   (assert (and app.drawing-controller
                                app.drawing-controller.persistent-tool)
                           "NormalState drawing pen override requires drawing-controller:persistent-tool")
                   (app.drawing-controller:persistent-tool))
       :set-tool (fn [tool]
                   (assert (and app.drawing-controller app.drawing-controller.set-active-tool)
                           "NormalState drawing pen override requires drawing-controller:set-active-tool")
                   (app.drawing-controller:set-active-tool tool))}))

  (fn handle-f4-toggle []
    (if (and app.canvas app.toggle-active-interaction-surface)
        (app.toggle-active-interaction-surface)
        false))

  (fn remove-selected-nodes []
    (if app.canvas-mode-delete-selection
        (app.canvas-mode-delete-selection)
        false))

  (fn maybe-open-focused-graph-node []
    (if app.canvas-mode-activate-focused
        (app.canvas-mode-activate-focused)
        false))

  (fn open-fennel-interpreter []
    (local launchable (require :launchables/fennel-interpreter))
    (assert (and launchable launchable.open-panel)
            "NormalState fennel interpreter requires launchables/fennel-interpreter.open-panel")
    (launchable.open-panel {:scene app.scene})
    true)

  (fn dispatch-mode-input [event-name ctx payload]
    (local handlers
      (normalize-handlers
        (and app.canvas-mode-input-handlers
             (. app.canvas-mode-input-handlers event-name))))
    (var handled false)
    (each [_ handler (ipairs (or handlers []))]
      (local event-handler (resolve-handler handler event-name))
      (when (and event-handler
                 (event-handler ctx payload))
        (set handled true)))
    handled)

  (local CanvasModeInput
    {:key-down (fn [ctx payload]
                 (dispatch-mode-input :key-down ctx payload))
     :key-up (fn [ctx payload]
               (dispatch-mode-input :key-up ctx payload))
     :mouse-button-down (fn [ctx payload]
                          (dispatch-mode-input :mouse-button-down ctx payload))
     :mouse-button-up (fn [ctx payload]
                        (dispatch-mode-input :mouse-button-up ctx payload))
     :mouse-motion (fn [ctx payload]
                     (dispatch-mode-input :mouse-motion ctx payload))})

  (fn normal-command-sections [payload]
    (local entries [(entry "space" "leader" {:priority 10})])
    (local focus-manager (and payload payload.focus-manager))
    (local active-input (and payload payload.active-input))
    (when (or (and focus-manager focus-manager.activate-focused-from-payload)
              app.canvas-mode-activate-focused)
      (table.insert entries (entry "enter" "activate" {:priority 20})))
    (when focus-manager
      (table.insert entries (entry "tab" "focus-next" {:priority 30 :show-collapsed? false}))
      (when (not active-input)
        (table.insert entries (entry "h/j/k/l" "focus-direction" {:priority 31 :show-collapsed? false}))))
    (local f4-label
      (if (and app.canvas app.toggle-active-interaction-surface)
          "toggle-canvas"
          "toggle-graph-view"))
    (table.insert entries (entry "f4" f4-label {:priority 40}))
    (table.insert entries (entry "`" "fennel-repl" {:priority 50}))
    (local sections [(section :mode "MODE" entries)])
    (local provider app.canvas-mode-command-hints-provider)
    (when provider
      (each [_ extra-section (ipairs (or (provider payload) []))]
        (table.insert sections extra-section)))
    sections)

  (local NormalCommands
    {:key-down
     (fn [ctx payload]
       (local key (and payload payload.key))
       (local set-state (. ctx :set-state))
       (if (= key KEY_SPACE)
           (do
             ((. ctx :mark-command-executed!))
             (set-state :leader)
             true)
           (= key SDLK_RETURN)
           (do
             (local focus-manager ((. ctx :focus-manager)))
             (local handled
               (if (and focus-manager focus-manager.activate-focused-from-payload)
                   (if (focus-manager:activate-focused-from-payload payload)
                       true
                       (maybe-open-focused-graph-node))
                   (maybe-open-focused-graph-node)))
           (when handled
               ((. ctx :mark-command-executed!)))
             handled)
           (= key SDLK_DELETE)
           (do
             (local handled (remove-selected-nodes))
             (when handled
               ((. ctx :mark-command-executed!)))
             handled)
           (= key SDLK_F4)
           (do
             (local handled (handle-f4-toggle))
             (when handled
               ((. ctx :mark-command-executed!)))
             handled)
           (= key KEY_BACKQUOTE)
           (do
             (local handled (open-fennel-interpreter))
             (when handled
               ((. ctx :mark-command-executed!)))
             handled)
           false))})

  (local state
    (State
      {:name :normal
       :route-wrappers [Routes.CommandHints]
       :command_hints_provider (fn [_self payload]
                                 (normal-command-sections payload))
       :routes {:touch-down (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseDown])
                :touch-motion (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseMotion])
                :touch-up (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseUp])
                :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseCanceled])
                :pen-proximity-in (Routes.Chain [DrawingPenOverride.PenToolOverride
                                                 PenHandlers.PenProximityIn])
                :pen-proximity-out (Routes.Chain [DrawingPenOverride.PenToolOverride
                                                  PenHandlers.PenProximityOut])
                :pen-motion (Routes.Chain [DrawingPenOverride.PenToolOverride
                                           PenHandlers.PenMotion])
                :pen-down (Routes.Chain [DrawingPenOverride.PenToolOverride
                                         PenHandlers.PenDown])
                :pen-up (Routes.Chain [DrawingPenOverride.PenToolOverride
                                       PenHandlers.PenUp])
                :pen-button-down (Routes.Chain [DrawingPenOverride.PenToolOverride
                                                PenHandlers.PenButtonDown])
                :pen-button-up (Routes.Chain [DrawingPenOverride.PenToolOverride
                                              PenHandlers.PenButtonUp])
                :pen-axis (Routes.Chain [DrawingPenOverride.PenToolOverride
                                         PenHandlers.PenAxis])
                :text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])
                :text-editing (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch])
                :key-down (Routes.FirstHandlerWins [FocusHandlers.InputKeyDownDispatch
                                                   CanvasModeInput
                                                   NormalCommands
                                                   FocusHandlers.FocusTabKeyDown
                                                   FocusHandlers.FocusDirectionKeyDown
                                                   FocusHandlers.ActiveInputKeyBlock])
                :key-up (Routes.FirstHandlerWins [FocusHandlers.InputKeyUpDispatch
                                                 CanvasModeInput
                                                 FocusHandlers.ActiveInputKeyBlock])
                :mouse-button-down (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                                  PointerHandlers.ResizableMouseButtonDown
                                                  PointerHandlers.ClickableMouseButtonDown
                                                  CanvasModeInput
                                                  PointerHandlers.MovableMouseButtonDown
                                                  PointerHandlers.SelectionMouseButtonDown
                                                  PointerHandlers.CameraMouseButtonDown])
                :mouse-button-up (Routes.Chain [PointerHandlers.InputMouseButtonUpDispatch
                                                PointerHandlers.ResizableMouseButtonUp
                                                PointerHandlers.ClickableMouseButtonUp
                                                CanvasModeInput
                                                PointerHandlers.MovableMouseButtonUp
                                                PointerHandlers.SelectionMouseButtonUp
                                                PointerHandlers.CameraMouseButtonUp
                                                HoverHandlers.HoverAfterMouseButtonUp])
                :mouse-motion (Routes.Chain [PointerHandlers.InputMouseMotionDispatch
                                             PointerHandlers.MovableMouseMotion
                                             PointerHandlers.ResizableMouseMotion
                                             CanvasModeInput
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
               DrawingPenOverride.PenToolOverride
               TouchHandlers.TouchLifecycle
               HoverHandlers.HoverLifecycle]
       :leave [DrawingPenOverride.PenToolOverride
               PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               HoverHandlers.HoverLifecycle]}))
  state)

NormalState
