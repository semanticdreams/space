(local StateBase (require :state-base))
(local GraphView (require :graph/view))

(local KEY_SPACE (string.byte " "))
(local SDLK_RETURN 13)
(local SDLK_DELETE 127)
(local SDLK_F4 1073741885)

(fn NormalState []
  (local base (StateBase.make-state {:name :normal}))
  (local base-on-key-down base.on-key-down)
  (fn create-graph-view []
    (if (and app.graph-view-factory (= (type app.graph-view-factory) :function))
        (app.graph-view-factory)
        (do
          (assert app.graph "NormalState requires app.graph to create GraphView")
          (local ctx (and app.scene app.scene.build-context))
          (assert ctx "NormalState requires app.scene.build-context to create GraphView")
          (GraphView {:graph app.graph
                      :ctx ctx
                      :movables app.movables
                      :selector app.object-selector
                      :view-target app.hud
                      :camera app.camera
                      :pointer-target app.scene}))))

  (fn toggle-graph-view []
    (if app.graph-view
        (do
          (app.graph-view:drop)
          (set app.graph-view nil)
          true)
        (do
          (local view (create-graph-view))
          (assert view "NormalState GraphView factory returned nil")
          (set app.graph-view view)
          true)))

  (fn remove-selected-nodes []
    (local graph-view app.graph-view)
    (when (and graph-view graph-view.remove-selected-nodes)
        (> (graph-view:remove-selected-nodes) 0)))

  (fn handle-key-down [payload]
    (local key (and payload payload.key))
    (if (= key KEY_SPACE)
        (do
          (when (and app.engine app.states app.states.set-state)
            (app.states.set-state :leader))
          true)
        (= key SDLK_RETURN)
        (let [focus-manager app.focus
              graph-view app.graph-view]
          (if (and focus-manager focus-manager.activate-focused-from-payload)
              (if (focus-manager:activate-focused-from-payload payload)
                  true
                  (if (and graph-view graph-view.open-focused-node)
                      (or (graph-view:open-focused-node)
                          (base-on-key-down payload))
                      (base-on-key-down payload)))
              (if (and graph-view graph-view.open-focused-node)
                  (or (graph-view:open-focused-node)
                      (base-on-key-down payload))
                  (base-on-key-down payload))))
        (= key SDLK_DELETE)
        (if (remove-selected-nodes)
            true
            (base-on-key-down payload))
        (= key SDLK_F4)
        (toggle-graph-view)
        (base-on-key-down payload)))

  (StateBase.make-state
    {:name :normal
     :on-key-down handle-key-down}))

NormalState
