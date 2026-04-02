(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local GraphView (require :graph/view))

(local KEY_SPACE (string.byte " "))
(local KEY_BACKQUOTE (string.byte "`"))
(local SDLK_RETURN 13)
(local SDLK_DELETE 127)
(local SDLK_F4 1073741885)

(fn NormalState []
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
    (local graph-view app.graph-view)
    (when (and graph-view graph-view.remove-selected-nodes)
        (> (graph-view:remove-selected-nodes) 0)))

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
           (let [focus-manager app.focus
                 graph-view app.graph-view]
             (if (and focus-manager focus-manager.activate-focused-from-payload)
                 (if (focus-manager:activate-focused-from-payload payload)
                     true
                     (and graph-view graph-view.open-focused-node
                          (graph-view:open-focused-node)))
                 (and graph-view graph-view.open-focused-node
                      (graph-view:open-focused-node))))
           (= key SDLK_DELETE)
           (remove-selected-nodes)
           (= key SDLK_F4)
           (toggle-graph-view)
           (= key KEY_BACKQUOTE)
           (open-fennel-interpreter)
           false))})

  (State
    {:name :normal
     :routes {:text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])
              :text-editing (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch])
              :key-down (Routes.FirstHandlerWins [NormalCommands
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
     :enter [HoverHandlers.HoverLifecycle]
     :leave [HoverHandlers.HoverLifecycle]}))

NormalState
