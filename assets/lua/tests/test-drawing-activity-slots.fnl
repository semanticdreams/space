(local glm (require :glm))
(local fs (require :fs))
(local Main (require :main))
(local Activities (require :activities))
(local Scene (require :scene))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local DrawingController (require :drawing/controller))
(local DrawingActivityUnit (require :drawing-activity-unit))
(local {: FocusManager} (require :focus))

(local tests [])

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn drawing-activity-builds-render-in-canvas-slot []
  (local app-keys [:active-world-runtime
                   :canvas
                   :drawing-controller
                   :drawing-render
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :canvas-controls
                   :first-person-controls])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (local data-dir "/tmp/space/tests/drawing-activity-slots")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "drawing-activity-slot-test"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local controller (DrawingController {:data_dir data-dir}))
  (controller:add-layer "vector")
  (controller:begin-gesture "rectangle" (glm.vec3 0 0 0))
  (controller:update-gesture (glm.vec3 24 12 0) false)
  (assert (controller:commit-gesture)
          "drawing activity slot test expected rectangle commit to succeed")
  (local runtime {:canvas canvas
                  :scene scene
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :drawing-controller controller})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.drawing-controller controller)
  (local (ok result)
    (pcall
      (fn []
        (DrawingActivityUnit.load-drawing-activity!)
        (Activities.activate-activity "drawing")
        (local slot (canvas:activity-slot "drawing"))
        (assert slot "Drawing activity should create a drawing canvas slot")
        (assert (= canvas.active-activity-slot slot)
                "Drawing activity should activate its canvas slot")
        (assert app.drawing-render "Drawing activity should create app.drawing-render")
        (assert (= slot.root app.drawing-render)
                "Drawing activity slot should own the drawing render")
        (app.drawing-render:update)
        (assert (= (canvas:get-triangle-vector) slot.ctx.triangle-vector)
                "Active drawing slot draw data should be exposed by the canvas")
        (assert (> (slot.ctx.triangle-vector:length) 0)
                "Drawing render should write vector geometry into the drawing slot")
        (assert (= (canvas.build-context.triangle-vector:length) 0)
                "Drawing activity should not draw through the default canvas context")
        (Activities.deactivate-active-activity)
        (assert (not slot.visible?)
                "Deactivating drawing activity should hide the drawing slot")
        (assert (not app.drawing-render)
                "Deactivating drawing activity should drop app.drawing-render")
        true)))
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (when runtime.drawing-render
    (runtime.drawing-render:drop)
    (set runtime.drawing-render nil))
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Drawing activity builds render in canvas activity slot"
                      :fn drawing-activity-builds-render-in-canvas-slot})

(fn drawing-activity-scene-isolation-prevents-sandbox-inheritance []
  ;; When Sandbox has terrain/lights/etc and Drawing activates, Drawing's Scene
  ;; slot must be empty and must not inherit Sandbox content/environment.
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local ActivitySceneState (require :activity-scene-state))
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (local Scene (require :scene))
  (local SandboxActivityUnit (require :sandbox-activity-unit))
  (local GraphActivityUnit (require :graph-activity-unit))
  (local Graph (require :graph/init))
  (local GraphMap (require :graph/map))
  (local ObjectSelector (require :object-selector))
  (local app-keys [:active-world-runtime
                   :canvas
                   :drawing-controller
                   :drawing-render
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :canvas-controls
                   :first-person-controls
                   :lights
                   :renderers
                   :background-state
                   :skybox-state
                   :physics-containment-config
                   :engine
                   :pointer-target-enabled?
                   :viewport
                   :themes
                   :scene])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.scene-interactive? true)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (Main.install-app-shell!)
  (local data-dir "/tmp/space/tests/drawing-scene-isolation")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "drawing-scene-isolation-test"}))
  (local scene (Scene {:camera camera}))
  (local canvas (Canvas {:camera camera
                          :focus-manager focus-manager}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)

  ;; Mock renderer services
  (var skybox-state {:enabled? false
                     :name "lake"
                     :brightness 0.5
                     :tint-color [1.0 1.0 1.0]})
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state]
                                            (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state]
                                               (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  (var mock-lights-state {:ambient {:enabled? false
                                    :color [0.1 0.1 0.1]
                                    :intensity 1.0}
                           :directional []
                           :point []
                           :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state)
                   :set-state (fn [_ state]
                                (set mock-lights-state state))})
  (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                              :removeRigidBody (fn [_phys _body])}})

  (local graph (Graph {:with-start false}))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local controller (DrawingController {:data_dir data-dir}))
  (controller:add-layer "vector")
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir
                  :drawing-controller controller})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.scene scene)
  (set app.drawing-controller controller)
  (local (ok result)
    (pcall
      (fn []
        (SandboxActivityUnit.load-sandbox-activity!)
        (DrawingActivityUnit.load-drawing-activity!)
        ;; Graph activity needed by sandbox tests but also provides graph-map for Sandbox
        (GraphActivityUnit.load-graph-activity!)

        ;; Give sandbox a non-default scene state
        (local sandbox-state
          {:panels []
           :terrains [{:kind "heightfield-terrain"}]
           :lights {:ambient {:enabled? true :color [1.0 1.0 1.0] :intensity 1.0}
                    :directional []
                    :point []
                    :spot []}
           :skybox {:enabled? true
                    :name "lake"
                    :brightness 0.5
                    :tint-color [1.0 1.0 1.0]}
           :background {:color [0.2 0.3 0.4]}
           :containment {:enabled? true}})
        (scene:restore-activity-slot-state "sandbox" sandbox-state)

        ;; Activate Sandbox
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox")
                "Scene should report sandbox as active slot")
        (assert (. mock-lights-state :ambient :enabled?)
                "Sandbox activation should enable ambient light")
        ;; Background and containment should reflect sandbox state
        (assert (and app.background-state
                     (= (. app.background-state.color 1) 0.2)
                     (= (. app.background-state.color 2) 0.3)
                     (= (. app.background-state.color 3) 0.4))
                "Sandbox activation should apply custom background color")
        (let [sb-slot (scene:activity-slot "sandbox")
              sb-manager (and sb-slot sb-slot.physics-containment-manager)]
          (assert (and sb-manager sb-manager.config sb-manager.config.enabled?)
                  "Sandbox containment should be enabled"))
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert (app.pointer-target-enabled? (. sb-slot :pointer-target))
                  "Sandbox pointer target should be enabled while sandbox is active"))

        ;; Switch to Drawing
        (Activities.activate-activity "drawing")
        (assert (= scene.active-activity-slot-id "drawing")
                "Drawing activation should make drawing the active scene slot")
        (local drawing-slot (scene:activity-slot "drawing"))
        (assert drawing-slot "Drawing should own a scene slot")
        (local sandbox-slot (scene:activity-slot "sandbox"))
        (assert (not (= drawing-slot sandbox-slot))
                "Drawing scene slot must not be Sandbox scene slot")
        ;; Drawing services should be empty/disabled
        (assert (not (. mock-lights-state :ambient :enabled?))
                "Drawing activation should disable ambient light (empty slot)")
        (assert (not skybox-state.enabled?)
                "Drawing activation should disable skybox (empty slot)")
        (local drawing-captured (scene:capture-activity-slot-state "drawing"))
        (assert (= (length drawing-captured.terrains) 0)
                "Drawing scene slot should have no terrains")
        (assert (= (length drawing-captured.panels) 0)
                "Drawing scene slot should have no panels")
        ;; Background should be reset to default
        (assert (and app.background-state
                     (= (. app.background-state.color 1) 0.0)
                     (= (. app.background-state.color 2) 0.0)
                     (= (. app.background-state.color 3) 0.0))
                "Drawing activation should reset background to default")
        ;; Containment should be disabled
        (let [d-slot (scene:activity-slot "drawing")
              d-manager (and d-slot d-slot.physics-containment-manager)]
          (assert (and d-manager d-manager.config
                       (not d-manager.config.enabled?))
                  "Drawing activation should disable containment"))
        ;; Sandbox pointer target should be rejected
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert (not (app.pointer-target-enabled? (. sb-slot :pointer-target)))
                  "Sandbox pointer target should be rejected while drawing is active"))

        ;; Switch back to Sandbox — content preserved
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox")
                "Switching back to sandbox should restore sandbox as active")
        (assert (. mock-lights-state :ambient :enabled?)
                "Sandbox reactivation should re-enable ambient light")
        (assert skybox-state.enabled?
                "Sandbox reactivation should re-enable skybox")
        true)))
  (pcall SandboxActivityUnit.unload-sandbox-activity!)
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when runtime.drawing-render
    (runtime.drawing-render:drop)
    (set runtime.drawing-render nil))
  (object-selector:drop)
  (graph-map:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Drawing activity scene isolation prevents sandbox inheritance"
                      :fn drawing-activity-scene-isolation-prevents-sandbox-inheritance})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-activity-slots"
                       :tests tests})))

{:name "drawing-activity-slots"
 :tests tests
 :main main}
