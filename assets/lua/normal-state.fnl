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
(local DrawingHandlers (require :drawing/input))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local GraphView (require :graph/view))

(local KEY_SPACE (string.byte " "))
(local KEY_BACKQUOTE (string.byte "`"))
(local SDLK_RETURN 13)
(local SDLK_DELETE 127)
(local SDLK_F4 1073741885)

(fn NormalState []
  (local PenHandlers
    (PenPointer.PenPointerHandlers
      {:touch-policy {:suppress-touch-when :down
                      :suppression-timeout-ms 150
                      :allow-touch-during-hover? true}}))

  (fn touch-allowed? [payload]
    (if (= app.active-canvas-feature "drawing")
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
                       (= app.active-canvas-feature "drawing")))
       :get-tool (fn []
                   (assert (and app.drawing-controller
                                app.drawing-controller.persistent-tool)
                           "NormalState drawing pen override requires drawing-controller:persistent-tool")
                   (app.drawing-controller:persistent-tool))
       :set-tool (fn [tool]
                   (assert (and app.drawing-controller app.drawing-controller.set-active-tool)
                           "NormalState drawing pen override requires drawing-controller:set-active-tool")
                   (app.drawing-controller:set-active-tool tool))}))

  (fn graph-interaction-enabled? []
    (not (= app.active-canvas-feature "drawing")))

  (fn create-graph-view []
    (if (and app.graph-view-factory (= (type app.graph-view-factory) :function))
        (app.graph-view-factory)
        (do
          (assert app.graph "NormalState requires app.graph to create GraphView")
          (local ctx (or (and app.canvas app.canvas.build-context)
                         (and app.scene app.scene.build-context)))
          (assert ctx "NormalState requires canvas or scene build-context to create GraphView")
          (GraphView {:graph app.graph
                      :ctx ctx
                      :movables app.movables
                      :selector app.object-selector
                      :view-target (or app.canvas app.hud)
                      :camera (or (and app.canvas app.canvas.camera) app.camera)
                      :pointer-target (or app.canvas app.scene)}))))

  (fn toggle-graph-view []
    (if (and app.canvas app.toggle-active-interaction-surface)
        (app.toggle-active-interaction-surface)
        (if app.graph-view
            (do
              (app.graph-view:drop)
              (set app.graph-view nil)
              true)
            (do
              (local view (create-graph-view))
              (assert view "NormalState GraphView factory returned nil")
              (set app.graph-view view)
              true))))

  (fn remove-selected-nodes []
    (if (not (graph-interaction-enabled?))
        false
        (do
          (local graph-view app.graph-view)
          (when (and graph-view graph-view.remove-selected-nodes)
            (> (graph-view:remove-selected-nodes) 0)))))

  (fn maybe-open-focused-graph-node []
    (if (not (graph-interaction-enabled?))
        false
        (do
          (local graph-view app.graph-view)
          (and graph-view
               graph-view.open-focused-node
               (graph-view:open-focused-node)))))

  (fn open-fennel-interpreter []
    (local launchable (require :launchables/fennel-interpreter))
    (assert (and launchable launchable.open-panel)
            "NormalState fennel interpreter requires launchables/fennel-interpreter.open-panel")
    (launchable.open-panel {:scene app.scene})
    true)

  (local NormalCommands
    {:key-down
     (fn [ctx payload]
       (local key (and payload payload.key))
       (local set-state (. ctx :set-state))
       (if (= key KEY_SPACE)
           (do
             (set-state :leader)
             true)
           (= key SDLK_RETURN)
           (do
             (local focus-manager app.focus)
             (if (and focus-manager focus-manager.activate-focused-from-payload)
                 (if (focus-manager:activate-focused-from-payload payload)
                     true
                     (maybe-open-focused-graph-node))
                 (maybe-open-focused-graph-node)))
           (= key SDLK_DELETE)
           (remove-selected-nodes)
           (= key SDLK_F4)
           (toggle-graph-view)
           (= key KEY_BACKQUOTE)
           (open-fennel-interpreter)
           false))})

  (State
    {:name :normal
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
                                                 DrawingHandlers.DrawingKeyDown
                                                 NormalCommands
                                                 FocusHandlers.FocusTabKeyDown
                                                 FocusHandlers.FocusDirectionKeyDown
                                                 FocusHandlers.ActiveInputKeyBlock])
              :key-up (Routes.FirstHandlerWins [FocusHandlers.InputKeyUpDispatch
                                               FocusHandlers.ActiveInputKeyBlock])
              :mouse-button-down (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                                PointerHandlers.ResizableMouseButtonDown
                                                PointerHandlers.ClickableMouseButtonDown
                                                DrawingHandlers.DrawingMouseButtonDown
                                                PointerHandlers.MovableMouseButtonDown
                                                PointerHandlers.SelectionMouseButtonDown
                                                PointerHandlers.CameraMouseButtonDown])
              :mouse-button-up (Routes.Chain [PointerHandlers.InputMouseButtonUpDispatch
                                              PointerHandlers.ResizableMouseButtonUp
                                              PointerHandlers.ClickableMouseButtonUp
                                              DrawingHandlers.DrawingMouseButtonUp
                                              PointerHandlers.MovableMouseButtonUp
                                              PointerHandlers.SelectionMouseButtonUp
                                              PointerHandlers.CameraMouseButtonUp
                                              HoverHandlers.HoverAfterMouseButtonUp])
              :mouse-motion (Routes.Chain [PointerHandlers.InputMouseMotionDispatch
                                           PointerHandlers.MovableMouseMotion
                                           PointerHandlers.ResizableMouseMotion
                                           DrawingHandlers.DrawingMouseMotion
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

NormalState
