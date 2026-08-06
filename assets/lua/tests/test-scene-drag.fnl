(local glm (require :glm))
(local Main (require :main))
(local NormalState (require :normal-state))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))
(local Scene (require :scene))
(local Ball (require :ball))
(local Movables (require :movables))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Camera (require :camera))
(local Canvas (require :canvas))
(local CanvasControls (require :canvas-controls))
(local AppProjection (require :app-projection))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local {: FirstPersonControls} (require :first-person-controls))

(local tests [])
(local approx MathUtils.approx)

(fn reset-engine-events []
  (when _G.reset-engine-events
    (_G.reset-engine-events)))

(fn command-hints-handle-toggle-key [_manager _payload]
  true)

(fn command-hints-close-on-handled-event [_manager _route-key _payload]
  false)

(fn command-hints-hud-provider [_self]
  {:command-hints
   {:handle-toggle-key command-hints-handle-toggle-key
    :close-on-handled-event command-hints-close-on-handled-event}})

(fn bind-normal-state! [state]
  (local states (States {:hud_provider command-hints-hud-provider}))
  (states:add-state :normal state)
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  states)

(fn restore-states! [states]
  (StateSystemBindings.bind-states-host states)
  (set app.states states))

(fn provider-move [] :move)
(fn provider-grab [] :grab)
(fn provider-nil [] nil)

(fn snapshot-app []
  (local keys [:scene :canvas :layout-root :movables :intersectables :camera
               :first-person-controls :active-world-runtime :hoverables :clickables
               :engine :states :viewport :create-default-projection
               :active-interaction-surface :preferred-interaction-surface
               :scene-interactive? :canvas-interactive? :canvas-visible?
               :canvas-controls :active-pointer-controls :workspace-shell-changed
               :set-canvas-visible :set-active-interaction-surface
               :activity-object-drag-mode-provider])
  (local snapshot {:keys keys :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn restore-app! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn measure-unit-layout [self]
  (set self.measure (glm.vec3 1 1 1)))

(fn layout-to-measure [self]
  (set self.size self.measure))

(fn make-target-layout [name]
  (Layout {:name name
           :measurer measure-unit-layout
           :layouter layout-to-measure}))

(fn add-layout-target! [scene fixture name]
  (scene:build
    (fn [_ctx]
      (local target (make-target-layout name))
      (set fixture.target-layout target)
      {:layout target
       :drop (fn [_]
               (target:drop))}))
  (scene:update)
  fixture.target-layout)

(fn add-ball-target! [scene fixture]
  (app.engine.physics:setGravity 0 -25 0)
  (scene:build-default {:terrains []})
  (set fixture.ball
       (scene:add-object (Ball {:size (glm.vec3 6 6 6)})
                         {:position (glm.vec3 0 0 0)}))
  (scene:update)
  fixture.ball)

(fn add-physics-target! [scene fixture]
  (app.engine.physics:setGravity 0 -25 0)
  (scene:build-default {:terrains []})
  (set fixture.cuboid
       (scene:add-physics-body {:position (glm.vec3 0 0 0)
                                :size (glm.vec3 6 6 6)}))
  (scene:update)
  fixture.cuboid)

(fn install-canvas-hidden-shell! [fixture]
  (set fixture.canvas-camera (Camera {:position (glm.vec3 0 0 100)}))
  (set fixture.canvas (Canvas {:camera fixture.canvas-camera
                               :states app.states
                               :movables fixture.movables}))
  (set fixture.canvas-controls (CanvasControls {:canvas fixture.canvas
                                                :camera fixture.canvas-camera}))
  (set app.canvas fixture.canvas)
  (set app.canvas-controls fixture.canvas-controls)
  (Main.install-app-shell!)
  (app.set-active-interaction-surface :canvas)
  (app.set-canvas-visible false)
  (assert (= app.active-interaction-surface :scene)
          "Hidden canvas should fall back to scene interaction")
  true)

(fn start-normal-state! [fixture provider]
  (set fixture.state (NormalState))
  (bind-normal-state! fixture.state)
  (fixture.state.on-enter)
  (set app.activity-object-drag-mode-provider provider)
  true)

(fn fixture-input-controls [self]
  self.fixture.controls)

(fn fixture-camera-provider [self _opts]
  self.fixture.camera)

(fn fixture-screen-pos-ray [_self pointer _opts]
  {:origin (glm.vec3 pointer.x pointer.y 10)
   :direction (glm.vec3 0 0 -1)})

(fn setup-scene-drag-fixture! [fixture options]
  (reset-engine-events)
  (set fixture.intersector (Intersectables))
  (set fixture.clickables (assert (Clickables {:intersectables fixture.intersector})
                                  "Scene drag fixture requires clickables"))
  (set fixture.hoverables (assert (Hoverables {:intersectables fixture.intersector})
                                  "Scene drag fixture requires hoverables"))
  (set fixture.movables (Movables {:intersectables fixture.intersector}))
  (set fixture.camera (Camera {:position (glm.vec3 0 0 10)}))
  (set fixture.controls (FirstPersonControls {:camera fixture.camera}))
  (set app.active-world-runtime
       {:presentation {:fixture fixture
                       :input-controls fixture-input-controls
                       :camera fixture-camera-provider}})
  (set app.camera nil)
  (set app.first-person-controls nil)
  (set app.create-default-projection AppProjection.create-default-projection)
  (set fixture.scene (Scene {:position (glm.vec3 0 0 0)
                             :rotation (glm.quat 1 0 0 0)
                             :camera fixture.camera}))
  (set app.intersectables fixture.intersector)
  (set app.clickables fixture.clickables)
  (set app.hoverables fixture.hoverables)
  (set app.movables fixture.movables)
  (set app.scene fixture.scene)
  (set app.layout-root fixture.scene.layout-root)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (set app.scene-interactive? true)
  (set app.canvas-interactive? false)
  (fixture.scene:ensure-activity-slot "sandbox")
  (set fixture.sandbox-slot (fixture.scene:activate-activity-slot "sandbox"))
  (assert fixture.sandbox-slot "Scene drag fixture requires a sandbox slot")
  (if (= options.target :ball)
      (add-ball-target! fixture.scene fixture)
      (= options.target :physics)
      (add-physics-target! fixture.scene fixture)
      (add-layout-target! fixture.scene fixture (or options.name "scene-drag-target")))
  (set fixture.scene.screen-pos-ray fixture-screen-pos-ray)
  (when options.hidden-canvas?
    (install-canvas-hidden-shell! fixture))
  (start-normal-state! fixture options.provider)
  true)

(fn run-scene-drag-fixture! [fixture options f]
  (setup-scene-drag-fixture! fixture options)
  (f fixture))

(fn with-scene-drag-fixture [opts f]
  (local options (or opts {}))
  (local snapshot (snapshot-app))
  (local fixture {})
  (local (ok result) (pcall run-scene-drag-fixture! fixture options f))
  (when fixture.state
    (fixture.state.on-leave))
  (when fixture.canvas-controls (fixture.canvas-controls:drop))
  (when fixture.canvas (fixture.canvas:drop))
  (when fixture.scene (fixture.scene:drop))
  (when fixture.movables (fixture.movables:drop))
  (when fixture.intersector (fixture.intersector:drop))
  (when fixture.clickables
    (local clickables (assert fixture.clickables "Scene drag fixture cleanup requires clickables"))
    (clickables:drop))
  (when fixture.hoverables
    (local hoverables (assert fixture.hoverables "Scene drag fixture cleanup requires hoverables"))
    (hoverables:drop))
  (when fixture.controls (fixture.controls:drop))
  (when fixture.canvas-camera (fixture.canvas-camera:drop))
  (when fixture.camera (fixture.camera:drop))
  (restore-states! (. snapshot.values :states))
  (restore-app! snapshot)
  (if ok result (error result)))

(fn assert-drag-layout-with-provider-move [fixture]
      (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 0})
      (app.engine.events.mouse-motion.emit {:x 5.25 :y 5.75 :mod 0})
      (assert (app.movables:drag-active?)
              "Provider :move should start direct object drag without Alt")
      (assert (approx fixture.target-layout.position.x 5.0)
              "Provider :move should update layout X position")
      (assert (approx fixture.target-layout.position.y 5.5)
              "Provider :move should update layout Y position")
      (app.engine.events.mouse-button-up.emit {:button 1})
      (assert (not (app.movables:drag-active?)) "Drag should end on mouse-up")
      true)

(fn drag-layout-with-provider-move []
  (with-scene-drag-fixture
    {:provider provider-move :name "provider-move-drag-target"}
    assert-drag-layout-with-provider-move))

(fn assert-alt-drag-without-provider-is-blocked [_fixture]
      (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 256})
      (app.engine.events.mouse-motion.emit {:x 5.25 :y 5.75 :mod 256})
      (assert (not (app.movables:drag-active?))
              "Alt must not start object drag when the provider is nil")
      true)

(fn alt-drag-without-provider-is-blocked []
  (with-scene-drag-fixture
    {:provider nil :name "alt-without-provider-target"}
    assert-alt-drag-without-provider-is-blocked))

(fn assert-provider-nil-is-blocked [_fixture]
      (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 0})
      (app.engine.events.mouse-motion.emit {:x 5.25 :y 5.75 :mod 0})
      (assert (not (app.movables:drag-active?))
              "Provider nil should not start object drag")
      true)

(fn provider-nil-is-blocked []
  (with-scene-drag-fixture
    {:provider provider-nil :name "provider-nil-target"}
    assert-provider-nil-is-blocked))

(fn assert-provider-grab-reaches-physics-drag-path [fixture]
      (local cuboid (assert fixture.cuboid "Physics provider test requires cuboid"))
      (app.engine.events.mouse-button-down.emit {:button 1 :x 3.25 :y 3.25 :mod 0})
      (assert (= (and app.movables.drag app.movables.drag.entry.target) cuboid.layout)
              "Provider :grab should engage the cuboid movable target on mouse-down")
      (app.engine.events.mouse-motion.emit {:x 8.25 :y 9.25 :mod 0})
      (assert (app.movables:drag-active?)
              "Provider :grab should start physics-backed drag after motion threshold")
      (assert app.movables.drag.relative-anchor
              "Provider :grab should initialize the physics relative anchor path")
      ;; Task 3 only routes to the physics drag path; Bullet constraint release is Task 5.
      (set app.movables.drag nil)
      true)

(fn provider-grab-reaches-physics-drag-path []
  (with-scene-drag-fixture
    {:provider provider-grab :target :physics}
    assert-provider-grab-reaches-physics-drag-path))

(fn assert-provider-move-drags-ball [fixture]
      (local ball (assert fixture.ball "Ball provider test requires ball"))
      (app.engine.events.mouse-button-down.emit {:button 1 :x 3.25 :y 3.25 :mod 0})
      (app.engine.events.mouse-motion.emit {:x 7.25 :y 9.25 :mod 0})
      (assert (app.movables:drag-active?) "Provider :move should drag scene balls")
      (assert ball.dragging "Ball movable should enter dragging mode")
      (fixture.scene:update)
      (assert (> ball.layout.position.x 3.5) "Ball drag should move along X")
      (assert (> ball.layout.position.y 5.5) "Ball drag should move along Y")
      (app.engine.events.mouse-button-up.emit {:button 1 :mod 0})
      true)

(fn provider-move-drags-ball []
  (with-scene-drag-fixture
    {:provider provider-move :target :ball}
    assert-provider-move-drags-ball))

(fn assert-hidden-canvas-does-not-block-provider-move [fixture]
      (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 0})
      (app.engine.events.mouse-motion.emit {:x 5.25 :y 5.75 :mod 0})
      (assert (app.movables:drag-active?)
              "Hidden canvas should not block provider-enabled scene drag")
      (assert (approx fixture.target-layout.position.x 5.0)
              "Hidden canvas drag should update layout X")
      (assert (approx fixture.target-layout.position.y 5.5)
              "Hidden canvas drag should update layout Y")
      (app.engine.events.mouse-button-up.emit {:button 1 :mod 0})
      true)

(fn hidden-canvas-does-not-block-provider-move []
  (with-scene-drag-fixture
    {:provider provider-move
     :hidden-canvas? true
     :name "hidden-canvas-provider-move-target"}
    assert-hidden-canvas-does-not-block-provider-move))

(fn assert-click-without-drag-threshold-remains-click [fixture]
      (local initial-x fixture.target-layout.position.x)
      (local initial-y fixture.target-layout.position.y)
      (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 0})
      (app.engine.events.mouse-motion.emit {:x 0.26 :y 0.26 :mod 0})
      (assert (not (app.movables:drag-active?))
              "Tiny motion below threshold should not start drag")
      (assert (approx fixture.target-layout.position.x initial-x)
              "Click without drag should not move layout X")
      (assert (approx fixture.target-layout.position.y initial-y)
              "Click without drag should not move layout Y")
      (app.engine.events.mouse-button-up.emit {:button 1 :mod 0})
      true)

(fn click-without-drag-threshold-remains-click []
  (with-scene-drag-fixture
    {:provider provider-move :name "click-without-drag-target"}
    assert-click-without-drag-threshold-remains-click))

(table.insert tests {:name "Provider move drags real scene entity"
                     :fn drag-layout-with-provider-move})
(table.insert tests {:name "Alt drag blocked without object drag provider"
                     :fn alt-drag-without-provider-is-blocked})
(table.insert tests {:name "Object drag blocked when provider returns nil"
                     :fn provider-nil-is-blocked})
(table.insert tests {:name "Provider grab reaches physics drag path"
                     :fn provider-grab-reaches-physics-drag-path})
(table.insert tests {:name "Provider move drags scene ball"
                     :fn provider-move-drags-ball})
(table.insert tests {:name "Hidden canvas does not block provider move"
                     :fn hidden-canvas-does-not-block-provider-move})
(table.insert tests {:name "Click without drag threshold remains click"
                     :fn click-without-drag-threshold-remains-click})

(local main
  (fn []
    (set (. package.loaded :main) nil)
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-drag" :tests tests})))

{:name "scene-drag"
 :tests tests
 :main main}
