(local glm (require :glm))
(local Canvas (require :canvas))
(local CanvasControls (require :canvas-controls))
(local ObjectSelector (require :object-selector))
(local Activities (require :activities))
(local WorkspaceShellState (require :home-world-workspace-shell-state))
(local viewport-utils (require :viewport-utils))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(local resolve-runtime-interaction-surface WorkspaceShellState.resolve-runtime-interaction-surface)
(local capture-activity-shell-state WorkspaceShellState.capture-activity-shell-state)

(fn project-canvas-position [canvas position opts]
  (local options (or opts {}))
  (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
  (assert viewport "HomeWorld canvas projection requires a viewport")
  (assert (> viewport.width 0) "HomeWorld canvas projection requires viewport width > 0")
  (assert (> viewport.height 0) "HomeWorld canvas projection requires viewport height > 0")
  (local view (or options.view
                  (and canvas canvas.get-view-matrix
                       (canvas:get-view-matrix))))
  (local projection (or options.projection
                        (and canvas canvas.projection)))
  (assert view "HomeWorld canvas projection requires a view matrix")
  (assert projection "HomeWorld canvas projection requires a projection matrix")
  (assert (and glm glm.project) "HomeWorld canvas projection requires glm.project")
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local projected (glm.project position view projection viewport-vec))
  (assert projected "glm.project returned nil")
  (glm.vec3 projected.x
            (- (+ viewport.height viewport.y) projected.y)
            projected.z))

(fn bind-runtime-canvas-selector! [runtime]
  (when (and runtime.scene runtime.scene.build-context)
    (set runtime.scene.build-context.object-selector runtime.object-selector))
  (when (and runtime.canvas runtime.canvas.build-context)
    (set runtime.canvas.build-context.object-selector runtime.object-selector))
  true)

(fn selector-build-context [canvas]
  (or (and canvas canvas.active-activity-slot canvas.active-activity-slot.ctx)
      (and canvas canvas.build-context)))

(fn clear-runtime-activity-sessions! [runtime]
  (each [activity-id _session (pairs (or runtime.activity-sessions {}))]
    (set (. runtime.activity-sessions activity-id) nil))
  true)

(fn clear-slot-root! [runtime activity-id root]
  (local slot (and runtime runtime.canvas runtime.canvas.activity-slot
                   (runtime.canvas:activity-slot activity-id)))
  (when (and slot (= slot.root root))
    (set slot.root nil))
  true)

(fn drop-runtime-canvas-surface! [runtime]
  (if (= app.active-world-runtime runtime)
      (Activities.with-workspace-shell-change-suppressed
        (fn []
          (Activities.deactivate-active-activity)
          (Activities.drop-all-activity-sessions!)))
      (clear-runtime-activity-sessions! runtime))
  (set runtime.activity-sessions nil)
  (when runtime.drawing-render
    (clear-slot-root! runtime "drawing" runtime.drawing-render)
    (runtime.drawing-render:drop)
    (set runtime.drawing-render nil))
  (when runtime.graph-view
    (clear-slot-root! runtime "graph" runtime.graph-view)
    (runtime.graph-view:drop)
    (set runtime.graph-view nil))
  (when runtime.board-view
    (clear-slot-root! runtime "board" runtime.board-view)
    (runtime.board-view:drop)
    (set runtime.board-view nil))
  (set runtime.board nil)
  (when runtime.object-selector
    (runtime.object-selector:drop)
    (set runtime.object-selector nil))
  (when runtime.canvas-controls
    (runtime.canvas-controls:drop)
    (set runtime.canvas-controls nil))
  (when runtime.canvas
    (runtime.canvas:drop)
    (set runtime.canvas nil))
  (set runtime.canvas-scope nil)
  true)

(fn load-runtime-canvas-surface! [world runtime]
  (assert runtime "HomeWorldCanvasRuntime.load-runtime-canvas-surface! requires runtime")
  (assert runtime.canvas-camera "HomeWorldCanvasRuntime requires runtime.canvas-camera")
  (assert runtime.focus-manager "HomeWorldCanvasRuntime requires runtime.focus-manager")
  (assert runtime.graph "HomeWorldCanvasRuntime requires runtime.graph")
  (assert runtime.drawing-controller "HomeWorldCanvasRuntime requires runtime.drawing-controller")
  (assert runtime.scene "HomeWorldCanvasRuntime requires runtime.scene")
  (drop-runtime-canvas-surface! runtime)
  (local canvas-state (or (and world.state world.state.canvas) {}))
  (local canvas
    (Canvas {:camera runtime.canvas-camera
             :focus-manager runtime.focus-manager
             :focus-scope-name (.. "canvas:" world.id)
             :icons runtime.icons
             :states runtime.states
             :movables runtime.movables
             :scale-factor canvas-state.scale_factor}))
  (local canvas-controls
    (CanvasControls {:canvas canvas
                     :camera runtime.canvas-camera}))
  (local object-selector
    (ObjectSelector {:ctx-provider (fn []
                                     (selector-build-context canvas))
                     :project (fn [position opts]
                                (project-canvas-position canvas position opts))
                      :enabled? true}))
  (set runtime.canvas canvas)
  (set runtime.canvas-controls canvas-controls)
  (set runtime.canvas-scope canvas.focus-scope)
  (set runtime.object-selector object-selector)
  (set runtime.graph-view nil)
  (set runtime.drawing-render nil)
  (bind-runtime-canvas-selector! runtime)
  true)

(fn capture-runtime-canvas-unit-state [world runtime]
  (local canvas-state
    (if (and runtime runtime.canvas runtime.canvas.capture-state)
        (runtime.canvas:capture-state)
        (clone-table (and world.state world.state.canvas))))
  (local activity-state (capture-activity-shell-state world runtime {}))
  (when (and runtime
             (= app.active-world-runtime runtime)
             Activities.snapshot-activity-sessions)
    (set activity-state.sessions (Activities.snapshot-activity-sessions)))
  {:canvas canvas-state
   :activity activity-state})

(fn restore-runtime-canvas-unit-state! [runtime state]
  (local unit-state (or state {}))
  (local canvas-state (clone-table (or unit-state.canvas {})))
  (local activity-state (clone-table (or unit-state.activity {})))
  (local (normalized-activity-id)
    (Activities.normalize-persisted-activity-id (and activity-state activity-state.active_id)))
  (set runtime.pending-canvas-state canvas-state)
  (set runtime.requested-activity-id normalized-activity-id)
  (set runtime.requested-activity-known? true)
  (set runtime.active-activity-id nil)
  (set runtime.activity-session-state (clone-table (or activity-state.sessions {})))
  (set runtime.activity-sessions {})
  (set runtime.preferred-interaction-surface
       (resolve-runtime-interaction-surface
          (or (and activity-state activity-state.preferred_interaction_surface)
              "scene")))
  true)

{:load-runtime-canvas-surface! load-runtime-canvas-surface!
 :drop-runtime-canvas-surface! drop-runtime-canvas-surface!
 :capture-runtime-canvas-unit-state capture-runtime-canvas-unit-state
 :restore-runtime-canvas-unit-state! restore-runtime-canvas-unit-state!}
