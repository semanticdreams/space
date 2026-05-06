(local glm (require :glm))
(local Canvas (require :canvas))
(local CanvasControls (require :canvas-controls))
(local GraphView (require :graph/view))
(local ObjectSelector (require :object-selector))
(local {:DrawingRender DrawingRender} (require :drawing/render))
(local CanvasFeatures (require :canvas-features))
(local CanvasShellState (require :home-world-canvas-shell-state))
(local viewport-utils (require :viewport-utils))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(local resolve-runtime-interaction-surface CanvasShellState.resolve-runtime-interaction-surface)
(local capture-canvas-shell-state CanvasShellState.capture-canvas-shell-state)

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

(fn drop-runtime-canvas-surface! [runtime]
  (when runtime.drawing-render
    (runtime.drawing-render:drop)
    (set runtime.drawing-render nil))
  (when runtime.graph-view
    (runtime.graph-view:drop)
    (set runtime.graph-view nil))
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
  (local graph-canvas-target
    {:interaction-surface :canvas
     :canvas-feature "graph"
     :screen-pos-ray (fn [_self pos opts]
                       (canvas:screen-pos-ray pos opts))})
  (local object-selector
    (ObjectSelector {:ctx (and canvas canvas.build-context)
                     :project (fn [position opts]
                                (project-canvas-position canvas position opts))
                     :enabled? true}))
  (local graph-view
    (GraphView {:graph runtime.graph
                :ctx (and canvas canvas.build-context)
                :movables runtime.movables
                :selector object-selector
                :view-target canvas
                :camera runtime.canvas-camera
                :pointer-target graph-canvas-target
                :data-dir world.dir}))
  (local drawing-render
    (DrawingRender {:ctx (and canvas canvas.build-context)
                    :controller runtime.drawing-controller
                    :canvas canvas}))
  (set runtime.canvas canvas)
  (set runtime.canvas-controls canvas-controls)
  (set runtime.canvas-scope canvas.focus-scope)
  (set runtime.object-selector object-selector)
  (set runtime.graph-view graph-view)
  (set runtime.drawing-render drawing-render)
  (bind-runtime-canvas-selector! runtime)
  true)

(fn capture-runtime-canvas-unit-state [world runtime]
  (local canvas-state
    (if (and runtime runtime.canvas runtime.canvas.capture-state)
        (runtime.canvas:capture-state)
        (clone-table (and world.state world.state.canvas))))
  (capture-canvas-shell-state world runtime canvas-state))

(fn restore-runtime-canvas-unit-state! [runtime state]
  (local canvas-state (clone-table (or state {})))
  (set runtime.pending-canvas-state canvas-state)
  (set runtime.active-canvas-feature
       (CanvasFeatures.resolve
         (or canvas-state.active_feature
             (. CanvasFeatures :default-feature-id))))
  (set runtime.preferred-interaction-surface
       (resolve-runtime-interaction-surface
         (or canvas-state.preferred_interaction_surface
             "scene")))
  true)

{:load-runtime-canvas-surface! load-runtime-canvas-surface!
 :drop-runtime-canvas-surface! drop-runtime-canvas-surface!
 :capture-runtime-canvas-unit-state capture-runtime-canvas-unit-state
 :restore-runtime-canvas-unit-state! restore-runtime-canvas-unit-state!}
