(local glm (require :glm))
(local Scene (require :scene))
(local Camera (require :camera))
(local Graph (require :graph/init))
(local DemoDialogs (require :demo-dialogs))
(local MathUtils (require :math-utils))
(local PhysicsFloor (require :physics-floor))
(local {: Layout} (require :layout))
(local bt (require :bt))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec3-approx= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

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

(fn configure-test-physics-world []
  (when (and app.engine app.engine.physics)
    (app.engine.physics:setGravity 0 -25 0)
    (PhysicsFloor.ensure-installed {})))

(fn setup-scene [opts]
  (local options (or opts {}))
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-camera app.camera)
  (var scene nil)
  (var movables nil)
  (local icons (make-icons-stub))

  (fn cleanup []
    (when scene
      (scene:drop)
      (set scene nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.camera original-camera))

  (let [(ok payload)
        (pcall (fn []
                 (set movables (make-stub-movables))
                 (set scene (Scene {:icons icons}))
                 (set app.scene scene)
                 (set app.layout-root scene.layout-root)
                 (set app.movables movables)
                 (when options.camera
                   (set app.camera options.camera))
                 (configure-test-physics-world)
                 (scene:build-default)
                 {:scene scene :movables movables :icons icons}))]
    (if ok
        {:cleanup cleanup :scene-result payload}
        (do
          (cleanup)
          (error payload)))))

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
        (assert (= terrain.kind "flat-terrain")
                "Expected default terrain kind flat-terrain")
        (assert terrain.id "Expected captured terrain id"))))
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

(fn scene-build-default-skips-unsupported-terrains []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains [{:id "t-1"
                                          :kind "heightfield-terrain"
                                          :options {:width 64}}]})
        (local captured (scene:capture-state))
        (local terrains (or captured.terrains []))
        (assert (= (length terrains) 0)
                "Unsupported terrains should be skipped during scene build"))))
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
            (local element (scene:add-ball {:size (glm.vec3 18 18 18)}))
            (assert element "Expected add-ball to return an element")
            (assert (= (length (or scene.entity.balls [])) 1)
                    "Scene should track runtime balls")
            (local layout element.layout)
            (local expected-center
              (+ camera.position (* (camera:get-forward) (glm.vec3 100))))
            (local half-size (* 0.5 layout.size))
            (local center (+ layout.position (layout.rotation:rotate half-size)))
            (assert (vec3-approx= center expected-center)
                    "Ball center should be placed 100 units in front of the camera")

            (local captured (scene:capture-state))
            (local panels (or captured.panels []))
            (assert (= (length panels) 1)
                    "Expected one persisted scene panel for ball")
            (local panel (. panels 1))
            (assert (= panel.kind "physics-ball")
                    "Ball persistence kind should be physics-ball")

            (scene:remove-panel-child element)
            (assert (= (length (or scene.entity.balls [])) 0)
                    "Removing ball should clear runtime ball tracking")

            (scene:restore-state captured)
            (assert (= (length (or scene.entity.balls [])) 1)
                    "Scene restore should recreate persisted ball")))]
    (cleanup)
  (when (not ok)
    (error err))))

(fn scene-ball-settles-on-global-floor []
  (assert bt "Scene ball floor test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (local (ok err)
    (pcall
      (fn []
        (local element (scene:add-ball {:size (glm.vec3 18 18 18)
                                        :position (glm.vec3 0 40 0)}))
        (assert element "Expected add-ball to return an element")
        (for [_ 1 1500]
          (app.engine.physics:update 0)
          (scene:update))
        (local center (+ element.layout.position
                         (element.layout.rotation:rotate (* 0.5 element.layout.size))))
        (assert (> center.y -100)
                (string.format
                  "Ball should not fall through global floor at y=-100 (center_y=%.3f)"
                  center.y))
        (assert (< center.y -70)
                (string.format
                  "Ball should settle near global floor, not remain high (center_y=%.3f)"
                  center.y)))))
  (cleanup)
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

(table.insert tests {:name "Demo browser appends dialogs and movables" :fn demo-browser-adds-dialogs-to-scene})
(table.insert tests {:name "Closing demo dialog removes it from the scene" :fn closing-demo-dialog-removes-positioned-child})
(table.insert tests {:name "Demo browser capture/restore roundtrip" :fn demo-browser-capture-and-restore-roundtrip})
(table.insert tests {:name "Scene capture-state includes default terrain"
                     :fn scene-capture-state-includes-default-terrain})
(table.insert tests {:name "Scene build-default preserves explicit empty terrains"
                     :fn scene-build-default-preserves-explicit-empty-terrains})
(table.insert tests {:name "Demo entry capture-state persists entry metadata"
                     :fn demo-entry-capture-state-persists-entry-persistence})
(table.insert tests {:name "Scene capture-state requires panel persistence"
                     :fn scene-capture-state-requires-panel-persistence})
(table.insert tests {:name "Scene capture-state requires restore strategy"
                     :fn scene-capture-state-requires-restore-strategy})
(table.insert tests {:name "Scene additions appear in front of the camera" :fn added-dialog-appears-in-front-of-camera})
(table.insert tests {:name "Scene build default skips unsupported terrains"
                     :fn scene-build-default-skips-unsupported-terrains})
(table.insert tests {:name "Scene runtime physics body falls" :fn scene-add-physics-body-falls})
(table.insert tests {:name "Scene ball appears in front of camera and restores"
                     :fn scene-add-ball-appears-in-front-of-camera-and-restores})
(table.insert tests {:name "Scene ball settles on global floor"
                     :fn scene-ball-settles-on-global-floor})
(table.insert tests {:name "Scene physics body collides with flat terrain"
                     :fn scene-physics-body-collides-with-flat-terrain})
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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "demo-browser"
                       :tests tests})))

{:name "demo-browser"
 :tests tests
 :main main}
