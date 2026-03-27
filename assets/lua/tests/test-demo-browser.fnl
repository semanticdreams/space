(local glm (require :glm))
(local Scene (require :scene))
(local Ball (require :ball))
(local Camera (require :camera))
(local BuildContext (require :build-context))
(local Hud (require :hud))
(local Graph (require :graph/init))
(local DemoDialogs (require :demo-dialogs))
(local HeightfieldTargetCapture (require :graph/view/heightfield-target-capture))
(local HeightfieldPaintCapture (require :graph/view/heightfield-paint-capture))
(local States (require :states))
(local TerrainRectPickState (require :terrain-rect-pick-state))
(local TerrainPaintManager (require :graph/view/terrain-paint-manager))
(local TerrainPaintState (require :terrain-paint-state))
(local MathUtils (require :math-utils))
(local PhysicsContainment (require :physics-containment))
(local SceneTerrainRecovery (require :scene-terrain-recovery))
(local TerrainQuery (require :terrain-query))
(local HeightfieldTerrainSpace (require :heightfield-terrain-space))
(local {: Layout} (require :layout))
(local bt (require :bt))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local fixtures (require :tests/http-fixtures))
(local TestSupport (require :tests/test-support))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec3-approx= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn quat-approx= [a b]
  (and (approx a.w b.w)
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn runtime-balls [scene]
  (local balls [])
  (each [_ metadata (ipairs (or scene.scene-children []))]
    (local element (and metadata metadata.element))
    (when (and element element.is-physics-ball)
      (table.insert balls element)))
  balls)

(fn find-close-button [element]
  (local dialog (or element.front element.__front_widget element.child element))
  (local titlebar-meta (. dialog.children 1))
  (local titlebar titlebar-meta.element)
  (local title-flex (. titlebar.children 2))
  (local action-row-meta (. title-flex.children (length title-flex.children)))
  (local action-row action-row-meta.element)
  (local close-meta (. action-row.children (length action-row.children)))
  close-meta.element)

(fn make-icons-stub []
  (local stub {:font {:glyph-map {65533 {:advance 1.0}}
                      :metadata {:metrics {:lineHeight 1.0
                                           :ascender 0.5
                                           :descender -0.5}
                                 :atlas {:width 1
                                         :height 1}}}})
  (set stub.get
       (fn [_self _name]
         4242))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(fn make-stub-movables []
  (local registered [])
  (local movables {:registered registered :unregistered []})
  (set movables.register
       (fn [self widget opts]
         (table.insert self.registered {:widget widget
                                        :opts opts})))
  (set movables.unregister
       (fn [self key]
         (table.insert self.unregistered key)))
  movables)

(fn make-clickables-menu-stub []
  (local state {:registered-right-click []
                :unregistered-right-click []})
  {:state state
   :register-right-click (fn [_self obj]
                           (table.insert state.registered-right-click obj))
   :unregister-right-click (fn [_self obj]
                             (table.insert state.unregistered-right-click obj))})

(fn array->vec3 [arr]
  (glm.vec3 (. arr 1) (. arr 2) (. arr 3)))

(fn array->quat [arr]
  (glm.quat (. arr 1) (. arr 2) (. arr 3) (. arr 4)))

(fn terrain-surface-height-at-local-point [record local-x local-z]
  (local info (TerrainQuery.surface-info-at-local-point record local-x local-z))
  (and info info.local-surface-y))

(fn terrain-world-point-from-runtime-layout [record terrain-layout local-point]
  (+ terrain-layout.position
     (terrain-layout.rotation:rotate
       (HeightfieldTerrainSpace.canonical-local->runtime-local record local-point))))

(fn elevated-probe-point-in-cell [record cell-x cell-z min-height]
  (local spacing (HeightfieldTerrainGrid.spacing record))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local base-x (* cell-x spacing-x))
  (local base-z (* cell-z spacing-z))
  (local candidates [[0.8 0.8]
                     [0.2 0.8]
                     [0.8 0.2]
                     [0.2 0.2]
                     [0.65 0.65]
                     [0.35 0.65]
                     [0.65 0.35]
                     [0.5 0.5]])
  (var found nil)
  (each [_ uv (ipairs candidates)]
    (when (not found)
      (local local-point (glm.vec3 (+ base-x (* (. uv 1) spacing-x))
                                   0
                                   (+ base-z (* (. uv 2) spacing-z))))
      (local local-surface-y
        (terrain-surface-height-at-local-point record local-point.x local-point.z))
      (when (and local-surface-y (> local-surface-y (or min-height 1.0)))
        (set found local-point))))
  found)

(fn terrain-cell-heights [record cell-x cell-z]
  (local chunk-map (HeightfieldTerrainGrid.build-chunk-map record))
  (local h00 (HeightfieldTerrainGrid.sample-height-global record chunk-map cell-x cell-z))
  (local h01 (HeightfieldTerrainGrid.sample-height-global record chunk-map cell-x (+ cell-z 1)))
  (local h10 (HeightfieldTerrainGrid.sample-height-global record chunk-map (+ cell-x 1) cell-z))
  (local h11 (HeightfieldTerrainGrid.sample-height-global record chunk-map (+ cell-x 1) (+ cell-z 1)))
  (if (or (= h00 nil) (= h01 nil) (= h10 nil) (= h11 nil))
      nil
      {:h00 h00 :h01 h01 :h10 h10 :h11 h11}))

(fn broad-elevated-probe-point-in-cell [record cell-x cell-z min-height]
  (local heights (terrain-cell-heights record cell-x cell-z))
  (when heights
    (local min-cell-height
      (math.min heights.h00 heights.h01 heights.h10 heights.h11))
    (when (> min-cell-height (or min-height 1.0))
      (local spacing (HeightfieldTerrainGrid.spacing record))
      (local spacing-x (. spacing 1))
      (local spacing-z (. spacing 2))
      (glm.vec3 (+ (* cell-x spacing-x) (* spacing-x 0.5))
                0
                (+ (* cell-z spacing-z) (* spacing-z 0.5))))))

(fn collect-broad-elevated-probes [record min-height]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local probes [])
  (for [sample-z bounds.min-sample-z (- bounds.max-sample-z 1)]
    (for [sample-x bounds.min-sample-x (- bounds.max-sample-x 1)]
      (local point
        (broad-elevated-probe-point-in-cell record sample-x sample-z min-height))
      (when point
        (local heights (terrain-cell-heights record sample-x sample-z))
        (table.insert probes {:sample-x sample-x
                              :sample-z sample-z
                              :min-height (math.min heights.h00 heights.h01 heights.h10 heights.h11)
                              :max-height (math.max heights.h00 heights.h01 heights.h10 heights.h11)
                              :point point}))))
  probes)

(fn representative-probes [probes max-count]
  (local count (length probes))
  (local wanted (math.max 0 (or max-count 4)))
  (if (or (= wanted 0) (= count 0) (<= count wanted))
      probes
      (= wanted 1)
      [(. probes 1)]
      (do
        (local selected [])
        (local used {})
        (for [idx 0 (- wanted 1)]
          (local probe-index
            (+ 1 (math.floor (/ (* idx (- count 1)) (- wanted 1)))))
          (when (not (. used probe-index))
            (set (. used probe-index) true)
            (table.insert selected (. probes probe-index))))
        selected)))

(fn first-home-world-path []
  (TestSupport.fixture-path "terrain-live-pick-world.json"))

(fn wait-for-terrain-layout-stable [scene terrain-id max-updates]
  (local updates (or max-updates 12))
  (var previous-position nil)
  (var previous-rotation nil)
  (var stable-layout nil)
  (for [_ 1 updates]
    (when (not stable-layout)
      (scene:update)
      (var terrain-entry nil)
      (when terrain-id
        (each [_ metadata (ipairs (or scene.scene-terrains []))]
          (when (and (not terrain-entry)
                     metadata.record
                     (= metadata.record.id terrain-id))
            (set terrain-entry metadata))))
      (when (and (not terrain-id) (. scene.scene-terrains 1))
        (set terrain-entry (. scene.scene-terrains 1)))
      (local layout (and terrain-entry terrain-entry.element terrain-entry.element.layout))
      (when layout
        (if (and previous-position
                 previous-rotation
                 (vec3-approx= previous-position layout.position)
                 (quat-approx= previous-rotation layout.rotation))
            (set stable-layout layout)
            (do
              (set previous-position (glm.vec3 layout.position.x layout.position.y layout.position.z))
              (set previous-rotation (glm.quat layout.rotation.w
                                               layout.rotation.x
                                               layout.rotation.y
                                               layout.rotation.z)))))))
  (assert stable-layout "Expected terrain layout to stabilize")
  stable-layout)

(fn random-range [min-value max-value]
  (+ min-value (* (math.random) (- max-value min-value))))

(fn manual-containment-config [min-y]
  {:mode "manual-bounds"
   :bounds {:min [-500 min-y -500]
            :max [500 500 500]}})

(fn configure-test-physics-world [opts]
  (local options (or opts {}))
  (when (and app.engine app.engine.physics)
    (app.engine.physics:setGravity 0 -25 0)
    (PhysicsContainment.ensure-installed
      {:config (or options.config
                   app.physics-containment-config
                   (PhysicsContainment.default-config))})))

(fn setup-scene [opts]
  (local options (or opts {}))
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-camera app.camera)
  (local original-hud app.hud)
  (local original-containment-config app.physics-containment-config)
  (var scene nil)
  (var movables nil)
  (var hud nil)
  (local icons (make-icons-stub))

  (fn cleanup []
    (when scene
      (scene:drop)
      (set scene nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.camera original-camera)
    (set app.hud original-hud)
    (PhysicsContainment.clear)
    (set app.physics-containment-config original-containment-config))

  (let [(ok payload)
        (pcall (fn []
                 (set movables (make-stub-movables))
                 (set scene (Scene {:icons icons
                                    :position (or options.scene-position nil)
                                    :rotation (or options.scene-rotation nil)}))
                 (set hud {:world-units-per-pixel 1})
                 (set hud.build-context (BuildContext {:pointer-target hud}))
                 (set hud.on-viewport-changed (fn [_self _viewport] nil))
                 (set app.scene scene)
                 (set app.hud hud)
                 (set app.layout-root scene.layout-root)
                 (set app.movables movables)
                 (when options.camera
                   (set app.camera options.camera))
                 (when options.containment-config
                   (set app.physics-containment-config options.containment-config))
                 (configure-test-physics-world {:config options.containment-config})
                 (scene:build-default)
                 {:scene scene :movables movables :icons icons :hud hud}))]
    (if ok
        {:cleanup cleanup :scene-result payload}
        (do
          (cleanup)
          (error payload)))))

(fn random-flat-heights [width depth]
  (local heights [])
  (for [_ 1 (* width depth)]
    (table.insert heights 0.0))
  heights)

(fn flat-heightfield-record [opts]
  (local options (or opts {}))
  (local chunk-width (or options.chunk-width 5))
  (local chunk-depth (or options.chunk-depth 5))
  (local height (or options.height 0.0))
  {:id (or options.id "terrain-a")
   :kind "heightfield-terrain"
   :options {:position (or options.position [0 -100 0])
             :rotation (or options.rotation [1 0 0 0])
             :sample-spacing (or options.sample-spacing [20 20])
             :chunk-samples [chunk-width chunk-depth]
             :default-height height}
   :chunks [{:coord [0 0]
             :size [chunk-width chunk-depth]
             :heights
             (icollect [_ _height-index (ipairs (random-flat-heights chunk-width chunk-depth))]
               height)}]})

(fn make-fixed-panel-builder [opts]
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 10 10 10)))
  (fn [_ctx _builder-options]
    (local layout
      (Layout {:name (or options.name "fixed-panel")
               :measurer (fn [self]
                           (set self.measure size))
               :layouter (fn [self]
                           (set self.size self.measure))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))}))

(fn make-terrain-bound-test-object [opts]
  (local options (or opts {}))
  {:scene-object-options
   (fn [_self]
     {:builder (make-fixed-panel-builder {:size (or options.size (glm.vec3 10 10 10))
                                          :name (or options.name "terrain-bound-test-object")})
      :skip-cuboid true
      :skip-physics true
      :terrain-binding {:enabled? true
                        :get-support-bounds
                        (fn [entry]
                          (local origin (entry:get-origin-position))
                          (local support-offset (or options.support-offset (glm.vec3 0 0 0)))
                          {:position (+ origin support-offset)
                           :rotation (or options.support-rotation (glm.quat 1 0 0 0))
                           :size (or options.support-size
                                     options.size
                                     (glm.vec3 10 10 10))})}})})

(fn make-unbound-test-object [opts]
  (local options (or opts {}))
  {:scene-object-options
   (fn [_self]
     {:builder (make-fixed-panel-builder {:size (or options.size (glm.vec3 10 10 10))
                                          :name (or options.name "unbound-test-object")})
      :skip-cuboid true
      :skip-physics true})})

(fn random-heightfield-record [seed]
  (math.randomseed seed)
  (local chunk-width 5)
  (local chunk-length 5)
  (local min-chunk-x (- (math.random 0 1)))
  (local max-chunk-x (+ min-chunk-x (math.random 0 2)))
  (local min-chunk-z (- (math.random 0 1)))
  (local max-chunk-z (+ min-chunk-z (math.random 0 2)))
  (local chunks [])
  (for [chunk-z min-chunk-z max-chunk-z]
    (for [chunk-x min-chunk-x max-chunk-x]
      (table.insert chunks
        {:coord [chunk-x chunk-z]
         :size [chunk-width chunk-length]
         :heights (random-flat-heights chunk-width chunk-length)})))
  (local yaw (random-range (- math.pi) math.pi))
  (local half-angle (/ yaw 2))
  {:id "terrain-a"
   :kind "heightfield-terrain"
   :options {:position [(random-range -10 10) 0 (random-range -10 10)]
             :rotation [(math.cos half-angle) 0 (math.sin half-angle) 0]
             :sample-spacing [(random-range 0.75 3.5) (random-range 0.75 3.5)]
             :chunk-samples [chunk-width chunk-length]
             :default-height 0.0}
   :chunks chunks})

(fn camera-looking-at [position target]
  (local direction (glm.normalize (- target position)))
  (local yaw (math.atan direction.x (- direction.z)))
  (local horizontal (math.sqrt (+ (* direction.x direction.x)
                                  (* direction.z direction.z))))
  (local pitch (- (math.atan direction.y horizontal)))
  (Camera {:position position
           :rotation (glm.quat (glm.vec3 pitch yaw 0))}))

(fn demo-browser-adds-dialogs-to-scene []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local movables setup.scene-result.movables)

  (let [(ok err)
        (pcall (fn []
                 (scene:add-demo-browser)
                 (assert (= (length scene.scene-children) 1)
                         "Browser should add itself to the scene container")
                 (local entry (DemoDialogs.find-entry :welcome-dialog))
                 (scene:add-demo-entry entry)
                 (assert (= (length scene.scene-children) 2)
                         "Scene should contain browser and the opened dialog")
                 (assert (>= (length scene.entity.__scene_movable_keys) 2)
                         "Movables should track added scene children")
                 (assert (>= (length movables.registered) 2)
                         "Movables register should record registrations for positioned children")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn closing-demo-dialog-removes-positioned-child []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local movables setup.scene-result.movables)

  (let [(ok err)
        (pcall (fn []
                 (scene:add-demo-browser)
                 (local entry (DemoDialogs.find-entry :welcome-dialog))
                 (local element (scene:add-demo-entry entry))
                 (assert element "Expected demo entry to be created")
                 (local close-button (find-close-button element))
                 (assert (= close-button.icon "close"))
                 (close-button:on-click {:button 1})
                 (assert (= (length scene.scene-children) 1)
                         "Closing dialog should remove the positioned child")
                 (assert (>= (length scene.entity.__scene_movable_keys) 1)
                         "Movables should track remaining scene children after closing")
                 (assert (>= (length movables.unregistered) 1)
                         "Closing dialog should unregister removed movable entries")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn demo-browser-capture-and-restore-roundtrip []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local browser (scene:add-demo-browser))
            (assert browser "Expected demo browser element")
            (local captured (scene:capture-state))
            (local panels (or captured.panels []))
            (assert (= (length panels) 1)
                    "Expected one persisted scene panel for demo browser")
            (local panel (. panels 1))
            (assert (= panel.kind "demo-browser")
                    "Demo browser persistence kind should be demo-browser")

            (scene:remove-panel-child browser)
            (assert (= (length scene.scene-children) 0)
                    "Expected demo browser removal before restore")

            (scene:restore-state captured)
            (assert (= (length scene.scene-children) 1)
                    "Demo browser should restore from captured scene state")
            (assert scene.demo-browser
                    "Scene.demo-browser handle should be re-established after restore")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-capture-state-includes-default-terrain []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (local captured (scene:capture-state))
        (local terrains (or captured.terrains []))
        (assert (= (length terrains) 1)
                "Expected one default terrain in captured scene state")
        (local terrain (. terrains 1))
        (assert (= terrain.kind "heightfield-terrain")
                "Expected default terrain kind heightfield-terrain")
        (assert terrain.id "Expected captured terrain id"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-recover-terrain-bound-panel-uses-lowest-overlapping-terrain []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local low-terrain (flat-heightfield-record {:id "low-terrain"
                                               :position [0 -100 0]
                                               :height 0.0}))
  (local high-terrain (flat-heightfield-record {:id "high-terrain"
                                                :position [0 -80 0]
                                                :height 0.0}))
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [low-terrain high-terrain]})
        (local element
          (scene:add-panel-child {:builder (make-fixed-panel-builder {:name "recover-lowest-panel"})
                                  :skip-physics true
                                  :position (glm.vec3 30 -220 30)}))
        (assert element "Expected scene panel child")
        (local results (SceneTerrainRecovery.recover scene))
        (assert (= (length results) 1) "Expected one recovered terrain-bound entry")
        (assert (approx element.layout.position.x 30.0))
        (assert (approx element.layout.position.z 30.0))
        (assert (approx element.layout.position.y -100.0)
                (string.format
                  "Panel should recover to the lowest overlapping terrain surface (actual_y=%.3f)"
                  element.layout.position.y)))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-recover-terrain-bound-object-moves-to-nearest-terrain []
  (local setup (setup-scene {:scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain (flat-heightfield-record {:id "terrain-a"
                                           :position [0 -100 0]
                                           :height 0.0}))
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain]})
        (local object
          (make-terrain-bound-test-object {:name "nearest-terrain-object"
                                           :support-offset (glm.vec3 0 -5 0)}))
        (local element
          (scene:add-object object
                            {:position (glm.vec3 130 -260 150)}))
        (assert element "Expected terrain-bound test object")
        (local entries (SceneTerrainRecovery.collect-entries scene))
        (assert (= (length entries) 1) "Expected one terrain-bound entry")
        (local results (SceneTerrainRecovery.recover scene))
        (local result (. results 1))
        (assert (= (length results) 1) "Expected one recovery result")
        (assert (= result.mode :nearest)
                "Object outside all terrain domains should snap to nearest terrain")
        (assert result.target "Expected nearest-terrain recovery target")
        (assert (approx element.layout.position.x result.target.world-point.x)
                (string.format
                  "Expected recovered x to match nearest terrain target (actual_x=%.3f target_x=%.3f)"
                  element.layout.position.x
                  result.target.world-point.x))
        (assert (approx element.layout.position.z result.target.world-point.z)
                (string.format
                  "Expected recovered z to match nearest terrain target (actual_z=%.3f target_z=%.3f)"
                  element.layout.position.z
                  result.target.world-point.z))
        (assert (approx element.layout.position.y (- result.target.world-surface-y -5.0))
                (string.format
                  "Expected support bounds to control recovery placement (actual_y=%.3f)"
                  element.layout.position.y)))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-recover-ignores-unbound-scene-object []
  (local setup (setup-scene {:scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain (flat-heightfield-record {:id "terrain-a"
                                           :position [0 -100 0]
                                           :height 0.0}))
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain]})
        (local object
          (make-unbound-test-object {:name "unbound-object"}))
        (local element
          (scene:add-object object
                            {:position (glm.vec3 30 -260 30)}))
        (assert element "Expected unbound test object")
        (local entries (SceneTerrainRecovery.collect-entries scene))
        (assert (= (length entries) 0)
                "Objects without explicit terrain binding should not be recovery candidates")
        (local before-y element.layout.position.y)
        (local results (SceneTerrainRecovery.recover scene))
        (assert (= (length results) 0)
                "Recovery should skip objects without explicit terrain binding")
        (assert (= element.layout.position.y before-y)
                "Unbound object position should remain unchanged"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-recover-terrain-bound-physics-cuboid-repositions-body []
  (assert bt "Terrain-bound cuboid recovery test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain (flat-heightfield-record {:id "terrain-a"
                                           :position [0 -100 0]
                                           :height 0.0}))
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain]})
        (local element
          (scene:add-physics-body {:position (glm.vec3 30 -240 30)
                                   :size (glm.vec3 4 4 4)}))
        (assert element "Expected add-physics-body to return an element")
        (local results (SceneTerrainRecovery.recover scene))
        (assert (= (length results) 1) "Expected one recovery result")
        (assert (= (. (. results 1) :mode) :vertical)
                "Physics cuboid below terrain should recover in place")
        (scene:update)
        (local center (+ element.layout.position
                         (element.layout.rotation:rotate (* 0.5 element.layout.size))))
        (assert (approx element.layout.position.y -100.0)
                (string.format
                  "Expected cuboid origin to rest on terrain (actual_y=%.3f)"
                  element.layout.position.y))
        (assert (> center.y -99.0)
                (string.format
                  "Expected cuboid body center above terrain after recovery (center_y=%.3f)"
                  center.y)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-recover-nearest-terrain-respects-scene-root-transform []
  (local setup (setup-scene {:scene-position (glm.vec3 50 0 20)
                             :scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain (flat-heightfield-record {:id "terrain-a"
                                           :position [0 -100 0]
                                           :height 0.0}))
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain]})
        (local object
          (make-terrain-bound-test-object {:name "root-transform-nearest-object"}))
        (local element
          (scene:add-object object
                            {:position (glm.vec3 200 -260 120)}))
        (assert element "Expected terrain-bound test object")
        (local results (SceneTerrainRecovery.recover scene))
        (assert (= (length results) 1) "Expected one recovery result")
        (assert (= (. (. results 1) :mode) :nearest)
                "Object outside all terrain domains should snap to nearest terrain")
        (assert (approx element.layout.position.x 130.0)
                (string.format
                  "Expected nearest terrain x to respect scene root transform (actual_x=%.3f)"
                  element.layout.position.x))
        (assert (approx element.layout.position.z 100.0)
                (string.format
                  "Expected nearest terrain z to respect scene root transform (actual_z=%.3f)"
                  element.layout.position.z))
        (assert (approx element.layout.position.y -100.0)
                (string.format
                  "Expected recovered y to match transformed terrain surface (actual_y=%.3f)"
                  element.layout.position.y)))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-build-default-preserves-explicit-empty-terrains []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains []})
        (local captured (scene:capture-state))
        (local terrains (or captured.terrains []))
        (assert (= (length terrains) 0)
                "Explicit empty terrains should remain empty when building scene defaults"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-domain-hit-respects-scene-root-transform []
  (local setup (setup-scene {:scene-position (glm.vec3 -5 0 0)
                             :scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 -3 10 2)
                                (glm.vec3 -3 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (scene.layout-root:update)
        (local hit (scene:screen-pos-terrain-domain-hit {:x 50 :y 50}
                                                        {:view view
                                                         :projection projection
                                                         :viewport viewport}))
        (assert hit "screen-pos terrain domain hit should resolve a translated scene-root terrain")
        (assert (= hit.terrain-id "terrain-a")
                "screen-pos terrain domain hit should report terrain id through scene-root transform")
        (assert (= hit.sample.x 2)
                "screen-pos terrain domain hit should preserve sample x under scene-root translation")
        (assert (= hit.sample.z 2)
                "screen-pos terrain domain hit should preserve sample z under scene-root translation"))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-hit-resolves-default-heightfield []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local hit (scene:screen-pos-terrain-hit {:x 50 :y 50}
                                                 {:view view
                                                  :projection projection
                                                  :viewport viewport}))
        (assert hit "screen-pos terrain hit should resolve a heightfield terrain")
        (assert (= hit.terrain-id "terrain-a") "screen-pos terrain hit should report terrain id")
        (assert (= hit.target.mode :samples) "screen-pos terrain hit should return a single-sample target")
        (assert (= hit.target.shape :rect) "screen-pos terrain hit should use the compact rectangular sample target")
        (assert (= hit.sample.x 2) "screen-pos terrain hit should resolve the nearest sample x")
        (assert (= hit.sample.z 2) "screen-pos terrain hit should resolve the nearest sample z"))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-rect-terrain-target-builds-sample-set []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local target-result
          (scene:screen-rect-terrain-target "terrain-a"
                                            {:x 40 :y 50}
                                            {:x 60 :y 50}
                                            {:view view
                                             :projection projection
                                             :viewport viewport}))
        (assert target-result "screen rect terrain target should resolve a sample target")
        (assert (= target-result.terrain-id "terrain-a") "screen rect target should report terrain id")
        (assert (= target-result.target.mode :samples) "screen rect target should resolve picked samples")
        (assert (= target-result.target.sample-count 3) "thin horizontal drag should select three samples")
        (assert (= target-result.target.x0 1) "screen rect target should normalize the smaller sample x")
        (assert (= target-result.target.x1 3) "screen rect target should normalize the larger sample x")
        (assert (= target-result.target.z0 2) "screen rect target should keep the selected z band for a thin horizontal drag")
        (assert (= target-result.target.z1 2) "screen rect target should keep the selected z band for a thin horizontal drag"))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-rect-terrain-target-respects-scene-root-transform []
  (local setup (setup-scene {:scene-position (glm.vec3 -5 0 0)
                             :scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 -3 10 2)
                                (glm.vec3 -3 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (scene.layout-root:update)
        (local target-result
          (scene:screen-rect-terrain-target "terrain-a"
                                            {:x 40 :y 50}
                                            {:x 60 :y 50}
                                            {:view view
                                             :projection projection
                                             :viewport viewport}))
        (assert target-result
                "screen rect terrain target should resolve through scene-root transformed terrain")
        (assert (= target-result.terrain-id "terrain-a"))
        (assert (= target-result.target.mode :samples))
        (assert (= target-result.target.sample-count 3))
        (assert (= target-result.target.x0 1))
        (assert (= target-result.target.x1 3))
        (assert (= target-result.target.z0 2))
        (assert (= target-result.target.z1 2)))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-domain-hit-scales-logical-input-to-pixel-viewport []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-engine-width (and app.engine app.engine.width))
  (local original-engine-height (and app.engine app.engine.height))
  (local original-engine-pixel-width (and app.engine (. app.engine "pixel-width")))
  (local original-engine-pixel-height (and app.engine (. app.engine "pixel-height")))
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (when app.engine
          (set app.engine.width 50)
          (set app.engine.height 50)
          (set (. app.engine "pixel-width") 100)
          (set (. app.engine "pixel-height") 100))
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local hit (scene:screen-pos-terrain-domain-hit {:x 20 :y 25}
                                                        {:view view
                                                         :projection projection
                                                         :viewport viewport}))
        (assert hit "scaled logical input should still hit the terrain")
        (assert (= hit.terrain-id "terrain-a") "scaled logical input should preserve terrain id")
        (assert (= hit.sample.x 1) "scaled logical input should map x through logical->pixel scaling")
        (assert (= hit.sample.z 2) "scaled logical input should map y through logical->pixel scaling"))))
  (when app.engine
    (set app.engine.width original-engine-width)
    (set app.engine.height original-engine-height)
    (set (. app.engine "pixel-width") original-engine-pixel-width)
    (set (. app.engine "pixel-height") original-engine-pixel-height))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn target-approx=? [left right]
  (if (or (not left) (not right))
      (= left right)
      (and (= left.mode right.mode)
           (= left.x0 right.x0)
           (= left.z0 right.z0)
           (= left.x1 right.x1)
           (= left.z1 right.z1))))

(fn resolve-target-capture-drag [scene terrain-id start-pos move-pos end-pos]
  (var resolved nil)
  (local capture
    (HeightfieldTargetCapture {:scene scene
                               :terrain-id terrain-id
                               :on-target (fn [target _result]
                                            (set resolved target))}))
  (capture:begin)
  (capture:begin-drag start-pos)
  (capture:update-drag move-pos)
  (capture:end-drag end-pos)
  (capture:drop)
  resolved)

(fn heightfield-target-capture-resolves-live-scene-drag []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:end-drag {:x 60 :y 50})
        (assert resolved-target "target capture should resolve a terrain rectangle after drag")
        (assert (= resolved-target.x0 1) "target capture should resolve the smaller sample x")
        (assert (= resolved-target.x1 3) "target capture should resolve the larger sample x")
        (assert (= resolved-target.z0 2) "target capture should resolve z bounds")
        (assert (= resolved-target.z1 2) "target capture should keep horizontal z bounds")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-escape-cancels-selection []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:on-key-down {:key 27})
        (assert (= resolved-target nil)
                "target capture should not resolve a rectangle when cancelled with escape")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-requires-both-drag-endpoints-on-terrain []
  (local camera (Camera))
  (camera:set-position (glm.vec3 2 10 2))
  (camera:look-at (glm.vec3 2 0 2))
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)
                             :camera camera}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 95 :y 5})
        (capture:update-drag {:x 40 :y 50})
        (capture:end-drag {:x 60 :y 50})
        (assert (= resolved-target nil)
                "target capture should not resolve a rectangle when either drag endpoint misses the terrain")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-uses-last-drag-position-on-release []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:end-drag {:x 95 :y 5})
        (assert resolved-target
                "target capture should commit the last dragged terrain position rather than the raw mouse-up coordinates")
        (assert (= resolved-target.x0 1))
        (assert (= resolved-target.x1 3))
        (assert (= resolved-target.z0 2))
        (assert (= resolved-target.z1 2))
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-clears-selection-when-drag-leaves-terrain []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var selection-target false)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target-updated (fn [target _result]
                                                          (set selection-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (assert selection-target
                "target capture should emit a selection target while the drag still resolves on terrain")
        (capture:update-drag {:x 95 :y 5})
        (assert (= selection-target nil)
                "target capture should clear the selection target as soon as the drag leaves the terrain")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-resolves-live-scene-drag-with-default-ray-opts []
  (local camera (Camera))
  (camera:set-position (glm.vec3 2 10 2))
  (camera:look-at (glm.vec3 2 0 2))
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)
                             :camera camera}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local expected
          (scene:screen-rect-terrain-target "terrain-a"
                                            {:x 40 :y 50}
                                            {:x 60 :y 50}
                                            nil))
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:end-drag {:x 60 :y 50})
        (assert resolved-target
                "default scene ray options should be enough for live terrain picking")
        (assert expected
                "default-ray-opts fixture should derive an expected terrain target from the screen rect seam")
        (assert (= resolved-target.x0 expected.target.x0))
        (assert (= resolved-target.z0 expected.target.z0))
        (assert (= resolved-target.x1 expected.target.x1))
        (assert (= resolved-target.z1 expected.target.z1))
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-paint-capture-stamps-live-scene-samples []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-clickables app.clickables)
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-fpc app.first-person-controls)
  (local original-states app.states)
  (var suspended-state nil)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local stamped-batches [])
        (local capture
          (HeightfieldPaintCapture {:scene scene
                                    :terrain-id "terrain-a"
                                    :ray-opts {:view view
                                               :projection projection
                                               :viewport viewport}
                                    :on-stamp-batch (fn [targets _hit]
                                                      (table.insert stamped-batches targets))}))
        (local states (States))
        (states.add-state :normal {})
        (states.add-state :terrain-paint (TerrainPaintState))
        (states.set-state :normal)
        (set suspended-state (TestSupport.suspend-active-state original-states))
        (set app.states states)
        (set app.clickables {:on-mouse-button-down (fn [_self _payload] nil)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :active? false})
        (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                           :on-mouse-button-up (fn [_self _payload] nil)
                           :on-mouse-motion (fn [_self _payload] nil)
                           :drag-active? (fn [_self] false)})
        (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :on-mouse-motion (fn [_self _payload] nil)
                             :drag-active? (fn [_self] false)})
        (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                        :on-mouse-button-up (fn [_self _payload] nil)
                                        :on-mouse-motion (fn [_self _payload] nil)
                                        :on-mouse-wheel (fn [_self _payload] nil)
                                        :update (fn [_self _delta] nil)
                                        :drag-active? (fn [_self] false)})
        (TerrainPaintManager.begin capture)
        (app.engine.events.mouse-button-down.emit {:button 1 :x 40 :y 50})
        (app.engine.events.mouse-motion.emit {:x 60 :y 50})
        (app.engine.events.updated.emit 0.016)
        (app.engine.events.mouse-button-up.emit {:button 1 :x 60 :y 50})
        (assert (= (length stamped-batches) 2)
                "paint capture should emit continuous stroke batches")
        (assert (= (length (. stamped-batches 1)) 1)
                "paint capture should emit the first hovered sample immediately")
        (assert (= (. (. (. stamped-batches 1) 1) :x0) 1)
                "paint capture should stamp the first sample under the cursor")
        (assert (= (length (. stamped-batches 2)) 2)
                "paint capture should batch the newly crossed samples on motion")
        (assert (= (. (. (. stamped-batches 2) 1) :x0) 2)
                "paint capture should include intermediate samples along the stroke")
        (assert (= (. (. (. stamped-batches 2) 2) :x0) 3)
                "paint capture should include the moved-to sample under the cursor")
        (assert (= (states.active-name) :normal)
                "paint capture should restore the previous state after completion")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls original-fpc)
  (set app.states original-states)
  (TestSupport.resume-active-state suspended-state)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-paint-capture-does-not-raycast-before-stroke []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-clickables app.clickables)
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-fpc app.first-person-controls)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-screen-pos-terrain-domain-hit scene.screen-pos-terrain-domain-hit)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var hit-count 0)
        (set scene.screen-pos-terrain-domain-hit
             (fn [self pos ray-opts]
               (set hit-count (+ hit-count 1))
               (original-screen-pos-terrain-domain-hit self pos ray-opts)))
        (local capture
          (HeightfieldPaintCapture {:scene scene
                                    :terrain-id "terrain-a"
                                    :ray-opts {:view view
                                               :projection projection
                                               :viewport viewport}}))
        (local states (States))
        (states.add-state :normal {})
        (states.add-state :terrain-paint (TerrainPaintState))
        (states.set-state :normal)
        (set suspended-state (TestSupport.suspend-active-state original-states))
        (set app.states states)
        (set app.clickables {:on-mouse-button-down (fn [_self _payload] nil)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :active? false})
        (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                           :on-mouse-button-up (fn [_self _payload] nil)
                           :on-mouse-motion (fn [_self _payload] nil)
                           :drag-active? (fn [_self] false)})
        (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :on-mouse-motion (fn [_self _payload] nil)
                             :drag-active? (fn [_self] false)})
        (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                        :on-mouse-button-up (fn [_self _payload] nil)
                                        :on-mouse-motion (fn [_self _payload] nil)
                                        :on-mouse-wheel (fn [_self _payload]
                                                          (error "terrain rectangle pick state should swallow mouse wheel input"))
                                        :update (fn [_self _delta] nil)
                                        :drag-active? (fn [_self] false)})
        (TerrainPaintManager.begin capture)
        (app.engine.events.mouse-motion.emit {:x 60 :y 50})
        (assert (= hit-count 0)
                "paint capture should not raycast terrain before a stroke has started")
        (app.engine.events.mouse-button-down.emit {:button 1 :x 40 :y 50})
        (assert (= hit-count 1)
                "paint capture should raycast once when the stroke starts on mouse down")
        (capture:drop))))
  (set scene.screen-pos-terrain-domain-hit original-screen-pos-terrain-domain-hit)
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls original-fpc)
  (set app.states original-states)
  (TestSupport.resume-active-state suspended-state)
  (cleanup)
  (when (not ok)
    (error err)))

(fn terrain-rect-pick-state-routes-engine-events []
  (local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-clickables app.clickables)
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-fpc app.first-person-controls)
  (local original-states app.states)
  (var suspended-state nil)
  (var forwarded-wheel nil)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (set app.clickables {:on-mouse-button-down (fn [_self _payload] nil)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :active? true})
        (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                           :on-mouse-button-up (fn [_self _payload] nil)
                           :on-mouse-motion (fn [_self _payload] nil)
                           :drag-active? (fn [_self] false)})
        (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :on-mouse-motion (fn [_self _payload] nil)
                             :drag-active? (fn [_self] false)})
        (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                        :on-mouse-button-up (fn [_self _payload] nil)
                                        :on-mouse-motion (fn [_self _payload] nil)
                                        :on-mouse-wheel (fn [_self payload]
                                                          (set forwarded-wheel payload.y))
                                        :update (fn [_self _delta] nil)
                                        :drag-active? (fn [_self] false)})
        (local states (States))
        (states.add-state :normal {})
        (states.add-state :terrain-rect-pick (TerrainRectPickState))
        (states.set-state :normal)
        (set suspended-state (TestSupport.suspend-active-state original-states))
        (set app.states states)
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (TerrainRectPickManager.begin capture)
        (assert (= (app.states.active-name) :terrain-rect-pick)
                "terrain rectangle picking should enter an explicit app state")
        (local active-state (app.states:active-state))
        (active-state:on-mouse-wheel {:x 0 :y 1})
        (assert (= forwarded-wheel 1)
                "terrain rectangle pick state should forward mouse wheel input to camera controls")
        (app.engine.events.mouse-button-down.emit {:button 1 :x 40 :y 50})
        (app.engine.events.mouse-motion.emit {:x 60 :y 50})
        (app.engine.events.mouse-button-up.emit {:button 1 :x 60 :y 50})
        (assert resolved-target
                "terrain rectangle pick state should route engine mouse events to the active session")
        (assert (= resolved-target.x0 1))
        (assert (= resolved-target.x1 3))
        (assert (= (app.states.active-name) :normal)
                "terrain rectangle pick state should restore the previous state after completion")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls original-fpc)
  (set app.states original-states)
  (TestSupport.resume-active-state suspended-state)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-terrain-selection-persists-across-runtime-replace []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-themes app.themes)
  (set app.themes
       {:get-active-theme (fn []
                            {:terrain-selection {:fill (glm.vec4 0.2 0.5 0.9 0.2)
                                                 :border (glm.vec4 0.2 0.5 0.9 0.95)}})})
  (local (ok err)
    (pcall
      (fn []
        (local terrain-record
          {:id "terrain-a"
           :kind "heightfield-terrain"
           :options {:position [0 0 0]
                     :rotation [1 0 0 0]
                     :sample-spacing [2 2]
                     :chunk-samples [5 5]
                     :default-height 0.0}
           :chunks [{:coord [0 0]
                     :size [5 5]
                     :heights [0 0 0 0 0
                               0 0 0 0 0
                               0 0 0 0 0
                               0 0 0 0 0
                               0 0 0 0 0]}]})
        (local updated-record
          {:id "terrain-a"
           :kind "heightfield-terrain"
           :options {:position [0 0 0]
                     :rotation [1 0 0 0]
                     :sample-spacing [2 2]
                     :chunk-samples [5 5]
                     :default-height 1.0}
           :chunks [{:coord [0 0]
                     :size [5 5]
                     :heights [1 1 1 1 1
                               1 1 1 1 1
                               1 1 1 1 1
                               1 1 1 1 1
                               1 1 1 1 1]}]})
        (scene:build-default {:terrains [terrain-record]})
        (scene:set-terrain-selection-target "terrain-a" {:mode :rect
                                                         :x0 1
                                                         :z0 1
                                                         :x1 3
                                                         :z1 3})
        (local before (scene:get-terrain-selection-target "terrain-a"))
        (assert before "scene should expose terrain selection after it is set")
        (scene:replace-terrain-record "terrain-a" updated-record)
        (local after (scene:get-terrain-selection-target "terrain-a"))
        (assert after "terrain selection should persist after runtime terrain replacement")
        (assert (= after.x0 1))
        (assert (= after.z0 1))
        (assert (= after.x1 3))
        (assert (= after.z1 3)))))
  (set app.themes original-themes)
  (cleanup)
  (when (not ok)
    (error err)))

(fn demo-entry-capture-state-persists-entry-persistence []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (local browser (scene:add-demo-browser))
        (local entry (DemoDialogs.find-entry :welcome-dialog))
        (assert entry "Expected Welcome Dialog demo entry")
        (local demo-element (scene:add-demo-entry entry))
        (local captured (scene:capture-state))
        (local panels (or captured.panels []))
        (assert (= (length panels) 2)
                "Expected demo browser + demo entry to be persisted")
        (var found-demo-entry false)
        (each [_ panel (ipairs panels)]
          (when (= panel.kind "demo-entry-welcome-dialog")
            (set found-demo-entry true)
            (assert (= panel.restorer-module "demo-dialogs")
                    "Demo entry should restore through demo-dialogs module")
            (assert (= panel.entry-key "welcome-dialog")
                    "Demo entry should persist its key for restore")))
        (assert found-demo-entry
                "Captured scene state should include welcome-dialog entry persistence")
        (scene:remove-panel-child browser)
        (scene:remove-panel-child demo-element)
        (assert (= (length scene.scene-children) 0)
                "Scene should be empty before restore")
        (scene:restore-state captured)
        (assert (= (length scene.scene-children) 2)
                "Scene.restore-state should recreate both browser and demo entry"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-capture-state-requires-panel-persistence []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (scene:add-panel-child {:builder (fn [_ctx]
                                           {:layout (Layout {:name "scene-missing-persistence"
                                                             :measurer (fn [self]
                                                                         (set self.measure (glm.vec3 1 1 1)))
                                                             :layouter (fn [self]
                                                                         (set self.size self.measure))})
                                            :drop (fn [_self])})})
        (scene:capture-state))))
  (cleanup)
  (assert (not ok) "Scene.capture-state should fail when panel persistence is missing")
  (assert (string.find (tostring err) "without persistence")
          "Scene.capture-state should report missing persistence")
  true)

(fn scene-capture-state-requires-restore-strategy []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (scene:add-panel-child {:builder (fn [_ctx]
                                           {:layout (Layout {:name "scene-missing-restore"
                                                             :measurer (fn [self]
                                                                         (set self.measure (glm.vec3 1 1 1)))
                                                             :layouter (fn [self]
                                                                         (set self.size self.measure))})
                                            :drop (fn [_self])})
                               :persistence {:kind "scene-missing-restore"}})
        (scene:capture-state))))
  (cleanup)
  (assert (not ok) "Scene.capture-state should fail when restore strategy is missing")
  (assert (string.find (tostring err) "no restore strategy")
          "Scene.capture-state should report missing restore strategy")
  true)

(fn added-dialog-appears-in-front-of-camera []
  (local camera (Camera {:position (glm.vec3 2 3 4)}))
  (camera:yaw (math.rad 45))
  (local setup (setup-scene {:camera camera}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (fn probe-builder [_ctx]
    (local layout
      (Layout {:name "position-probe"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 1 1 1)))
               :layouter (fn [self]
                           (set self.size self.measure))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))})

  (let [(ok err)
        (pcall
          (fn []
            (scene:add-panel-child {:builder probe-builder})
            (assert (= (length scene.scene-children) 1)
                    "Scene should contain the positioned probe")
            (local positioned-metadata (. scene.scene-children 1))
            (local wrapper positioned-metadata.element)
            (local layout wrapper.layout)
            (local expected-position
              (+ camera.position (* (camera:get-forward) (glm.vec3 100))))
            (local half-size (* 0.5 layout.size))
            (local center (+ layout.position (layout.rotation:rotate half-size)))
            (assert (vec3-approx= center expected-position)
                    "Positioned probe center should be placed in front of the camera")
            (local cam-forward (camera:get-forward))
            (local projected (glm.vec3 cam-forward.x 0 cam-forward.z))
            (local facing
              (if (> (glm.length projected) 1e-4)
                  (glm.normalize (* projected (glm.vec3 -1)))
                  (glm.vec3 0 0 1)))
            (local expected-forward (* facing (glm.vec3 -1)))
            (local actual-forward (layout.rotation:rotate (glm.vec3 0 0 -1)))
            (when (not (vec3-approx= actual-forward expected-forward))
              (error (string.format
                       "Positioned probe should face the camera (actual=%.4f,%.4f,%.4f expected=%.4f,%.4f,%.4f)"
                       actual-forward.x actual-forward.y actual-forward.z
                       expected-forward.x expected-forward.y expected-forward.z)))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-add-physics-body-falls []
  (assert bt "Physics body test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local element (scene:add-physics-body {:position (glm.vec3 0 20 0)
                                                      :size (glm.vec3 4 4 4)}))
            (assert element "Expected add-physics-body to return an element")
            (assert scene.entity.physics-bodies "Scene should track runtime physics bodies")
            (local entry (. scene.entity.physics-bodies (length scene.entity.physics-bodies)))
            (assert (and entry entry.body) "Runtime physics body should create a rigid body")
            (local start-y element.layout.position.y)

            (for [i 1 120]
              (app.engine.physics:update 0)
              (scene:update))

            (local end-y element.layout.position.y)
            (local transform (entry.body:getCenterOfMassTransform))
            (local origin (transform:getOrigin))
            (assert (< end-y (- start-y 5))
                    (string.format
                      "Physics body should fall (start_y=%.3f end_y=%.3f body_center_y=%.3f)"
                      start-y
                      end-y
                      origin.y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-add-ball-appears-in-front-of-camera-and-restores []
  (local camera (Camera {:position (glm.vec3 2 3 4)}))
  (camera:yaw (math.rad 45))
  (local setup (setup-scene {:camera camera}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local element (scene:add-object
                             (Ball {:size (glm.vec3 18 18 18)
                                    :radius 7
                                    :mass 2.5
                                    :friction 0.25
                                    :restitution 0.75
                                    :initial-velocity (glm.vec3 1 2 3)})))
            (assert element "Expected add-ball to return an element")
            (assert (= (length (runtime-balls scene)) 1)
                    "Scene should track runtime balls")
            (local layout element.layout)
            (local expected-center
              (+ camera.position (* (camera:get-forward) (glm.vec3 100))))
            (local half-size (* 0.5 layout.size))
            (local center (+ layout.position (layout.rotation:rotate half-size)))
            (assert (vec3-approx= center expected-center)
                    "Ball center should be placed 100 units in front of the camera")
            (assert (approx layout.rotation.w camera.rotation.w)
                    "Ball should inherit camera-derived default rotation when spawned")
            (assert (approx layout.rotation.y camera.rotation.y)
                    "Ball should inherit camera-derived default rotation around Y when spawned")

            (local captured (scene:capture-state))
            (local panels (or captured.panels []))
            (assert (= (length panels) 1)
                    "Expected one persisted scene panel for ball")
            (local panel (. panels 1))
            (assert (= panel.kind "physics-ball")
                    "Ball persistence kind should be physics-ball")
            (assert (= panel.radius 7) "Ball persistence should preserve radius")
            (assert (= panel.mass 2.5) "Ball persistence should preserve mass")
            (assert (= panel.friction 0.25) "Ball persistence should preserve friction")
            (assert (= panel.restitution 0.75) "Ball persistence should preserve restitution")
            (assert (vec3-approx= (array->vec3 panel.initial-velocity) (glm.vec3 1 2 3))
                    "Ball persistence should preserve initial velocity")

            (scene:remove-panel-child element)
            (assert (= (length (runtime-balls scene)) 0)
                    "Removing ball should clear runtime ball tracking")

            (scene:restore-state captured)
            (assert (= (length (runtime-balls scene)) 1)
                    "Scene restore should recreate persisted ball")
            (local restored (. (runtime-balls scene) 1))
            (assert (= restored.radius 7) "Ball restore should preserve radius")
            (assert (= restored.mass 2.5) "Ball restore should preserve mass")
            (assert (= restored.friction 0.25) "Ball restore should preserve friction")
            (assert (= restored.restitution 0.75) "Ball restore should preserve restitution")
            (assert (vec3-approx= restored.initial-velocity (glm.vec3 1 2 3))
                    "Ball restore should preserve initial velocity")
            (assert (approx restored.layout.rotation.w camera.rotation.w)
                    "Ball restore should preserve default spawn rotation")))]
    (cleanup)
  (when (not ok)
    (error err))))

(fn scene-ball-context-menu-removes-ball []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-clickables app.clickables)
  (local original-menu-manager app.menu-manager)

  (let [(ok err)
        (pcall
          (fn []
            (local clickables (make-clickables-menu-stub))
            (var opened nil)
            (set app.clickables clickables)
            (set app.menu-manager {:open (fn [_self opts]
                                           (set opened opts))})

            (local element (scene:add-object (Ball {:size (glm.vec3 18 18 18)
                                                    :radius 7})))
            (assert element "Expected add-ball to return an element")
            (assert (= (length (runtime-balls scene)) 1)
                    "Scene should track runtime balls before context-menu removal")
            (assert (= (length clickables.state.registered-right-click) 1)
                    "Ball should register one right-click target when added to the scene")

            (local target (. clickables.state.registered-right-click 1))
            (assert target.on-right-click
                    "Ball context-menu target should expose an on-right-click handler")
            (target:on-right-click {:point (glm.vec3 3 4 0)})

            (assert opened "Ball right click should open a menu")
            (assert (= opened.position.x 3) "Ball context menu should open at the click point")
            (assert (= opened.position.y 4) "Ball context menu should open at the click point")
            (assert (= (length opened.actions) 1)
                    "Ball context menu should currently expose one action")
            (assert (= (. opened.actions 1 :name) "Remove")
                    "Ball context menu should expose a Remove action")

            ((. opened.actions 1 :fn) nil {})

            (assert (= (length (runtime-balls scene)) 0)
                    "Ball remove action should remove the runtime ball from the scene")
            (assert (= (length clickables.state.unregistered-right-click) 1)
                    "Removing a ball should unregister its right-click target")
            (assert (= (. clickables.state.unregistered-right-click 1) target)
                    "Ball should unregister the same right-click target it registered")))]
    (set app.clickables original-clickables)
    (set app.menu-manager original-menu-manager)
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-ball-settles-on-configured-containment-floor []
  (assert bt "Scene ball configured containment floor test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -100))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (local (ok err)
    (pcall
      (fn []
        (local element (scene:add-object
                         (Ball {:size (glm.vec3 18 18 18)})
                         {:position (glm.vec3 0 40 0)}))
        (assert element "Expected add-ball to return an element")
        (for [_ 1 1500]
          (app.engine.physics:update 0)
          (scene:update))
        (local center (+ element.layout.position
                         (element.layout.rotation:rotate (* 0.5 element.layout.size))))
        (assert (> center.y -100)
                (string.format
                  "Ball should not fall through configured containment floor at y=-100 (center_y=%.3f)"
                  center.y))
        (assert (< center.y -70)
                (string.format
                  "Ball should settle near configured containment floor, not remain high (center_y=%.3f)"
                  center.y)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-physics-body-collides-with-flat-terrain []
  (assert bt "Physics body terrain test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local element (scene:add-physics-body {:position (glm.vec3 0 -70 0)
                                                      :size (glm.vec3 4 4 4)}))
            (assert element "Expected add-physics-body to return an element")

            (for [i 1 360]
              (app.engine.physics:update 0)
              (scene:update))

            (local y element.layout.position.y)
            (assert (< (math.abs (+ y 100)) 6)
                    (string.format
                      "Physics body should settle near flat terrain y=-100 (actual_y=%.3f)"
                      y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-heightfield-physics-respects-scene-root-transform []
  (assert bt "Scene heightfield root-transform physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain-record
    {:id "terrain-a"
     :kind "heightfield-terrain"
     :options {:position [0 -100 0]
               :rotation [1 0 0 0]
               :sample-spacing [20 20]
               :chunk-samples [5 5]
               :default-height 20.0}
     :chunks [{:coord [0 0]
               :size [5 5]
               :heights [20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20]}]})

  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain-record]})
        (scene.layout-root:update)
        (local terrain-entry (. scene.scene-terrains 1))
        (local terrain-layout (and terrain-entry terrain-entry.element terrain-entry.element.layout))
        (assert terrain-layout "Expected runtime terrain layout for root-transform physics test")
        (local local-center (glm.vec3 40 0 40))
        (local world-center (+ terrain-layout.position
                               (terrain-layout.rotation:rotate local-center)))
        (local surface (scene:terrain-surface-under-point world-center))
        (assert surface "Expected terrain surface under transformed terrain center")
        (local body
          (scene:add-physics-body {:position (glm.vec3 (- world-center.x 2)
                                                       (+ surface.world-surface-y 40)
                                                       (- world-center.z 2))
                                   :size (glm.vec3 4 4 4)}))
        (assert body "Expected add-physics-body to create a runtime body")
        (for [_ 1 360]
          (app.engine.physics:update 0)
          (scene:update))
        (local center (+ body.layout.position
                         (body.layout.rotation:rotate (* 0.5 body.layout.size))))
        (assert (> center.y (+ surface.world-surface-y 1.0))
                (string.format
                  "Physics body should rest above the transformed heightfield surface instead of falling through (surface_y=%.3f center_y=%.3f)"
                  surface.world-surface-y
                  center.y)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-replaced-heightfield-updates-physics []
  (assert bt "Terrain replacement physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain-record
    {:id "terrain-a"
     :kind "heightfield-terrain"
     :options {:position [0 -100 0]
               :rotation [1 0 0 0]
               :sample-spacing [20 20]
               :chunk-samples [5 5]
               :default-height 0.0}
     :chunks [{:coord [0 0]
               :size [5 5]
               :heights [0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0]}]})
  (local updated-record
    {:id "terrain-a"
     :kind "heightfield-terrain"
     :options {:position [0 -100 0]
               :rotation [1 0 0 0]
               :sample-spacing [20 20]
               :chunk-samples [5 5]
               :default-height 20.0}
     :chunks [{:coord [0 0]
               :size [5 5]
               :heights [20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20]}]})

  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain-record]})
        (scene:replace-terrain-record "terrain-a" updated-record)
        (local element
          (scene:add-physics-body {:position (glm.vec3 40 -40 40)
                                   :size (glm.vec3 4 4 4)}))
        (assert element "Expected add-physics-body to return an element")
        (for [_ 1 360]
          (app.engine.physics:update 0)
          (scene:update))
        (local y element.layout.position.y)
        (assert (> y -90)
                (string.format
                  "Physics body should settle on replaced raised terrain, not the old base (actual_y=%.3f)"
                  y)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-replaced-heightfield-updates-lifted-ball-collision []
  (assert bt "Terrain replacement lifted-ball test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain-record
    {:id "terrain-a"
     :kind "heightfield-terrain"
     :options {:position [0 -100 0]
               :rotation [1 0 0 0]
               :sample-spacing [20 20]
               :chunk-samples [5 5]
               :default-height 0.0}
     :chunks [{:coord [0 0]
               :size [5 5]
               :heights [0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0]}]})
  (local updated-record
    {:id "terrain-a"
     :kind "heightfield-terrain"
     :options {:position [0 -100 0]
               :rotation [1 0 0 0]
               :sample-spacing [20 20]
               :chunk-samples [5 5]
               :default-height 20.0}
     :chunks [{:coord [0 0]
               :size [5 5]
               :heights [20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20]}]})

  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain-record]})
        (local element
          (scene:add-object (Ball {:size (glm.vec3 18 18 18)})
                            {:position (glm.vec3 40 20 40)}))
        (assert element "Expected add-ball to return an element")
        (for [_ 1 360]
          (app.engine.physics:update 0)
          (scene:update))
        (scene:replace-terrain-record "terrain-a" updated-record)
        (element:begin-drag)
        (element.layout:set-position (glm.vec3 0 0 0))
        (element:end-drag)
        (for [_ 1 360]
          (app.engine.physics:update 0)
          (scene:update))
        (local center (+ element.layout.position
                         (element.layout.rotation:rotate (* 0.5 element.layout.size))))
        (assert (> center.y -90)
                (string.format
                  "Lifted ball should rest on replaced raised terrain, not the old base (center_y=%.3f)"
                  center.y)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-replaced-heightfield-allows-direct-drag-placement-on-raised-area []
  (assert bt "Terrain replacement direct-place ball test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local terrain-record
    {:id "terrain-a"
     :kind "heightfield-terrain"
     :options {:position [0 -100 0]
               :rotation [1 0 0 0]
               :sample-spacing [20 20]
               :chunk-samples [5 5]
               :default-height 0.0}
     :chunks [{:coord [0 0]
               :size [5 5]
               :heights [0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0
                         0 0 0 0 0]}]})
  (local updated-record
    {:id "terrain-a"
     :kind "heightfield-terrain"
     :options {:position [0 -100 0]
               :rotation [1 0 0 0]
               :sample-spacing [20 20]
               :chunk-samples [5 5]
               :default-height 20.0}
     :chunks [{:coord [0 0]
               :size [5 5]
               :heights [20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20
                         20 20 20 20 20]}]})

  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain-record]})
        (local element
          (scene:add-object (Ball {:size (glm.vec3 18 18 18)})
                            {:position (glm.vec3 40 20 40)}))
        (assert element "Expected add-ball to return an element")
        (for [_ 1 360]
          (app.engine.physics:update 0)
          (scene:update))
        (scene:replace-terrain-record "terrain-a" updated-record)
        (element:begin-drag)
        (element.layout:set-position (glm.vec3 31 -89 31))
        (local placed-center (+ element.layout.position
                                (element.layout.rotation:rotate (* 0.5 element.layout.size))))
        (assert (> placed-center.y -82)
                (string.format
                  "Direct placement test should place the ball center near the raised surface before release (actual=%.3f)"
                  placed-center.y))
        (assert (< placed-center.y -76)
                (string.format
                  "Direct placement test should place the ball center near the raised surface before release (actual=%.3f)"
                  placed-center.y))
        (element:end-drag)
        (app.engine.physics:update 0)
        (scene:update)
        (local center (+ element.layout.position
                         (element.layout.rotation:rotate (* 0.5 element.layout.size))))
        (assert (= center.y center.y)
                "Direct drag placement release should keep a finite ball center")
        (assert (< (math.abs (- center.y placed-center.y)) 140.0)
                (string.format
                  "Direct drag placement release should stay near the manually placed pose for the first sync step (placed_y=%.3f center_y=%.3f)"
                  placed-center.y
                  center.y)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-live-heightfield-ball-above-raised-area-stays-near-supported-surface []
  (assert bt "Live heightfield ball regression test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local fixture (fixtures.read-json (TestSupport.fixture-path "terrain-live-pick-world.json")))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (local broad-probes (collect-broad-elevated-probes terrain-record 5.0))
  (local local-point
    (or (and (. broad-probes 1) (. (. broad-probes 1) :point))
        (glm.vec3 170 0 190)))
  (local ball-radius 9.0)
  (local ball-size (glm.vec3 (* ball-radius 2) (* ball-radius 2) (* ball-radius 2)))

  (local (ok err)
    (pcall
      (fn []
        (assert terrain-record "Expected live terrain fixture to include a terrain record")
        (scene:build-default {:terrains [terrain-record]})
        (wait-for-terrain-layout-stable scene terrain-record.id)
        (local terrain-entry (. scene.scene-terrains 1))
        (local terrain-layout (and terrain-entry terrain-entry.element terrain-entry.element.layout))
        (assert terrain-layout "Expected runtime terrain layout for live heightfield regression")
        (local world-point
          (terrain-world-point-from-runtime-layout terrain-record terrain-layout local-point))
        (local surface (scene:terrain-surface-under-point world-point))
        (assert surface "Expected terrain surface under transformed live heightfield probe")
        (local ball-center (glm.vec3 world-point.x
                                     (+ surface.world-surface-y 30.0)
                                     world-point.z))
        (local ball-layout-position
          (glm.vec3 (- ball-center.x ball-radius)
                    (- ball-center.y ball-radius)
                    (- ball-center.z ball-radius)))
        (local ball
          (scene:add-object (Ball {:size ball-size
                                   :radius ball-radius})
                            {:position ball-layout-position
                             :rotation (glm.quat 1 0 0 0)}))
        (assert ball "Expected add-ball to create a runtime ball")
        (for [_ 1 360]
          (app.engine.physics:update 0)
          (scene:update))
        (local transform (ball.body:getCenterOfMassTransform))
        (local origin (transform:getOrigin))
        (assert (> origin.y (+ surface.world-surface-y ball-radius -12.0))
                (string.format
                  "Ball should remain near the transformed raised live terrain support surface (surface_y=%.3f center_y=%.3f)"
                  surface.world-surface-y
                  origin.y)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-live-heightfield-supports-balls-across-3x3-chunks []
  (assert bt "Live 3x3 heightfield support test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local fixture (fixtures.read-json (TestSupport.fixture-path "terrain-live-pick-world.json")))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (local ball-radius 9.0)
  (local bounds (HeightfieldTerrainData.sample-bounds terrain-record))
  (local spacing (HeightfieldTerrainGrid.spacing terrain-record))
  (local spacing-x (. spacing 1))
  (local spacing-z (. spacing 2))
  (local min-local-x (+ (* bounds.min-sample-x spacing-x) 37.0))
  (local max-local-x (- (* bounds.max-sample-x spacing-x) 37.0))
  (local min-local-z (+ (* bounds.min-sample-z spacing-z) 37.0))
  (local max-local-z (- (* bounds.max-sample-z spacing-z) 37.0))
  (local local-probe-points [])
  (local broad-probes-by-cell {})
  (each [_ probe (ipairs (collect-broad-elevated-probes terrain-record 5.0))]
    (set (. broad-probes-by-cell (.. probe.sample-x ":" probe.sample-z)) probe))
  (for [probe-z 0 4]
    (local z
      (+ min-local-z
         (* (/ probe-z 4.0)
            (- max-local-z min-local-z))))
    (for [probe-x 0 4]
      (local x
        (+ min-local-x
           (* (/ probe-x 4.0)
              (- max-local-x min-local-x))))
      (local candidate (glm.vec3 x 0 z))
      (local local-surface-y
        (terrain-surface-height-at-local-point terrain-record candidate.x candidate.z))
      (when (and local-surface-y (> local-surface-y 1.0))
        (local cell-x (math.floor (/ candidate.x spacing-x)))
        (local cell-z (math.floor (/ candidate.z spacing-z)))
        (local broad-probe (. broad-probes-by-cell (.. cell-x ":" cell-z)))
        (when broad-probe
          (table.insert local-probe-points broad-probe.point)))))

  (fn assert-supported-at-local-point [local-point]
    (local terrain-entry (. scene.scene-terrains 1))
    (local terrain-layout (and terrain-entry terrain-entry.element terrain-entry.element.layout))
    (assert terrain-layout "Expected runtime terrain layout for 3x3 support probe")
    (local world-point
      (terrain-world-point-from-runtime-layout terrain-record terrain-layout local-point))
    (local local-surface-y
      (terrain-surface-height-at-local-point terrain-record local-point.x local-point.z))
    (assert (not (= local-surface-y nil))
            (string.format
              "Expected terrain surface at local probe (%.3f, %.3f)"
              local-point.x
              local-point.z))
    (local surface (scene:terrain-surface-under-point world-point))
    (assert surface "Expected transformed terrain surface under 3x3 probe")
    (local expected-surface-y surface.world-surface-y)
    (local ball
      (scene:add-object (Ball {:size (glm.vec3 (* ball-radius 2) (* ball-radius 2) (* ball-radius 2))
                               :radius ball-radius})
                        {:position (glm.vec3 (- world-point.x ball-radius)
                                             (+ expected-surface-y 40 (- ball-radius))
                                             (- world-point.z ball-radius))
                         :rotation (glm.quat 1 0 0 0)}))
    (assert ball "Expected add-ball to create a runtime ball for 3x3 terrain probe")
    (for [_ 1 360]
      (app.engine.physics:update 0)
      (scene:update))
    (local transform (ball.body:getCenterOfMassTransform))
    (local origin (transform:getOrigin))
    (assert (> origin.y (+ expected-surface-y ball-radius -12.0))
            (string.format
              "Ball should be supported near the rendered terrain surface at local probe (%.3f, %.3f); expected_surface_y=%.3f center_y=%.3f"
              local-point.x
              local-point.z
              expected-surface-y
              origin.y))
    (scene:remove-panel-child ball))

  (local (ok err)
    (pcall
      (fn []
        (assert terrain-record "Expected live terrain fixture to include a terrain record")
        (scene:build-default {:terrains [terrain-record]})
        (wait-for-terrain-layout-stable scene terrain-record.id)
        (each [_ local-point (ipairs local-probe-points)]
          (assert-supported-at-local-point local-point)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-first-home-world-supports-balls-on-elevated-samples []
  (assert bt "First home world elevated ball support test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local fixture (fixtures.read-json (first-home-world-path)))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (local ball-radius 9.0)
  (local local-probe-points
    (representative-probes (collect-broad-elevated-probes terrain-record 10.0) 4))

  (fn assert-supported-at-local-point [probe]
    (local local-point probe.point)
    (local terrain-entry (. scene.scene-terrains 1))
    (local terrain-layout (and terrain-entry terrain-entry.element terrain-entry.element.layout))
    (assert terrain-layout "Expected runtime terrain layout for first home world elevated probe")
    (local world-point
      (terrain-world-point-from-runtime-layout terrain-record terrain-layout local-point))
    (local local-surface-y
      (terrain-surface-height-at-local-point terrain-record local-point.x local-point.z))
    (assert (not (= local-surface-y nil))
            (string.format
              "Expected first home world terrain surface at local probe (%.3f, %.3f)"
              local-point.x
              local-point.z))
    (local surface (scene:terrain-surface-under-point world-point))
    (assert surface "Expected transformed terrain surface under first home world elevated probe")
    (local expected-surface-y surface.world-surface-y)
    (local ball
      (scene:add-object (Ball {:size (glm.vec3 (* ball-radius 2) (* ball-radius 2) (* ball-radius 2))
                               :radius ball-radius})
                        {:position (glm.vec3 (- world-point.x ball-radius)
                                             (+ expected-surface-y 40 (- ball-radius))
                                             (- world-point.z ball-radius))
                         :rotation (glm.quat 1 0 0 0)}))
    (assert ball "Expected add-ball to create a runtime ball for first home world elevated probe")
    (local initial-center (ball:center-from-layout))
    (for [_ 1 360]
      (app.engine.physics:update 0)
      (scene:update))
    (local transform (ball.body:getCenterOfMassTransform))
    (local origin (transform:getOrigin))
    (assert (> origin.y (+ expected-surface-y ball-radius -12.0))
            (string.format
              "First home world elevated ball support mismatch sample=(%d,%d) min_height=%.3f max_height=%.3f local=(%.3f, %.3f) expected_surface_y=%.3f initial_center=(%.3f, %.3f, %.3f) final_center=(%.3f, %.3f, %.3f)"
              probe.sample-x
              probe.sample-z
              probe.min-height
              probe.max-height
              local-point.x
              local-point.z
              expected-surface-y
              initial-center.x
              initial-center.y
              initial-center.z
              origin.x
              origin.y
              origin.z))
    (scene:remove-panel-child ball))

  (local (ok err)
    (pcall
      (fn []
        (assert terrain-record "Expected first home world to include a terrain record")
        (scene:build-default {:terrains [terrain-record]})
        (wait-for-terrain-layout-stable scene terrain-record.id)
        (each [_ probe (ipairs local-probe-points)]
          (assert-supported-at-local-point probe)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-first-home-world-supports-ball-on-central-plateau []
  (assert bt "First home world plateau ball support test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-containment-config app.physics-containment-config)
  (set app.physics-containment-config (manual-containment-config -1000))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local fixture (fixtures.read-json (first-home-world-path)))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (local ball-radius 9.0)
  (local broad-probes (collect-broad-elevated-probes terrain-record 10.0))
  (local local-point
    (or (and (. broad-probes 1) (. (. broad-probes 1) :point))
        (glm.vec3 170 0 190)))

  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [terrain-record]})
        (wait-for-terrain-layout-stable scene terrain-record.id)
        (local terrain-entry (. scene.scene-terrains 1))
        (local terrain-layout (and terrain-entry terrain-entry.element terrain-entry.element.layout))
        (assert terrain-layout "Expected runtime terrain layout for first home world plateau probe")
        (local world-point
          (terrain-world-point-from-runtime-layout terrain-record terrain-layout local-point))
        (local local-surface-y
          (terrain-surface-height-at-local-point terrain-record local-point.x local-point.z))
        (assert local-surface-y
                "Expected first home world central plateau surface")
        (local surface (scene:terrain-surface-under-point world-point))
        (assert surface "Expected transformed terrain surface under first home world plateau probe")
        (local expected-surface-y surface.world-surface-y)
        (local ball
          (scene:add-object (Ball {:size (glm.vec3 (* ball-radius 2) (* ball-radius 2) (* ball-radius 2))
                                   :radius ball-radius})
                            {:position (glm.vec3 (- world-point.x ball-radius)
                                                 (+ expected-surface-y 40 (- ball-radius))
                                                 (- world-point.z ball-radius))
                             :rotation (glm.quat 1 0 0 0)}))
        (assert ball "Expected add-ball to create a runtime ball for first home world plateau probe")
        (for [_ 1 360]
          (app.engine.physics:update 0)
          (scene:update))
        (local transform (ball.body:getCenterOfMassTransform))
        (local origin (transform:getOrigin))
        (assert (> origin.y (+ expected-surface-y ball-radius -12.0))
                (string.format
                  "First home world plateau support mismatch local=(%.3f, %.3f) expected_surface_y=%.3f final_center=(%.3f, %.3f, %.3f)"
                  local-point.x
                  local-point.z
                  expected-surface-y
                  origin.x
                  origin.y
                  origin.z)))))
  (cleanup)
  (set app.physics-containment-config original-containment-config)
  (when (not ok)
    (error err)))

(fn scene-terrain-surface-query-is-stable-across-updates []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local fixture (fixtures.read-json (first-home-world-path)))
  (local terrain-record (. (or (and fixture.scene fixture.scene.terrains) []) 1))
  (local local-point (glm.vec3 170 0 190))

  (local (ok err)
    (pcall
      (fn []
        (assert terrain-record "Expected first home world to include a terrain record")
        (scene:build-default {:terrains [terrain-record]})
        (wait-for-terrain-layout-stable scene terrain-record.id)
        (local terrain-entry (. scene.scene-terrains 1))
        (local terrain-layout (and terrain-entry terrain-entry.element terrain-entry.element.layout))
        (assert terrain-layout "Expected runtime terrain layout for terrain stability test")
        (local world-point
          (terrain-world-point-from-runtime-layout terrain-record terrain-layout local-point))
        (local initial-info (scene:terrain-surface-under-point world-point))
        (assert initial-info
                "Expected terrain surface query to resolve before updates")
        (for [_ 1 120]
          (app.engine.physics:update 0)
          (scene:update))
        (local final-info (scene:terrain-surface-under-point world-point))
        (assert final-info
                "Expected terrain surface query to resolve after updates")
        (assert (vec3-approx= initial-info.local-point final-info.local-point)
                (string.format
                  "Expected terrain local point to stay stable across updates initial=(%.3f, %.3f, %.3f) final=(%.3f, %.3f, %.3f)"
                  initial-info.local-point.x
                  initial-info.local-point.y
                  initial-info.local-point.z
                  final-info.local-point.x
                  final-info.local-point.y
                  final-info.local-point.z))
        (assert (approx initial-info.world-surface-y final-info.world-surface-y)
                (string.format
                  "Expected terrain surface height to stay stable across updates initial=%.3f final=%.3f"
                  initial-info.world-surface-y
                  final-info.world-surface-y)))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-runtime-body-falls-after-drag-release []
  (assert bt "Physics body drag-release test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local element (scene:add-physics-body {:position (glm.vec3 0 20 0)
                                                      :size (glm.vec3 4 4 4)}))
            (assert element "Expected add-physics-body to return an element")
            (local physics-entry (. scene.entity.physics-bodies (length scene.entity.physics-bodies)))
            (assert physics-entry "Expected runtime physics entry")

            (var movable-entry nil)
            (each [_ entry (ipairs (or scene.entity.movables []))]
              (when (and (not movable-entry)
                         (= entry.key physics-entry))
                (set movable-entry entry)))
            (assert movable-entry "Expected movable entry for runtime physics body")

            (movable-entry.on-drag-start movable-entry)
            (element.layout:set-position (glm.vec3 0 5 0))
            (movable-entry.on-drag-end movable-entry)

            (scene:update)
            (local start-y element.layout.position.y)
            (for [i 1 120]
              (app.engine.physics:update 0)
              (scene:update))
            (local end-y element.layout.position.y)
            (local transform (physics-entry.body:getCenterOfMassTransform))
            (local origin (transform:getOrigin))
            (assert (< end-y (- start-y 2))
                    (string.format
                      "Body should continue falling after drag release (start_y=%.3f end_y=%.3f body_center_y=%.3f body_active=%s dragging=%s)"
                      start-y
                      end-y
                      origin.y
                      (tostring physics-entry.body-active?)
                      (tostring physics-entry.dragging)))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-restore-physics-cuboids-world-switch-drift-check []
  (assert bt "World-switch drift check requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")

  (fn sim [scene steps]
    (for [i 1 steps]
      (app.engine.physics:update 0)
      (scene:update)))

  (fn physics-layout-ys [scene]
    (local ys [])
    (each [_ entry (ipairs (or (and scene.entity scene.entity.physics-bodies) []))]
      (local y (and entry entry.positioned entry.positioned.layout entry.positioned.layout.position.y))
      (when y
        (table.insert ys y)))
    ys)

  (fn max-abs-drift [start-ys end-ys]
    (var drift 0.0)
    (var idx 1)
    (while (<= idx (math.min (length start-ys) (length end-ys)))
      (local delta (math.abs (- (. end-ys idx) (. start-ys idx))))
      (when (> delta drift)
        (set drift delta))
      (set idx (+ idx 1)))
    drift)

  (local setup0 (setup-scene))
  (local cleanup0 setup0.cleanup)
  (local scene0 setup0.scene-result.scene)
  (local (ok0 payload0)
    (pcall
      (fn []
        (scene0:add-physics-body {:position (glm.vec3 -6 0 0)
                                  :size (glm.vec3 4 4 4)})
        (scene0:add-physics-body {:position (glm.vec3 6 0 0)
                                  :size (glm.vec3 4 4 4)})
        (sim scene0 720)
        (scene0:capture-state))))
  (cleanup0)
  (when (not ok0)
    (error payload0))
  (local captured payload0)
  (var current-captured captured)

  (var worst-drift 0.0)
  (for [cycle 1 3]
    (local setup (setup-scene))
    (local cleanup setup.cleanup)
    (local scene setup.scene-result.scene)
    (local (ok payload)
      (pcall
        (fn []
          (scene:build-default {:terrains current-captured.terrains})
          (scene:restore-state current-captured)
          (local start-ys (physics-layout-ys scene))
          (assert (= (length start-ys) 2)
                  (string.format "Expected 2 restored physics cuboids, got %d" (length start-ys)))
          (sim scene 120)
          (local end-ys (physics-layout-ys scene))
          (local drift (max-abs-drift start-ys end-ys))
          (when (> drift worst-drift)
            (set worst-drift drift))
          (assert (< drift 0.05)
                  (string.format
                   "Expected restored physics cuboids to keep stable Y before/after ticks (cycle=%d drift=%.6f start=(%.6f,%.6f) end=(%.6f,%.6f))"
                   cycle
                   drift
                   (. start-ys 1)
                   (. start-ys 2)
                   (. end-ys 1)
                   (. end-ys 2)))
          (scene:capture-state))))
    (cleanup)
    (when (not ok)
      (error payload))
    (set current-captured payload))
  (assert (< worst-drift 0.05)
          (string.format "Expected worst restore drift < 0.05, got %.6f" worst-drift))
  true)

(fn scene-add-graph-node-cube-adds-physics-and-readds-node []
  (assert bt "Graph node cube test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (local graph (Graph {:with-start false}))
  (set app.graph graph)

  (let [(ok err)
        (pcall
          (fn []
            (local node (Graph.GraphNode {:key "cube-node"
                                          :label "Node cube label for lod checks and wrapping"}))
            (local element
              (scene:add-graph-node-cube {:node node
                                          :position (glm.vec3 0 16 0)}))
            (assert element "Expected add-graph-node-cube to return an element")
            (assert scene.entity.physics-bodies
                    "Scene should track runtime physics bodies for graph node cubes")
            (local entry (. scene.entity.physics-bodies (length scene.entity.physics-bodies)))
            (assert (and entry entry.body)
                    "Graph node cube should create a runtime rigid body")
            (assert (and element.child element.child.open-graph)
                    "Graph node cube should expose an open-graph action")
            (assert (not (graph:lookup "cube-node"))
                    "Node should not exist in graph before graph action")
            (element.child:open-graph nil nil)
            (assert (graph:lookup "cube-node")
                    "Graph action should add node to graph")
            (graph:remove-nodes [(graph:lookup "cube-node")])
            (assert (not (graph:lookup "cube-node"))
                    "Node should be removable from graph")
            (element.child:open-graph nil nil)
            (assert (graph:lookup "cube-node")
                    "Graph action should re-add node after removal")))]
    (set app.graph original-graph)
    (graph:drop)
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-restore-graph-node-cube-uses-scene-graph-before-app-binding []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (set app.graph nil)
  (local graph (Graph {:with-start false}))
  (scene:set-graph graph)
  (local node (Graph.GraphNode {:key "test-node"
                                :label "restore target"}))
  (graph:add-node node {})
  (local initial-count (length (or scene.entity.children [])))

  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind "graph-node-cube"
                                        :node-key "test-node"
                                        :label "restore target"
                                        :size [4 4 4]
                                        :position [0 16 0]
                                        :rotation [1 0 0 0]}]}))))
  (local final-count (length (or scene.entity.children [])))
  (set app.graph original-graph)
  (graph:drop)
  (cleanup)
  (assert ok
          (.. "Expected scene restore to use scene.graph before app binding, got: "
              (tostring err)))
  (assert (= final-count (+ initial-count 1))
          "Scene restore should add graph node cube using scene-owned graph")
  true)

(fn scene-restore-graph-node-cube-sanitizes-poisoned-position []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (set app.graph nil)
  (local graph (Graph {:with-start false}))
  (scene:set-graph graph)
  (local node (Graph.GraphNode {:key "poisoned-node"
                                :label "poisoned restore target"}))
  (graph:add-node node {})
  (local initial-count (length (or scene.entity.children [])))

  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind "graph-node-cube"
                                        :node-key "poisoned-node"
                                        :label "poisoned restore target"
                                        :size [4 4 4]
                                        :position [1001000 0 0]
                                        :rotation [1 0 0 0]}]}))))
  (local final-count (length (or scene.entity.children [])))
  (local restored-metadata (. (or scene.entity.children []) final-count))
  (local restored-element (and restored-metadata restored-metadata.element))
  (local restored-layout (and restored-element restored-element.layout))
  (set app.graph original-graph)
  (graph:drop)
  (cleanup)
  (assert ok
          (.. "Expected scene restore to sanitize poisoned positions, got: "
              (tostring err)))
  (assert (= final-count (+ initial-count 1))
          "Scene restore should still add graph node cube after position sanitization")
  (assert restored-layout "Restored graph node should have a layout")
  (assert (< (glm.length restored-layout.position) 1000000)
          "Restored graph node position should be kept within vec3 safety threshold")
  true)

(fn scene-restore-graph-node-cube-sanitizes-poisoned-size []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (set app.graph nil)
  (local graph (Graph {:with-start false}))
  (scene:set-graph graph)
  (local node (Graph.GraphNode {:key "poisoned-size-node"
                                :label "poisoned size restore target"}))
  (graph:add-node node {})
  (local initial-count (length (or scene.entity.children [])))

  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind "graph-node-cube"
                                        :node-key "poisoned-size-node"
                                        :label "poisoned size restore target"
                                        :size [1001000 4 4]
                                        :position [0 0 0]
                                        :rotation [1 0 0 0]}]}))))
  (local final-count (length (or scene.entity.children [])))
  (local restored-metadata (. (or scene.entity.children []) final-count))
  (local restored-element (and restored-metadata restored-metadata.element))
  (local restored-layout (and restored-element restored-element.layout))
  (set app.graph original-graph)
  (graph:drop)
  (cleanup)
  (assert ok
          (.. "Expected scene restore to sanitize poisoned sizes, got: "
              (tostring err)))
  (assert (= final-count (+ initial-count 1))
          "Scene restore should still add graph node cube after size sanitization")
  (assert restored-layout "Restored graph node should have a layout")
  (assert (< restored-layout.size.x 1000000)
          "Restored graph node size should be kept within vec3 safety threshold")
  true)

(fn scene-restore-state-skips-legacy-panel-without-restorer []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (set app.graph nil)
  (local graph (Graph {:with-start false}))
  (scene:set-graph graph)
  (local node (Graph.GraphNode {:key "legacy-skip-node"
                                :label "legacy skip target"}))
  (graph:add-node node {})
  (local initial-count (length (or scene.entity.children [])))

  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind "legacy-panel-without-restorer"
                                        :position [1 2 3]
                                        :rotation [1 0 0 0]
                                        :size [4 4 4]}
                                       {:kind "graph-node-cube"
                                        :node-key "legacy-skip-node"
                                        :label "legacy skip target"
                                        :position [4 5 6]
                                        :rotation [1 0 0 0]
                                        :size [4 4 4]}]}))))
  (local final-count (length (or scene.entity.children [])))
  (local restored-metadata (. (or scene.entity.children []) final-count))
  (set app.graph original-graph)
  (graph:drop)
  (cleanup)
  (assert ok
          (.. "Expected scene restore to skip legacy panels without failing, got: "
              (tostring err)))
  (assert (= final-count (+ initial-count 1))
          "Scene restore should skip legacy panels without restorers and continue restoring valid ones")
  (assert (= (and restored-metadata restored-metadata.persistence restored-metadata.persistence.kind)
             "graph-node-cube")
          "Scene restore should still restore valid panels after skipping legacy ones")
  true)

(fn scene-restore-state-does-not-hide-registered-restorer-failures []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local owner {})
  (local kind "broken-restorer-panel")
  (scene:register-panel-restorer
    kind
    (fn [_panel]
      (error "expected registered restorer failure"))
    owner)
  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind kind}]}))))
  (scene:unregister-panel-restorer kind owner)
  (cleanup)
  (assert (not ok)
          "Scene restore should still fail when a registered restorer throws")
  (assert (and err (string.find (tostring err) "expected registered restorer failure" 1 true))
          "Scene restore should surface the original registered restorer failure")
  true)

(table.insert tests {:name "Demo browser appends dialogs and movables" :fn demo-browser-adds-dialogs-to-scene})
(table.insert tests {:name "Closing demo dialog removes it from the scene" :fn closing-demo-dialog-removes-positioned-child})
(table.insert tests {:name "Demo browser capture/restore roundtrip" :fn demo-browser-capture-and-restore-roundtrip})
(table.insert tests {:name "Scene capture-state includes default terrain"
                     :fn scene-capture-state-includes-default-terrain})
(table.insert tests {:name "Scene recover terrain-bound panel uses lowest overlapping terrain"
                     :fn scene-recover-terrain-bound-panel-uses-lowest-overlapping-terrain})
(table.insert tests {:name "Scene recover terrain-bound object moves to nearest terrain"
                     :fn scene-recover-terrain-bound-object-moves-to-nearest-terrain})
(table.insert tests {:name "Scene recover ignores unbound scene object"
                     :fn scene-recover-ignores-unbound-scene-object})
(table.insert tests {:name "Scene recover terrain-bound physics cuboid repositions body"
                     :fn scene-recover-terrain-bound-physics-cuboid-repositions-body})
(table.insert tests {:name "Scene recover nearest terrain respects scene root transform"
                     :fn scene-recover-nearest-terrain-respects-scene-root-transform})
(table.insert tests {:name "Scene build-default preserves explicit empty terrains"
                     :fn scene-build-default-preserves-explicit-empty-terrains})
(table.insert tests {:name "Scene screen-pos terrain domain hit respects scene root transform"
                     :fn scene-screen-pos-terrain-domain-hit-respects-scene-root-transform})
(table.insert tests {:name "Scene screen-pos terrain hit resolves default heightfield"
                     :fn scene-screen-pos-terrain-hit-resolves-default-heightfield})
(table.insert tests {:name "Scene screen-rect terrain target builds sample set"
                     :fn scene-screen-rect-terrain-target-builds-sample-set})
(table.insert tests {:name "Scene screen-rect terrain target respects scene root transform"
                     :fn scene-screen-rect-terrain-target-respects-scene-root-transform})
(table.insert tests {:name "Scene screen-pos terrain domain hit scales logical input to pixel viewport"
                     :fn scene-screen-pos-terrain-domain-hit-scales-logical-input-to-pixel-viewport})
(table.insert tests {:name "Heightfield target capture resolves live scene drag"
                     :fn heightfield-target-capture-resolves-live-scene-drag})
(table.insert tests {:name "Heightfield target capture escape cancels selection"
                     :fn heightfield-target-capture-escape-cancels-selection})
(table.insert tests {:name "Heightfield target capture requires both drag endpoints on terrain"
                     :fn heightfield-target-capture-requires-both-drag-endpoints-on-terrain})
(table.insert tests {:name "Heightfield target capture uses last drag position on release"
                     :fn heightfield-target-capture-uses-last-drag-position-on-release})
(table.insert tests {:name "Heightfield target capture clears selection when drag leaves terrain"
                     :fn heightfield-target-capture-clears-selection-when-drag-leaves-terrain})
(table.insert tests {:name "Heightfield target capture resolves live scene drag with default ray opts"
                     :fn heightfield-target-capture-resolves-live-scene-drag-with-default-ray-opts})
(table.insert tests {:name "Heightfield paint capture stamps live scene samples"
                     :fn heightfield-paint-capture-stamps-live-scene-samples})
(table.insert tests {:name "Heightfield paint capture does not raycast before stroke"
                     :fn heightfield-paint-capture-does-not-raycast-before-stroke})
(table.insert tests {:name "Terrain rect pick state routes engine events"
                     :fn terrain-rect-pick-state-routes-engine-events})
(table.insert tests {:name "Scene terrain selection persists across runtime replace"
                     :fn scene-terrain-selection-persists-across-runtime-replace})
(table.insert tests {:name "Demo entry capture-state persists entry metadata"
                     :fn demo-entry-capture-state-persists-entry-persistence})
(table.insert tests {:name "Scene capture-state requires panel persistence"
                     :fn scene-capture-state-requires-panel-persistence})
(table.insert tests {:name "Scene capture-state requires restore strategy"
                     :fn scene-capture-state-requires-restore-strategy})
(table.insert tests {:name "Scene additions appear in front of the camera" :fn added-dialog-appears-in-front-of-camera})
(table.insert tests {:name "Scene runtime physics body falls" :fn scene-add-physics-body-falls})
(table.insert tests {:name "Scene ball appears in front of camera and restores"
                     :fn scene-add-ball-appears-in-front-of-camera-and-restores})
(table.insert tests {:name "Scene ball context menu removes ball"
                     :fn scene-ball-context-menu-removes-ball})
(table.insert tests {:name "Scene ball settles on configured containment floor"
                     :fn scene-ball-settles-on-configured-containment-floor})
(table.insert tests {:name "Scene physics body collides with flat terrain"
                     :fn scene-physics-body-collides-with-flat-terrain})
(table.insert tests {:name "Scene heightfield physics respects scene root transform"
                     :fn scene-heightfield-physics-respects-scene-root-transform})
(table.insert tests {:name "Scene replaced heightfield updates physics"
                     :fn scene-replaced-heightfield-updates-physics})
(table.insert tests {:name "Scene replaced heightfield updates lifted ball collision"
                     :fn scene-replaced-heightfield-updates-lifted-ball-collision})
(table.insert tests {:name "Scene replaced heightfield allows direct drag placement on raised area"
                     :fn scene-replaced-heightfield-allows-direct-drag-placement-on-raised-area})
(table.insert tests {:name "Scene live heightfield ball above raised area stays near supported surface"
                     :fn scene-live-heightfield-ball-above-raised-area-stays-near-supported-surface})
(table.insert tests {:name "Scene live heightfield supports balls across 3x3 chunks"
                     :fn scene-live-heightfield-supports-balls-across-3x3-chunks})
(table.insert tests {:name "Scene first home world supports balls on elevated samples"
                     :fn scene-first-home-world-supports-balls-on-elevated-samples})
(table.insert tests {:name "Scene first home world supports ball on central plateau"
                     :fn scene-first-home-world-supports-ball-on-central-plateau})
(table.insert tests {:name "Scene terrain surface query is stable across updates"
                     :fn scene-terrain-surface-query-is-stable-across-updates})
(table.insert tests {:name "Scene runtime body falls after drag release"
                     :fn scene-runtime-body-falls-after-drag-release})
(table.insert tests {:name "Scene restore physics cuboids world-switch drift check"
                     :fn scene-restore-physics-cuboids-world-switch-drift-check})
(table.insert tests {:name "Scene graph node cube adds physics and graph action"
                     :fn scene-add-graph-node-cube-adds-physics-and-readds-node})
(table.insert tests {:name "Scene restore graph node cube uses scene graph before app binding"
                     :fn scene-restore-graph-node-cube-uses-scene-graph-before-app-binding})
(table.insert tests {:name "Scene restore graph node cube sanitizes poisoned position"
                     :fn scene-restore-graph-node-cube-sanitizes-poisoned-position})
(table.insert tests {:name "Scene restore graph node cube sanitizes poisoned size"
                     :fn scene-restore-graph-node-cube-sanitizes-poisoned-size})
(table.insert tests {:name "Scene restore skips legacy panel without restorer"
                     :fn scene-restore-state-skips-legacy-panel-without-restorer})
(table.insert tests {:name "Scene restore does not hide registered restorer failures"
                     :fn scene-restore-state-does-not-hide-registered-restorer-failures})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "demo-browser"
                       :tests tests})))

{:name "demo-browser"
 :tests tests
 :main main}
