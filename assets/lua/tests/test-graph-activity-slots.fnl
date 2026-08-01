(local glm (require :glm))
(local fs (require :fs))
(local Main (require :main))
(local Activities (require :activities))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local Scene (require :scene))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local ObjectSelector (require :object-selector))
(local GraphActivityUnit (require :graph-activity-unit))
(local RootContextActions (require :root-context-menu-actions))
(local DrawingController (require :drawing/controller))
(local DrawingActivityUnit (require :drawing-activity-unit))
(local BoardActivityUnit (require :board-activity-unit))
(local Rectangle (require :rectangle))
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

(fn make-font-stub []
  (local glyph {:advance 1})
  {:metadata {:metrics {:ascender 1 :descender -0.25 :lineHeight 1.25}
              :atlas {:width 1 :height 1}}
   :glyph-map {65533 glyph}})

(fn make-icons-stub []
  (local font (make-font-stub))
  (local codepoints {:close 4242
                     :code 4242
                     :move_item 4242
                     :table 4242})
  {:font font
   :get (fn [_self name]
          (local value (. codepoints name))
          (assert value (.. "Missing icon " name))
          value)
   :resolve (fn [self name]
              {:type :font
               :codepoint (self:get name)
               :font self.font})})

(fn test-theme []
  {:font (make-font-stub)
   :graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
           :label-color (glm.vec4 1 1 1 1)
           :label-target-pixels 13.0
           :label-min-scale 4.0
           :edge-color (glm.vec4 0.6 0.6 0.6 1)}
   :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})

(fn make-panel-node []
  {:key "test-panel-node:one"
   :label "Panel Node"
   :view (fn [_node]
           (Rectangle {:color (glm.vec4 0.1 0.8 0.3 1)}))})

(fn count-clickables-for-target [target]
  (local clickables (assert app.clickables "graph activity slot test requires app.clickables")) (var count 0)
  (each [_ object (ipairs (or clickables.left-click-objects []))]
    (when (= object.pointer-target target)
      (set count (+ count 1))))
  count)

(fn graph-activity-builds-view-in-canvas-slot []
  (local app-keys [:active-world-runtime
                    :canvas
                    :graph-map
                    :graph-map-manager
                    :graph-view
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
                   :viewport
                   :themes])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.themes {:get-active-theme test-theme})
  (local data-dir "/tmp/space/tests/graph-activity-slots")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-activity-slot-test"}))
  (local canvas (Canvas {:camera camera
                          :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir})

  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph-map graph-map)
  ;; Pre-create canvas slots with activity-owned cameras so
  ;; active-slot camera resolution does not fall back to the
  ;; canvas constructor camera.
  (canvas:ensure-activity-slot "graph" {:camera camera})
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (Activities.activate-activity "graph")
        (local slot (canvas:activity-slot "graph"))
        (assert slot "Graph activity should create a graph canvas slot")
        (assert (= canvas.active-activity-slot slot)
                "Graph activity should activate its canvas slot")
        (assert (= slot.pointer-target.canvas-target-kind :graph-view)
                "Graph activity slot should expose graph view target kind")
        (assert app.graph-view "Graph activity should create a graph view")
        (assert (= app.graph-view.ctx slot.ctx)
                "Graph view should be built with the graph slot context")
        (assert (= app.graph-view.ctx.pointer-target slot.pointer-target)
                "Graph view context should route interactions through the graph slot pointer target")
        (assert (= app.graph-view.ctx.panel-target slot)
                "Graph view panels should route through the graph slot panel target")
        (local root-context (RootContextActions.empty-context :canvas))
        (assert (= root-context.targets.canvas slot)
                "Graph activity actions should receive the graph slot as the canvas panel target")
        (assert (= (canvas:get-triangle-vector) slot.ctx.triangle-vector)
                "Active graph slot draw data should be exposed by the canvas")
        (assert (not (= (canvas:get-triangle-vector) canvas.build-context.triangle-vector))
                "Graph activity should not draw through the default canvas context")
        (object-selector:on-mouse-button {:button 1 :state true :x 100 :y 100})
        (assert (> (length (slot.ctx:get-quad-draw-list)) 0)
                "Graph selector rectangle should draw through the active graph slot context")
        (assert (= (length (canvas.build-context:get-quad-draw-list)) 0)
                "Graph selector rectangle should not draw through the default canvas context")
        (object-selector:cancel-selection)
        (Activities.deactivate-active-activity)
        (assert (not slot.visible?)
                "Deactivating graph activity should hide the graph slot")
        (assert (not app.graph-view)
                "Deactivating graph activity should stop exposing app.graph-view")
         true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when runtime.graph-view
    (runtime.graph-view:drop)
    (set runtime.graph-view nil))
  (object-selector:drop)
  (graph-map:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph activity builds view in canvas activity slot"
                      :fn graph-activity-builds-view-in-canvas-slot})

(fn graph-panels-are-confined-to-graph-slot-after-activity-switch []
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph
                   :graph-map
                   :graph-map-manager
                   :graph-view
                   :drawing-controller
                   :drawing-render
                   :board
                   :board-view
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
                   :activity-target-enabled?
                   :pointer-target-enabled?
                   :canvas-controls
                   :first-person-controls
                   :set-canvas-visible
                   :set-active-interaction-surface
                   :sync-interaction-surface-state
                   :viewport
                   :themes
                   :renderers
                   :lights
                   :engine])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (set app.set-canvas-visible
       (fn [visible?]
         (set app.canvas-visible? (and app.canvas (not (= visible? false))))
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-visible nil))))
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-surface nil))))
  (local data-dir "/tmp/space/tests/graph-activity-slot-panels")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-activity-slot-panel-test"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager
                         :icons (make-icons-stub)}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  ;; Mock services needed by scene:activate-activity-slot and scene:capture-activity-slot-state
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  (var mock-lights-state {:ambient {:enabled? false :color [0.1 0.1 0.1] :intensity 1.0} :directional [] :point [] :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state) :set-state (fn [_ state] (set mock-lights-state state))})
  (set app.engine {:physics {:addRigidBody (fn [_phys _body]) :removeRigidBody (fn [_phys _body])}})
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local panel-node (make-panel-node))
  (graph:register-key-loader "test-panel-node"
                             (fn [key]
                               (assert (= key panel-node.key)
                                       "Unexpected test graph key")
                               panel-node))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
  (graph-map:load-by-key panel-node.key)
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
                  :drawing-controller controller
                  :board-state {:items [] :connectors []}})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph graph)
  (set app.graph-map graph-map)
  (set app.drawing-controller controller)
  ;; Pre-create canvas slots with activity-owned cameras.
  (canvas:ensure-activity-slot "graph" {:camera camera})
  (canvas:ensure-activity-slot "drawing" {:camera camera})
  (canvas:ensure-activity-slot "board" {:camera camera})
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (DrawingActivityUnit.load-drawing-activity!)
        (BoardActivityUnit.load-board-activity!)

        (Activities.activate-activity "graph")
        (local graph-slot (canvas:activity-slot "graph"))
        (assert graph-slot "Graph activity should create a graph slot")
        (local clickables-before-open (count-clickables-for-target graph-slot.pointer-target))
        (app.graph-view.views:open panel-node)
        (assert (= (length graph-slot.float.children) 1)
                "Graph node dialog should mount in the graph activity slot float")
        (assert (= (length canvas.float.children) 0)
                "Graph node dialog should not mount in the default canvas float")
        (assert (> (count-clickables-for-target graph-slot.pointer-target)
                   clickables-before-open)
                "Graph node dialog controls should register on the graph slot pointer target")
        (canvas:update)
        (assert (> (length (graph-slot.ctx:get-quad-draw-list)) 0)
                "Graph node dialog should draw through the graph slot context")
        (assert (= (length (canvas.build-context:get-quad-draw-list)) 0)
                "Graph node dialog should not draw through the default canvas context")
        (assert (app.pointer-target-enabled? graph-slot.pointer-target)
                "Graph panel pointer target should be enabled while graph is active")

        (Activities.activate-activity "drawing")
        (local drawing-slot (canvas:activity-slot "drawing"))
        (assert drawing-slot.visible?
                "Drawing slot should be visible after switching to drawing")
        (assert (not graph-slot.visible?)
                "Graph slot should hide after switching to drawing")
        (assert (= (length graph-slot.float.children) 1)
                "Inactive graph slot should retain its graph dialog")
        (assert (not (app.pointer-target-enabled? graph-slot.pointer-target))
                "Graph panel pointer target should be disabled while drawing is active")
        (assert (= (canvas:get-triangle-vector) drawing-slot.ctx.triangle-vector)
                "Canvas rendering should read vectors from the active drawing slot after graph deactivation")
        (assert (not (= (canvas:get-triangle-vector) graph-slot.ctx.triangle-vector))
                "Canvas rendering should stop reading vectors from the inactive graph slot")
        (assert (= (length (canvas:get-quad-draw-list))
                   (length (drawing-slot.ctx:get-quad-draw-list)))
                "Canvas quad rendering should match the active drawing slot after graph deactivation")

        (Activities.activate-activity "board")
        (local board-slot (canvas:activity-slot "board"))
        (assert board-slot.visible?
                "Board slot should be visible after switching to board")
        (assert (not graph-slot.visible?)
                "Graph slot should remain hidden after switching to board")
        (assert (not (app.pointer-target-enabled? graph-slot.pointer-target))
                "Graph panel pointer target should stay disabled while board is active")
        (assert (= (canvas:get-triangle-vector) board-slot.ctx.triangle-vector)
                "Canvas rendering should read vectors from the active board slot after graph deactivation")
        (assert (not (= (canvas:get-triangle-vector) graph-slot.ctx.triangle-vector))
                "Canvas rendering should keep ignoring vectors from the inactive graph slot")
        (assert (= (length (canvas:get-quad-draw-list))
                   (length (board-slot.ctx:get-quad-draw-list)))
                "Canvas quad rendering should match the active board slot after graph deactivation")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (pcall BoardActivityUnit.unload-board-activity!)
  (object-selector:drop)
  (graph-map:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph panels are confined to graph slot after activity switch"
                      :fn graph-panels-are-confined-to-graph-slot-after-activity-switch})

(fn graph-activity-scene-isolation-prevents-sandbox-inheritance []
  ;; When Sandbox has terrain/lights/etc and Graph activates, Graph's Scene
  ;; slot must be empty and must not inherit Sandbox content/environment.
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local ActivitySceneState (require :activity-scene-state))
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (local Scene (require :scene))
  (local SandboxActivityUnit (require :sandbox-activity-unit))
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph
                   :graph-map
                   :graph-map-manager
                   :graph-view
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
                   :set-canvas-visible
                   :set-active-interaction-surface
                   :sync-interaction-surface-state
                   :viewport
                   :themes
                   :lights
                   :renderers
                   :background-state
                   :skybox-state
                    :physics-containment-config
                    :engine
                    :pointer-target-enabled?
                    :camera
                    :scene])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (set app.set-canvas-visible
       (fn [visible?]
         (set app.canvas-visible? (and app.canvas (not (= visible? false))))
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-visible nil))))
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-surface nil))))

  ;; Mock renderer services: lights, skybox, background
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
  ;; Mock lights
  (var mock-lights-state {:ambient {:enabled? false
                                    :color [0.1 0.1 0.1]
                                    :intensity 1.0}
                           :directional []
                           :point []
                           :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state)
                   :set-state (fn [_ state]
                                (set mock-lights-state state))})
  ;; Mock physics
  (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                              :removeRigidBody (fn [_phys _body])}})

  (local data-dir "/tmp/space/tests/graph-scene-isolation")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-scene-isolation-test"}))
  (local scene (Scene {:camera camera}))
  (local canvas (Canvas {:camera camera
                          :focus-manager focus-manager}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.scene scene)
  (set app.graph graph)
  (set app.graph-map graph-map)
  (local (ok result)
    (pcall
      (fn []
        (SandboxActivityUnit.load-sandbox-activity!)
        (GraphActivityUnit.load-graph-activity!)

        ;; Give sandbox a non-default scene state with terrain and enabled lights/skybox
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

        ;; Activate Sandbox and verify services reflect sandbox state
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox")
                "Scene should report sandbox as active slot")
        ;; Sandbox camera must be owned by the scene slot, not a global
        (assert (= app.camera nil)
                "Sandbox camera must be owned by the sandbox scene slot, not app.camera")
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert sb-slot "Sandbox scene slot must exist")
          (assert sb-slot.camera "Sandbox scene slot must own its camera"))
        (assert (. mock-lights-state :ambient :enabled?)
                "Sandbox activation should enable ambient light")
        (assert skybox-state.enabled?
                "Sandbox activation should enable skybox")
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
        ;; Sandbox pointer target should be enabled while sandbox is active
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert (app.pointer-target-enabled? (. sb-slot :pointer-target))
                  "Sandbox pointer target should be enabled while sandbox is active"))

        ;; Switch to Graph
        (Activities.activate-activity "graph")
        (assert (= scene.active-activity-slot-id "graph")
                "Graph activation should make graph the active scene slot")
        ;; Graph slot should not be sandbox slot
        (local graph-slot (scene:activity-slot "graph"))
        (assert graph-slot "Graph should own a scene slot")
        (local sandbox-slot (scene:activity-slot "sandbox"))
        (assert (not (= graph-slot sandbox-slot))
                "Graph scene slot must not be Sandbox scene slot")
        ;; Graph services should be empty/disabled
        (assert (not (. mock-lights-state :ambient :enabled?))
                "Graph activation should disable ambient light (empty slot)")
        (assert (not skybox-state.enabled?)
                "Graph activation should disable skybox (empty slot)")
        ;; Graph slot captured state should have empty terrain and panels
        (local graph-captured (scene:capture-activity-slot-state "graph"))
        (assert (= (length graph-captured.terrains) 0)
                "Graph scene slot should have no terrains")
        (assert (= (length graph-captured.panels) 0)
                "Graph scene slot should have no panels")
        (assert (not graph-captured.lights.ambient.enabled?)
                "Captured graph state should have disabled ambient light")
        (assert (not graph-captured.skybox.enabled?)
                "Captured graph state should have disabled skybox")
        ;; Background should be reset to default (neutral/black)
        (assert (and app.background-state
                     (= (. app.background-state.color 1) 0.0)
                     (= (. app.background-state.color 2) 0.0)
                     (= (. app.background-state.color 3) 0.0))
                "Graph activation should reset background to default")
        ;; Containment should be disabled
        (let [g-slot (scene:activity-slot "graph")
              g-manager (and g-slot g-slot.physics-containment-manager)]
          (assert (and g-manager g-manager.config
                       (not g-manager.config.enabled?))
                  "Graph activation should disable containment"))
        ;; Sandbox pointer target should be rejected
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert (not (app.pointer-target-enabled? (. sb-slot :pointer-target)))
                  "Sandbox pointer target should be rejected while graph is active"))

        ;; Switch back to Sandbox — content should be preserved
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox")
                "Switching back to sandbox should restore sandbox as active scene slot")
        (assert (. mock-lights-state :ambient :enabled?)
                "Sandbox reactivation should re-enable ambient light")
        (assert skybox-state.enabled?
                "Sandbox reactivation should re-enable skybox")
        true)))
  (pcall SandboxActivityUnit.unload-sandbox-activity!)
  (pcall GraphActivityUnit.unload-graph-activity!)
  (object-selector:drop)
  (graph-map:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph activity scene isolation prevents sandbox inheritance"
                      :fn graph-activity-scene-isolation-prevents-sandbox-inheritance})

(fn graph-and-drawing-do-not-share-canvas-camera []
  ;; Graph and Drawing each own their canvas camera via
  ;; ensure-activity-canvas-camera!.  Activating graph then drawing
  ;; must give each its own camera — the drawing slot camera must not
  ;; inherit the graph slot camera position.
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph
                   :graph-map
                   :graph-map-manager
                   :graph-view
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
                   :viewport
                   :themes
                   :renderers
                   :lights
                   :engine])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  (var mock-lights-state {:ambient {:enabled? false :color [0.1 0.1 0.1] :intensity 1.0} :directional [] :point [] :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state) :set-state (fn [_ state] (set mock-lights-state state))})
  (set app.engine {:physics {:addRigidBody (fn [_phys _body]) :removeRigidBody (fn [_phys _body])}})
  (local data-dir "/tmp/space/tests/graph-drawing-camera-isolation")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-drawing-camera-isolation"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
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
                  :drawing-controller controller
                  :board-state {:items [] :connectors []}})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph graph)
  (set app.graph-map graph-map)
  (set app.drawing-controller controller)
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (DrawingActivityUnit.load-drawing-activity!)
        ;; Activate graph — camera is created in activity-cameras.canvas.graph
        (Activities.activate-activity "graph")
        (local graph-slot (canvas:activity-slot "graph"))
        (assert graph-slot "Graph should have a canvas slot")
        (assert graph-slot.camera "Graph slot must own its camera")
        ;; Move the graph camera
        (graph-slot.camera:set-position (glm.vec3 100 0 100))
        ;; Switch to drawing — camera is created in activity-cameras.canvas.drawing
        (Activities.activate-activity "drawing")
        (local drawing-slot (canvas:activity-slot "drawing"))
        (assert drawing-slot "Drawing should have a canvas slot")
        (assert drawing-slot.camera "Drawing slot must own its camera")
        ;; Drawing camera must NOT inherit graph camera position
        (assert (not (= drawing-slot.camera.position.x 100))
                "Drawing must not inherit Graph camera position")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (object-selector:drop)
  (graph-map:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph and drawing do not share canvas camera"
                     :fn graph-and-drawing-do-not-share-canvas-camera})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-activity-slots"
                       :tests tests})))

{:name "graph-activity-slots"
 :tests tests
 :main main}
