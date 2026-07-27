(global app (or app {}))

(local glm (require :glm))
(local fs (require :fs))
(local runtime (require :runtime))
(local Activities (require :activities))
(local DrawingInput (require :drawing/input))
(local {:DrawingRender DrawingRender} (require :drawing/render))
(local DrawingActivityActions (require :drawing-activity-actions))
(local HomeWorldCanvasRuntime (require :home-world-canvas-runtime))

(fn drawing-activity-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  [(fs.join-path lua-root "drawing-activity-unit.fnl")
    (fs.join-path lua-root "drawing-activity-actions.fnl")
    (fs.join-path (fs.join-path lua-root "drawing") "input.fnl")
    (fs.join-path (fs.join-path lua-root "drawing") "render.fnl")
    (fs.join-path (fs.join-path lua-root "drawing") "sidebar-view.fnl")])

(fn drawing-left-dock-builder [ctx]
  (local DrawingSidebarView (require :drawing/sidebar-view))
  (if app.drawing-controller
      ((DrawingSidebarView {:controller app.drawing-controller})
       ctx)
      nil))

(fn enrich-drawing-context! [context]
  (local controller app.drawing-controller)
  (local active-layer
    (and controller controller.active-layer
         (controller:active-layer)))
  (local selection-count
    (if (and controller controller.selection-count)
        (controller:selection-count)
        0))
  (local layer-count
    (if (and controller controller.layer-count)
        (controller:layer-count)
        0))
  (set context.drawing
       {:controller controller
        :active-layer active-layer
        :selection-count selection-count
        :layer-count layer-count
        :has-selection? (> selection-count 0)})
  context)

(fn drawing-target-enabled? [target]
  (= (and target target.canvas-target-kind) nil))

(fn drawing-activity-update [payload]
  (local runtime (and payload payload.runtime))
  (when (and runtime runtime.drawing-render)
    (runtime.drawing-render:update))
  nil)

(fn activate-drawing-render! []
  (local world-runtime (assert app.active-world-runtime
                                 "Drawing activity requires app.active-world-runtime"))
  (local canvas (assert world-runtime.canvas
                          "Drawing activity requires runtime.canvas"))
  (local controller (assert world-runtime.drawing-controller
                              "Drawing activity requires runtime.drawing-controller"))

  ;; Create or reuse a drawing canvas camera stored in runtime.activity-cameras.
  (local slot-camera
    (HomeWorldCanvasRuntime.ensure-activity-canvas-camera!
      world-runtime
      "drawing"
      {:position (glm.vec3 0 0 100)}))

  ;; Ensure the slot has the camera before activation
  (canvas:ensure-activity-slot "drawing" {:camera slot-camera})
  (local slot (canvas:activate-activity-slot "drawing"))
  (slot:set-canvas-target-kind! nil)
  (slot:expose-render-target! {:layers [:geometry]})
  (local render (or world-runtime.drawing-render
                    (DrawingRender {:ctx slot.ctx
                                    :controller controller
                                    :canvas canvas
                                    :camera slot.camera})))
  (set slot.root render)
  (set world-runtime.drawing-render render)
  (set app.drawing-render render)
  render)

(fn deactivate-drawing-render! []
  (local world-runtime app.active-world-runtime)
  (local canvas (and world-runtime world-runtime.canvas))
  (when canvas
    (canvas:deactivate-activity-slot "drawing"))
  (set app.drawing-render nil)
  true)

(fn drop-drawing-render! []
  (local world-runtime app.active-world-runtime)
  (local render (or (and world-runtime world-runtime.drawing-render)
                    app.drawing-render))
  (local canvas (and world-runtime world-runtime.canvas))
  (local slot (and canvas (canvas:activity-slot "drawing")))
  (when slot
    (set slot.root nil))
  (when render
    (render:drop))
  (when canvas
    (canvas:deactivate-activity-slot "drawing"))
  (when world-runtime
    (set world-runtime.drawing-render nil))
  (set app.drawing-render nil)
  true)

(fn root-actions [context]
  ((. DrawingActivityActions :drawing-root-actions) context))

(fn selection-actions [context]
  ((. DrawingActivityActions :drawing-selection-actions) context))

(fn activate-activity! [ctx]
  ;; Ensure and activate empty Scene slot before Canvas hooks
  ;; so Drawing does not inherit Sandbox content/environment/interaction.
  (let [runtime (assert app.active-world-runtime
                         "Drawing activity activation requires app.active-world-runtime")
        scene (assert runtime.scene
                       "Drawing activity activation requires runtime.scene")]
    (scene:ensure-activity-slot "drawing")
    (scene:activate-activity-slot "drawing"))
  (ctx:defer-cleanup! drop-drawing-render!)
  (local render (activate-drawing-render!))
  (ctx:set-drawing-enabled! true)
  (ctx:set-root-actions! root-actions)
  (ctx:set-selection-actions! selection-actions)
  (ctx:set-left-dock-builder! drawing-left-dock-builder)
  (ctx:set-command-hints-provider! (. DrawingInput :CommandHintsProvider))
  (ctx:set-context-enricher! enrich-drawing-context!)
  (ctx:set-input-handlers! {:key-down (. DrawingInput :DrawingKeyDown)
                            :mouse-button-down (. DrawingInput :DrawingMouseButtonDown)
                            :mouse-motion (. DrawingInput :DrawingMouseMotion)
                            :mouse-button-up (. DrawingInput :DrawingMouseButtonUp)})
  (ctx:set-target-enabled! drawing-target-enabled?)
  (ctx:set-update! drawing-activity-update)
  (ctx:set-surface-state! {:canvas {:visible? true :interactive? true}})
  (ctx:set-preferred-interaction-surface! :canvas)
  {:activity-id "drawing"
   :drawing-render render})

(fn deactivate-activity! [_ctx _session]
  (deactivate-drawing-render!)
  ;; Deactivate Scene slot after Canvas deactivation without dropping it
  (let [runtime (assert app.active-world-runtime
                         "Drawing activity deactivation requires app.active-world-runtime")
        scene (assert runtime.scene
                       "Drawing activity deactivation requires runtime.scene")]
    (scene:deactivate-activity-slot "drawing")))

(fn snapshot-drawing-activity! []
  (let [runtime (assert app.active-world-runtime
                         "Drawing activity snapshot requires app.active-world-runtime")
        scene (assert runtime.scene
                       "Drawing activity snapshot requires runtime.scene")
        scene-state (scene:capture-activity-slot-state "drawing")]
    {:active? (= (Activities.active-activity-id) "drawing")
     :scene scene-state}))

(fn restore-state-arg [first _session maybe-state]
  (if (and first (. first :activity))
      maybe-state
      first))

(fn restore-drawing-activity! [first session maybe-state]
  (local state (restore-state-arg first session maybe-state))
  (when (and state state.scene)
    (let [runtime (assert app.active-world-runtime
                           "Drawing activity restore requires app.active-world-runtime")
          scene (assert runtime.scene
                         "Drawing activity restore requires runtime.scene")]
      (scene:restore-activity-slot-state "drawing" state.scene)))
  (when (and state state.active?)
    (if app.set-active-activity
        (app.set-active-activity "drawing")
        (Activities.activate-activity "drawing")))
  true)

(fn activity-registered? [activity-id]
  (local (ok _resolved) (pcall Activities.resolve activity-id))
  ok)

(fn load-drawing-activity! []
  (when (not (activity-registered? "drawing"))
    (Activities.register-activity
      {:id "drawing"
       :label "Draw"
       :icon "draw"
        :button-name "drawing-activity"
        :show-in-switcher? true
        :activate activate-activity!
        :deactivate deactivate-activity!
        :snapshot snapshot-drawing-activity!
        :restore restore-drawing-activity!}))
  true)

(fn unload-drawing-activity! []
  (local registered? (activity-registered? "drawing"))
  (local active? (and registered?
                      (= (Activities.active-activity-id) "drawing")))
  (when active?
    (if app.set-active-activity
        (app.set-active-activity nil)
        (Activities.deactivate-active-activity)))
  (when registered?
    (Activities.unregister-activity "drawing"))
  true)

{:drawing-activity-owned-paths drawing-activity-owned-paths
 :load-drawing-activity! load-drawing-activity!
 :unload-drawing-activity! unload-drawing-activity!
 :snapshot-drawing-activity! snapshot-drawing-activity!
 :restore-drawing-activity! restore-drawing-activity!}
