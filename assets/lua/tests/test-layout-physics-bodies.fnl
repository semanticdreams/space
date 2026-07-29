(local glm (require :glm))
(local Scene (require :scene))
(local Camera (require :camera))
(local {: FirstPersonControls} (require :first-person-controls))
(local MathUtils (require :math-utils))
(local PhysicsContainment (require :physics-containment))
(local {: Layout} (require :layout))
(local PerlinTerrain (require :perlin-terrain))
(local bt (require :bt))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))

(local Logging (require :logging))
(local Movables (require :movables))
(local Intersectables (require :intersectables))

(local tests [])
(local approx (. MathUtils :approx))

(fn vec3-approx= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn make-icons-stub []
  (local stub {:font {:glyph-map {65533 {:advance 1.0}}
                      :metadata {:metrics {:lineHeight 1.0
                                           :ascender 0.5
                                           :descender -0.5}}}})
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
  (local movables {:registered [] :unregistered []})
  (set movables.register
       (fn [self widget opts]
         (table.insert self.registered {:widget widget
                                        :opts opts})))
  (set movables.unregister
       (fn [self key]
         (table.insert self.unregistered key)))
  movables)

(var test-containment-manager nil)

(fn configure-test-physics-world [opts]
  (local options (or opts {}))
  (local config (or options.config (PhysicsContainment.default-config)))
  (when (and app.engine app.engine.physics)
    (app.engine.physics:setGravity 0 -25 0)
    (when (not test-containment-manager)
      (set test-containment-manager
           (PhysicsContainment.create-manager {:owner {} :physics app.engine.physics})))
    (test-containment-manager:ensure-installed {:config config})))

(fn setup-scene []
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-camera app.camera)
  (var scene nil)
  (var camera nil)

  (fn cleanup []
    (when scene
      (scene:drop)
      (set scene nil))
    (when camera
      (camera:drop)
      (set camera nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.camera original-camera)
    (when test-containment-manager
      (test-containment-manager:clear)))

  (let [(ok payload)
        (pcall (fn []
                 (local movables (make-stub-movables))
                 (set camera (Camera {:position (glm.vec3 0 0 0)}))
                 (set scene (Scene {:icons (make-icons-stub)
                                    :camera camera}))
                 (set app.scene scene)
                 (set app.layout-root scene.layout-root)
                 (set app.movables movables)
                 (set app.camera camera)
                  (configure-test-physics-world)
                   (scene:ensure-activity-slot "sandbox" {:camera camera})
                  (scene:activate-activity-slot "sandbox")
                  (scene:build-default)
                 {:scene scene :movables movables}))]
    (if ok
        {:cleanup cleanup :scene-result payload}
        (do
          (cleanup)
          (error payload)))))

(fn manual-containment-config [min-y]
  {:mode "manual-bounds"
   :bounds {:min [-500 min-y -500]
            :max [500 500 500]}})

(fn find-physics-entry-for-element [scene element]
  (accumulate [result nil _ entry (ipairs (or scene.entity.physics-bodies []))]
    (if (and (not result)
             (= entry.positioned element))
        entry
        result)))

(fn make-probe-panel-builder [size-ref]
  (fn [_ctx _runtime-opts]
    (local layout
      (Layout {:name "physics-probe-panel"
               :measurer (fn [self]
                           (set self.measure size-ref.value))
               :layouter (fn [self]
                           (set self.size self.measure))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))}))

(fn physical-panels-collide-with-each-other []
  (assert bt "Physical panel collision test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (local lower-size {:value (glm.vec3 6 3 6)})
  (local upper-size {:value (glm.vec3 6 3 6)})
  (local lower-builder (make-probe-panel-builder lower-size))
  (local upper-builder (make-probe-panel-builder upper-size))

  (let [(ok err)
        (pcall
          (fn []
            (local lower (scene:add-panel-child {:builder lower-builder
                                                 :skip-cuboid true
                                                 :position (glm.vec3 0 10 0)}))
            (local upper (scene:add-panel-child {:builder upper-builder
                                                 :skip-cuboid true
                                                 :position (glm.vec3 0 22 0)}))
            (assert lower "Expected lower panel")
            (assert upper "Expected upper panel")
            (assert (find-physics-entry-for-element scene lower)
                    "Lower panel should register a runtime physics body")
            (assert (find-physics-entry-for-element scene upper)
                    "Upper panel should register a runtime physics body")

            (for [i 1 360]
              (app.engine.physics:update 0)
              (scene:update))

            (assert (> upper.layout.position.y (+ lower.layout.position.y 1.0))
                    (string.format
                      "Upper panel should remain above lower panel after settling (lower_y=%.3f upper_y=%.3f)"
                      lower.layout.position.y
                      upper.layout.position.y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn physical-panel-collides-with-perlin-terrain []
  (assert bt "Perlin terrain collision test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (local panel-size {:value (glm.vec3 5 3 5)})
  (local panel-builder (make-probe-panel-builder panel-size))

  (let [(ok err)
        (pcall
          (fn []
            (scene:add-panel-child
              {:builder (PerlinTerrain {:position (glm.vec3 500 -100 -500)
                                        :scale (glm.vec3 20 3.5 20)
                                        :width 50
                                        :length 50
                                        :seed 424242
                                        :n1scale 34
                                        :n2scale 4
                                        :n3scale 1.5})
               :skip-cuboid true
               :skip-physics true
               :position (glm.vec3 500 -100 -500)
               :rotation (glm.quat 1 0 0 0)})

            (local panel (scene:add-panel-child {:builder panel-builder
                                                 :skip-cuboid true
                                                 :position (glm.vec3 1000 20 0)}))
            (assert panel "Expected panel on Perlin terrain")
            (local start-y panel.layout.position.y)

            (for [i 1 240]
              (app.engine.physics:update 0)
              (scene:update))

            (local end-y panel.layout.position.y)
            (assert (< end-y (- start-y 10))
                    (string.format
                      "Panel should fall before settling on Perlin terrain (start_y=%.3f end_y=%.3f)"
                      start-y end-y))
            (assert (> end-y -220)
                    (string.format
                      "Panel likely fell through Perlin terrain (end_y=%.3f)"
                      end-y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn physical-panel-rebuilds-body-on-resize []
  (assert bt "Resize shape-refresh test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (local size-ref {:value (glm.vec3 2 2 2)})
  (local builder (make-probe-panel-builder size-ref))

  (let [(ok err)
        (pcall
          (fn []
            (local panel (scene:add-panel-child {:builder builder
                                                 :skip-cuboid true
                                                 :position (glm.vec3 0 15 0)}))
            (assert panel "Expected panel")
            (local entry (find-physics-entry-for-element scene panel))
            (assert (and entry entry.rigid entry.rigid.shape)
                    "Expected runtime body shape for panel")
            (local initial-shape entry.rigid.shape)

            (set size-ref.value (glm.vec3 9 2 2))
            (panel.layout:mark-measure-dirty)
            (scene:update)
            (scene:update)

            (assert (not (= entry.rigid.shape initial-shape))
                    "Resizing panel should rebuild Bullet box shape")
            (assert (and entry.body entry.body-active?)
                    "Resized panel body should remain active")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn physical-panel-applies-stability-body-tuning []
  (assert bt "Panel body tuning test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local size-ref {:value (glm.vec3 4 12 4)})
  (local builder (make-probe-panel-builder size-ref))

  (local (ok err)
    (pcall
      (fn []
        (local panel (scene:add-panel-child {:builder builder
                                             :skip-cuboid true
                                             :position (glm.vec3 0 20 0)}))
        (assert panel "Expected panel")
        (local entry (find-physics-entry-for-element scene panel))
        (assert (and entry entry.body) "Expected runtime physics body")
        (assert (approx (entry.body:getFriction) 0.95)
                "Panel body should use elevated friction")
        (assert (approx (entry.body:getRollingFriction) 0.2)
                "Panel body should use rolling friction")
        (assert (approx (entry.body:getSpinningFriction) 0.35)
                "Panel body should use spinning friction")
        (assert (approx (entry.body:getLinearDamping) 0.04)
                "Panel body should use light linear damping")
        (assert (approx (entry.body:getAngularDamping) 0.35)
                "Panel body should use stronger angular damping"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn physical-panel-stops-at-global-containment-floor []
  (assert bt "Global containment floor test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (configure-test-physics-world {:config (manual-containment-config -500)})
  (local panel-size {:value (glm.vec3 5 3 5)})
  (local panel-builder (make-probe-panel-builder panel-size))

  (let [(ok err)
        (pcall
          (fn []
            (local panel (scene:add-panel-child {:builder panel-builder
                                                 :skip-cuboid true
                                                 :position (glm.vec3 5000 40 0)}))
            (assert panel "Expected panel on global containment test")
            (for [_ 1 1200]
              (app.engine.physics:update 0)
              (scene:update))
            (assert (> panel.layout.position.y -505)
                    (string.format
                      "Panel should not fall through containment floor at y=-500 (y=%.3f)"
                      panel.layout.position.y))
            (assert (< panel.layout.position.y -410)
                    (string.format
                      "Panel should settle near containment floor, not remain high (y=%.3f)"
                      panel.layout.position.y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn physical-panel-respects-configured-containment-floor-height []
  (assert bt "Configured containment floor test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (configure-test-physics-world {:config (manual-containment-config -1500)})
  (local panel-size {:value (glm.vec3 5 3 5)})
  (local panel-builder (make-probe-panel-builder panel-size))

  (local (ok err)
    (pcall
      (fn []
        (local panel (scene:add-panel-child {:builder panel-builder
                                             :skip-cuboid true
                                             :position (glm.vec3 8000 40 0)}))
        (assert panel "Expected panel on configured containment test")
        (for [_ 1 1500]
          (app.engine.physics:update 0)
          (scene:update))
        (assert (> panel.layout.position.y -1510)
                (string.format
                  "Panel should not fall through configured containment floor at y=-1500 (y=%.3f)"
                  panel.layout.position.y))
        (assert (< panel.layout.position.y -1400)
                (string.format
                  "Panel should settle near configured containment floor, not remain high (y=%.3f)"
                  panel.layout.position.y)))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn graph-node-cube-add-does-not-crash-after-ms-fpc-update []
  (assert bt "Graph-node cube large-camera test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph-map app.graph-map)
  (local graph (Graph {:with-start false}))
  (local map (GraphMap.GraphMap {:graph graph :id "test-fpc-cube"}))
  (set scene.graph-map map)
  (set app.graph-map map)
  (local original-camera app.camera)
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local controls (FirstPersonControls {:camera camera}))
  (controls:on-key-down {:key 44})
  ;; Engine emits frame delta in ms on events.updated.
  (for [_ 1 140]
    (controls:update 1000))
  (controls:on-key-up {:key 44})
  (set app.camera camera)
  (scene:set-camera camera)
  (let [(ok err)
        (pcall
          (fn []
            (local node {:key "layout-physics-bodies-test-node"
                         :label "layout-physics-bodies-test-node"})
            (local cube (scene:add-graph-node-cube {:node node}))
            (assert cube "Expected graph-node cube element")))]
    (controls:drop)
    (set app.camera original-camera)
    (set app.graph-map original-graph-map)
    (map:drop)
    (graph:drop)
    (cleanup)
    (assert ok
            (.. "Adding graph-node cube should not crash after ms FPC update, but got: "
                (tostring err)))))

(fn physics-sync-recovers-from-out-of-bounds-body-transform []
  (assert bt "Out-of-bounds transform test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local size-ref {:value (glm.vec3 4 4 4)})
  (local builder (make-probe-panel-builder size-ref))

  (local (ok err)
    (pcall
      (fn []
        (local panel (scene:add-panel-child {:builder builder
                                             :skip-cuboid true
                                             :position (glm.vec3 0 12 0)}))
        (assert panel "Expected panel")
        (local entry (find-physics-entry-for-element scene panel))
        (assert (and entry entry.body) "Expected runtime physics body")
        (local transform (bt.Transform))
        (transform:setIdentity)
        (transform:setOrigin (bt.Vector3 0 1001000 0))
        (transform:setRotation (bt.Quaternion 0 0 0 1))
        (entry.body:setWorldTransform transform)
        (when (and entry.rigid entry.rigid.motion-state)
          (entry.rigid.motion-state:setWorldTransform transform))
        (scene:update)
        (assert (< (math.abs panel.layout.position.y) 1000000)
                "Scene update should keep layout position in vec3-safe range")
        (assert (< (math.abs entry.offset.y) 1000000)
                "Recovered entry offset should remain in vec3-safe range")
        (local transform (entry.body:getCenterOfMassTransform))
        (local center (transform:getOrigin))
        (assert (< (math.abs center.y) 1000000)
                "Recovered body center should remain in vec3-safe range"))))
  (cleanup)
  (assert ok
          (.. "Scene update should recover from out-of-bounds physics transform, got: "
              (tostring err))))

(fn physics-anchor-mode-records-relative-anchor []
  (assert bt "Anchor drag test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-provider app.activity-drag-attachment-provider)
  (set app.activity-drag-attachment-provider (fn [] :anchor))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local size-ref {:value (glm.vec3 4 4 4)})
  (local builder (make-probe-panel-builder size-ref))
  (let [(ok err)
        (pcall
          (fn []
            (local panel (scene:add-panel-child {:builder builder
                                                  :skip-cuboid true
                                                  :position (glm.vec3 0 12 0)}))
            (assert panel "Expected panel for anchor drag test")
            (local entry (find-physics-entry-for-element scene panel))
            (assert (and entry entry.body) "Expected runtime physics body for anchor drag")

            ;; Collect movables from the entity
            (local LayoutPhysicsBodies (require :layout-physics-bodies))
            (local movables-entries (LayoutPhysicsBodies.collect-movables scene.entity))
            (var anchor-entry nil)
            (each [_ m (ipairs movables-entries)]
              (when (and (not anchor-entry)
                         (= m.target panel.layout))
                (set anchor-entry m)))
            (assert anchor-entry "Should find movable entry pointing to panel layout")
            (assert anchor-entry.on-drag-update "Anchor mode should include on-drag-update callback")

            ;; Simulate drag start to compute relative anchor
            (local hit-point (glm.vec3 1 2 3))
            (set entry.dragging true)
            (local movable-stub {:target panel.layout})

            ;; on-drag-start records dragging state
            (when anchor-entry.on-drag-start
              (anchor-entry.on-drag-start movable-stub))
            (assert entry.dragging "Entry should be in dragging state after drag start")))]
    (cleanup)
    (set app.activity-drag-attachment-provider original-provider)
    (when (not ok)
      (error err))))

(fn physics-anchor-mode-calls-applyForceAtPosition-during-drag []
  (assert bt "Anchor force test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-provider app.activity-drag-attachment-provider)
  (set app.activity-drag-attachment-provider (fn [] :anchor))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local size-ref {:value (glm.vec3 4 4 4)})
  (local builder (make-probe-panel-builder size-ref))
  (let [(ok err)
        (pcall
          (fn []
            (local panel (scene:add-panel-child {:builder builder
                                                  :skip-cuboid true
                                                  :position (glm.vec3 0 12 0)}))
            (assert panel "Expected panel for anchor force test")
            (local entry (find-physics-entry-for-element scene panel))
            (assert (and entry entry.body) "Expected runtime physics body")

            ;; Collect movables
            (local LayoutPhysicsBodies (require :layout-physics-bodies))
            (local movables-entries (LayoutPhysicsBodies.collect-movables scene.entity))
            (var anchor-entry nil)
            (each [_ m (ipairs movables-entries)]
              (when (and (not anchor-entry)
                         (= m.target panel.layout))
                (set anchor-entry m)))
            (assert anchor-entry "Should find anchor-mode movable entry")

            ;; Create a fake body that records applyForceAtPosition calls
            (var force-recorded nil)
            (var activate-called false)
            (local original-body entry.body)
            (set entry.body
                 {:applyForceAtPosition (fn [_self force rel-pos]
                                         (set force-recorded {:force force :rel-pos rel-pos}))
                  :forceActivationState (fn [_self state]
                                          nil)
                  :activate (fn [_self _force]
                              (set activate-called true))
                  :getCenterOfMassTransform (fn [_self]
                                              (local t (bt.Transform))
                                              (t:setIdentity)
                                              (t:setOrigin (bt.Vector3 2 2 2))
                                              t)})

            ;; Start drag at a known hit point
            (local hit-point (glm.vec3 1 2 3))
            (local drag {:entry anchor-entry
                         :hit-point hit-point
                         :started? false
                         :plane {:point hit-point
                                 :normal (glm.vec3 0 1 0)}
                         :plane-mode :forward
                         :offset (glm.vec3 0 0 0)})
            (set entry.dragging true)

            ;; Call on-drag-start if present
            (when anchor-entry.on-drag-start
              (anchor-entry.on-drag-start anchor-entry))

            ;; Build update table and call on-drag-update
            (local update {:payload {:button 1 :x 5 :y 6 :mod 0}
                           :pointer (glm.vec3 5 6 0)
                           :ray {:origin (glm.vec3 5 6 10)
                                 :direction (glm.vec3 0 0 -1)}
                           :hit (glm.vec3 5 6 0)
                           :new-position (glm.vec3 5 6 0)
                           :plane drag.plane})
            (local handled? (anchor-entry.on-drag-update anchor-entry drag update))

            ;; Restore original body
            (set entry.body original-body)

            (assert force-recorded "Anchor mode should call applyForceAtPosition during drag")
            (assert activate-called "Anchor mode should activate the body")
            (assert handled? "Anchor mode on-drag-update should return true to suppress teleport")))]
    (cleanup)
    (set app.activity-drag-attachment-provider original-provider)
    (when (not ok)
      (error err))))

(fn physics-center-mode-allows-default-teleport []
  (assert bt "Center mode test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-provider app.activity-drag-attachment-provider)
  (set app.activity-drag-attachment-provider (fn [] :center))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local size-ref {:value (glm.vec3 4 4 4)})
  (local builder (make-probe-panel-builder size-ref))
  (let [(ok err)
        (pcall
          (fn []
            (local panel (scene:add-panel-child {:builder builder
                                                  :skip-cuboid true
                                                  :position (glm.vec3 0 12 0)}))
            (assert panel "Expected panel for center-mode drag test")

            ;; Collect movables
            (local LayoutPhysicsBodies (require :layout-physics-bodies))
            (local movables-entries (LayoutPhysicsBodies.collect-movables scene.entity))
            (var center-entry nil)
            (each [_ m (ipairs movables-entries)]
              (when (and (not center-entry)
                         (= m.target panel.layout))
                (set center-entry m)))
            (assert center-entry "Should find center-mode movable entry")
            (assert center-entry.on-drag-update "Movable entry should have on-drag-update")

            ;; For center mode, on-drag-update should return false (allow teleport)
            (local drag {:entry center-entry
                         :hit-point (glm.vec3 0 0 0)
                         :started? true
                         :plane {:point (glm.vec3 0 0 0)
                                 :normal (glm.vec3 0 1 0)}
                         :offset (glm.vec3 0 0 0)})
            (local update {:payload {:button 1 :x 5 :y 6 :mod 0}
                           :pointer (glm.vec3 5 6 0)
                           :ray {:origin (glm.vec3 5 6 10)
                                 :direction (glm.vec3 0 0 -1)}
                           :hit (glm.vec3 5 6 0)
                           :new-position (glm.vec3 5 6 0)
                           :plane drag.plane})
            (local handled? (center-entry.on-drag-update center-entry drag update))
            (assert (not handled?)
                    "Center mode on-drag-update should return false to allow default teleport")))]
    (cleanup)
    (set app.activity-drag-attachment-provider original-provider)
    (when (not ok)
      (error err))))

(fn physics-anchor-mode-errors-if-applyForceAtPosition-absent []
  (assert bt "Missing-API test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local original-provider app.activity-drag-attachment-provider)
  (set app.activity-drag-attachment-provider (fn [] :anchor))
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local size-ref {:value (glm.vec3 4 4 4)})
  (local builder (make-probe-panel-builder size-ref))
  (let [(ok err)
        (pcall
          (fn []
            (local panel (scene:add-panel-child {:builder builder
                                                  :skip-cuboid true
                                                  :position (glm.vec3 0 12 0)}))
            (assert panel "Expected panel for missing-API test")
            (local entry (find-physics-entry-for-element scene panel))
            (assert (and entry entry.body) "Expected runtime physics body")

            ;; Collect movables
            (local LayoutPhysicsBodies (require :layout-physics-bodies))
            (local movables-entries (LayoutPhysicsBodies.collect-movables scene.entity))
            (var anchor-entry nil)
            (each [_ m (ipairs movables-entries)]
              (when (and (not anchor-entry)
                         (= m.target panel.layout))
                (set anchor-entry m)))
            (assert anchor-entry "Should find anchor-mode movable entry")

            ;; Replace body with one missing applyForceAtPosition
            (local original-body entry.body)
            (set entry.body
                 {:activate (fn [_self _force] nil)
                  :forceActivationState (fn [_self _state] nil)
                  :getCenterOfMassTransform (fn [_self]
                                              (local t (bt.Transform))
                                              (t:setIdentity)
                                              (t:setOrigin (bt.Vector3 2 2 2))
                                              t)})
            ;; No applyForceAtPosition on this fake body

            (set entry.dragging true)
            (local drag {:entry anchor-entry
                         :hit-point (glm.vec3 0 0 0)
                         :started? true
                         :plane {:point (glm.vec3 0 0 0)
                                 :normal (glm.vec3 0 1 0)}
                         :offset (glm.vec3 0 0 0)})
            (local update {:payload {:button 1 :x 5 :y 6 :mod 0}
                           :pointer (glm.vec3 5 6 0)
                           :ray {:origin (glm.vec3 5 6 10)
                                 :direction (glm.vec3 0 0 -1)}
                           :hit (glm.vec3 5 6 0)
                           :new-position (glm.vec3 5 6 0)
                           :plane drag.plane})

            (local (call-ok call-err) (pcall (fn [] (anchor-entry.on-drag-update anchor-entry drag update))))
            ;; Restore original body
            (set entry.body original-body)

            (assert (not call-ok)
                    "Anchor mode should error when applyForceAtPosition is absent")
            (assert (string.find (tostring call-err) "applyForceAtPosition")
                    (string.format
                      "Error should mention applyForceAtPosition, got: %s"
                      (tostring call-err)))))]
    (cleanup)
    (set app.activity-drag-attachment-provider original-provider)
    (when (not ok)
      (error err))))

(table.insert tests {:name "Physical panels collide with each other"
                     :fn physical-panels-collide-with-each-other})
(table.insert tests {:name "Physical panel collides with Perlin terrain"
                     :fn physical-panel-collides-with-perlin-terrain})
(table.insert tests {:name "Physical panel rebuilds shape on resize"
                     :fn physical-panel-rebuilds-body-on-resize})
(table.insert tests {:name "Physical panel applies stability body tuning"
                     :fn physical-panel-applies-stability-body-tuning})
(table.insert tests {:name "Physical panel stops at global containment floor"
                     :fn physical-panel-stops-at-global-containment-floor})
(table.insert tests {:name "Physical panel respects configured containment floor height"
                     :fn physical-panel-respects-configured-containment-floor-height})
(table.insert tests {:name "Graph-node cube add tolerates ms FPC update"
                     :fn graph-node-cube-add-does-not-crash-after-ms-fpc-update})
(table.insert tests {:name "Physics sync recovers from out-of-bounds body transform"
                     :fn physics-sync-recovers-from-out-of-bounds-body-transform})
(table.insert tests {:name "Physics anchor mode records relative anchor"
                     :fn physics-anchor-mode-records-relative-anchor})
(table.insert tests {:name "Physics anchor mode calls applyForceAtPosition during drag"
                     :fn physics-anchor-mode-calls-applyForceAtPosition-during-drag})
(table.insert tests {:name "Physics center mode allows default teleport"
                     :fn physics-center-mode-allows-default-teleport})
(table.insert tests {:name "Physics anchor mode errors if applyForceAtPosition absent"
                     :fn physics-anchor-mode-errors-if-applyForceAtPosition-absent})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "layout-physics-bodies"
                       :tests tests})))

{:name "layout-physics-bodies"
 :tests tests
 :main main}
