(local tests [])
(local glm (require :glm))
(local bt (require :bt))
(local Scene (require :scene))
(local PhysicsContainment (require :physics-containment))

(fn vec3= [left right]
  (and (= left.x right.x)
       (= left.y right.y)
       (= left.z right.z)))

(fn vec4= [left right]
  (and (= left.x right.x)
       (= left.y right.y)
       (= left.z right.z)
       (= left.w right.w)))

(fn flat-heightfield-record [opts]
  (local options (or opts {}))
  {:id (or options.id "terrain-a")
   :kind "heightfield-terrain"
   :options {:position (or options.position [0 -100 0])
             :rotation (or options.rotation [1 0 0 0])
             :sample-spacing (or options.sample-spacing [20 20])
             :chunk-samples [5 5]
             :default-height (or options.height 0.0)}
   :chunks [{:coord [0 0]
             :size [5 5]
             :heights (icollect [_ _idx (ipairs [1 2 3 4 5
                                                 6 7 8 9 10
                                                 11 12 13 14 15
                                                 16 17 18 19 20
                                                 21 22 23 24 25])]
                        (or options.height 0.0))}]})

(fn collision-object-count []
  (local world (and app.engine app.engine.physics (app.engine.physics:getWorld)))
  (assert world "Physics world is required for containment tests")
  (length (world:getCollisionObjectArray)))

(fn body-center [body]
  (local transform (body:getCenterOfMassTransform))
  (local origin (transform:getOrigin))
  (glm.vec3 origin.x origin.y origin.z))

(fn with-dynamic-box [opts f]
  (assert (and app.engine app.engine.physics) "Physics instance not available for dynamic box test")
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 2 2 2)))
  (local center (or options.center (glm.vec3 0 0 0)))
  (local velocity (or options.velocity (glm.vec3 0 0 0)))
  (local shape (bt.BoxShape (bt.Vector3 (* 0.5 size.x)
                                        (* 0.5 size.y)
                                        (* 0.5 size.z))))
  (local transform (bt.Transform))
  (transform:setIdentity)
  (transform:setOrigin (bt.Vector3 center.x center.y center.z))
  (local motion-state (bt.DefaultMotionState transform))
  (local inertia (bt.Vector3 0 0 0))
  (shape:calculateLocalInertia 1.0 inertia)
  (local info (bt.RigidBodyConstructionInfo 1.0 motion-state shape inertia))
  (local body (bt.RigidBody info))
  (app.engine.physics:addRigidBody body)
  (body:setLinearVelocity (bt.Vector3 velocity.x velocity.y velocity.z))
  (local (ok result)
    (pcall (fn []
             (f body))))
  (app.engine.physics:removeRigidBody body)
  (if ok
      result
      (error result)))

(fn with-scene [scene-opts f]
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-config app.physics-containment-config)
  (var scene nil)
  (local (ok result)
    (pcall
      (fn []
        (set scene (Scene scene-opts))
        (set app.scene scene)
        (set app.layout-root scene.layout-root)
        ;; Activate a slot so content mutations pass the assertion;
        ;; then clear containment config so tests start with a clean slate
        (scene:activate-activity-slot "sandbox")
        (set app.physics-containment-config nil)
        (f scene))))
  (when scene
    (scene:drop))
  (PhysicsContainment.clear)
  (set app.scene original-scene)
  (set app.layout-root original-layout-root)
  (set app.physics-containment-config original-config)
  (if ok
      result
      (error result)))

(fn installs-default-manual-containment-box []
  (PhysicsContainment.clear)
  (local baseline (collision-object-count))
  (assert (PhysicsContainment.ensure-installed {})
          "Expected default containment install to succeed")
  (local installed app.__physics-global-containment)
  (assert installed "Expected installed containment state")
  (assert (= (length installed.planes) 6) "Expected six containment planes")
  (assert (vec3= installed.bounds.min (glm.vec3 -500 -500 -500)))
  (assert (vec3= installed.bounds.max (glm.vec3 500 500 500)))
  (assert (= (collision-object-count) (+ baseline 6))
          "Expected containment install to add six collision objects"))

(fn automatic-terrain-bounds-respect-scene-transform-and-padding []
  (with-scene
    {:position (glm.vec3 50 0 20)
     :rotation (glm.quat 1 0 0 0)}
    (fn [scene]
      (scene:build-default {:terrains [(flat-heightfield-record {:height 0.0})]})
      (assert (PhysicsContainment.ensure-installed {:scene scene})
              "Expected automatic containment install to succeed")
      (local installed app.__physics-global-containment)
      (assert installed "Expected containment state")
      (assert (vec3= installed.bounds.min (glm.vec3 50 -150 20))
              "Expected containment min bounds to include terrain transform and padding")
      (assert (vec3= installed.bounds.max (glm.vec3 130 400 100))
              "Expected containment max bounds to include terrain transform and padding"))))

(fn terrain-change-refresh-debounces-until-latest-deadline []
  (with-scene
    {:position (glm.vec3 0 0 0)
     :rotation (glm.quat 1 0 0 0)}
    (fn [scene]
      (scene:build-default {:terrains []})
      (PhysicsContainment.ensure-installed {:scene scene})
      (assert (vec3= app.__physics-global-containment.bounds.min (glm.vec3 -500 -500 -500)))
      (scene:add-terrain-record (flat-heightfield-record {:height 0.0}))
      (PhysicsContainment.schedule-refresh {:scene scene})
      (app.engine.events.updated:emit 600)
      (PhysicsContainment.schedule-refresh {:scene scene})
      (app.engine.events.updated:emit 500)
      (assert (vec3= app.__physics-global-containment.bounds.min (glm.vec3 -500 -500 -500))
              "Containment should not refresh before the latest debounce deadline")
      (app.engine.events.updated:emit 500)
      (assert (vec3= app.__physics-global-containment.bounds.min (glm.vec3 0 -150 0))
              "Containment should refresh after the latest debounce deadline"))))

(fn automatic-bounds-follow-terrain-transform-changes []
  (with-scene
    {:position (glm.vec3 0 0 0)
     :rotation (glm.quat 1 0 0 0)
     :on-terrains-changed (fn [scene]
                            (PhysicsContainment.schedule-refresh {:scene scene}))}
    (fn [scene]
      (scene:build-default {:terrains [(flat-heightfield-record {:height 0.0})]})
      (assert (PhysicsContainment.ensure-installed {:scene scene}))
      (local terrain-layout (and (. scene.scene-terrains 1)
                                 (. (. scene.scene-terrains 1) :element)
                                 (. (. (. scene.scene-terrains 1) :element) :layout)))
      (assert terrain-layout "Expected terrain layout")
      (terrain-layout:set-position (glm.vec3 25 -80 35))
      (scene:update)
      (app.engine.events.updated:emit 1000)
      (assert (vec3= app.__physics-global-containment.bounds.min (glm.vec3 25 -130 35))
              "Containment should refresh after terrain transform changes"))))

(fn clear-cancels-pending-refresh []
  (with-scene
    {:position (glm.vec3 0 0 0)
     :rotation (glm.quat 1 0 0 0)}
    (fn [scene]
      (scene:build-default {:terrains []})
      (PhysicsContainment.ensure-installed {:scene scene})
      (scene:add-terrain-record (flat-heightfield-record {:height 0.0}))
      (PhysicsContainment.schedule-refresh {:scene scene})
      (PhysicsContainment.clear)
      (app.engine.events.updated:emit 1000)
      (assert (= app.__physics-global-containment nil)
              "Clearing containment should cancel pending refreshes"))))

(fn manual-bounds-block-horizontal-escape []
  (local original-config app.physics-containment-config)
  (PhysicsContainment.clear)
  (set app.physics-containment-config {:mode "manual-bounds"
                                       :bounds {:min [-50 -50 -50]
                                                :max [50 50 50]}})
  (assert (PhysicsContainment.ensure-installed
            {:config app.physics-containment-config})
          "Expected manual containment install to succeed")
  (with-dynamic-box
    {:center (glm.vec3 0 0 0)
     :velocity (glm.vec3 60 0 0)}
    (fn [body]
      (for [_ 1 240]
        (app.engine.physics:update 0))
      (local center (body-center body))
      (assert (< center.x 56)
              (string.format
                "Containment should stop the body near the max-x wall (x=%.3f)"
                center.x))))
  (set app.physics-containment-config original-config))

(fn manual-bounds-block-horizontal-escape-from-negative-side []
  (local original-config app.physics-containment-config)
  (PhysicsContainment.clear)
  (set app.physics-containment-config {:mode "manual-bounds"
                                       :bounds {:min [-50 -50 -50]
                                                :max [50 50 50]}})
  (assert (PhysicsContainment.ensure-installed
            {:config app.physics-containment-config})
          "Expected manual containment install to succeed")
  (with-dynamic-box
    {:center (glm.vec3 0 0 0)
     :velocity (glm.vec3 -60 0 0)}
    (fn [body]
      (for [_ 1 240]
        (app.engine.physics:update 0))
      (local center (body-center body))
      (assert (> center.x -56)
              (string.format
                "Containment should stop the body near the min-x wall (x=%.3f)"
                center.x))))
  (set app.physics-containment-config original-config))

(fn automatic-bounds-follow-terrain-record-replacements []
  (with-scene
    {:position (glm.vec3 0 0 0)
     :rotation (glm.quat 1 0 0 0)
     :on-terrains-changed (fn [scene]
                            (PhysicsContainment.schedule-refresh {:scene scene}))}
    (fn [scene]
      (scene:build-default {:terrains [(flat-heightfield-record {:id "terrain-a"
                                                                 :height 0.0})]})
      (assert (PhysicsContainment.ensure-installed {:scene scene}))
      (scene:replace-terrain-record
        "terrain-a"
        {:id "terrain-a"
         :kind "heightfield-terrain"
         :options {:position [10 -100 20]
                   :rotation [1 0 0 0]
                   :sample-spacing [30 10]
                   :chunk-samples [5 5]
                   :default-height 15.0}
         :chunks [{:coord [0 0]
                   :size [5 5]
                   :heights (icollect [_ _idx (ipairs [1 2 3 4 5
                                                       6 7 8 9 10
                                                       11 12 13 14 15
                                                       16 17 18 19 20
                                                       21 22 23 24 25])]
                              15.0)}]})
      (app.engine.events.updated:emit 1000)
      (local bounds app.__physics-global-containment.bounds)
      (assert (vec3= app.__physics-global-containment.bounds.min (glm.vec3 10 -135 20))
              (string.format
                "Containment should refresh horizontal placement after terrain record replacement (actual min=%.3f,%.3f,%.3f)"
                bounds.min.x
                bounds.min.y
                bounds.min.z))
      (assert (vec3= app.__physics-global-containment.bounds.max (glm.vec3 130 415 60))
              (string.format
                "Containment should refresh size and height after terrain record replacement (actual max=%.3f,%.3f,%.3f)"
                bounds.max.x
                bounds.max.y
                bounds.max.z)))))

(fn serialization-drops-legacy-visualization-color []
  (local normalized
    (PhysicsContainment.normalize-config
      {:mode "manual-bounds"
       :bounds {:min [-10 -20 -30]
                :max [10 20 30]}
       :visualization {:enabled true
                       :color [0.9 0.2 0.1 0.8]}}))
  (local serialized (PhysicsContainment.serialize-config normalized))
  (assert (= normalized.visualization.enabled true)
          "Containment normalization should preserve visualization.enabled")
  (assert (= serialized.visualization.enabled true)
          "Containment serialization should preserve visualization.enabled")
  (assert (= normalized.visualization.color nil)
          "Containment normalization should strip legacy visualization.color")
  (assert (= serialized.visualization.color nil)
          "Containment serialization should not persist visualization.color"))

(fn visualization-uses-theme-color []
  (local original-themes app.themes)
  (local (ok err)
    (pcall
      (fn []
        (PhysicsContainment.clear)
        (var captured-color nil)
        (local expected-color (glm.vec4 0.31 0.62 0.93 0.24))
        (set app.themes
             {:get-active-theme
              (fn []
                {:physics-containment {:visualization {:color expected-color}}})})
        (assert
          (PhysicsContainment.ensure-installed
            {:config {:mode "manual-bounds"
                      :bounds {:min [-10 -20 -30]
                               :max [10 20 30]}}
             :scene {:update (fn [_self])
                     :build-context {:lines {:create-line-batch
                                             (fn [_self params]
                                               (set captured-color params.color)
                                               {:drop (fn [_batch])})}}}})
          "Expected themed containment visualization install to succeed")
        (assert (vec4= captured-color expected-color)
                "Containment visualization should use the active theme color when config color is absent"))))
  (PhysicsContainment.clear)
  (set app.themes original-themes)
  (when (not ok)
    (error err)))

(fn visualization-refreshes-on-theme-change []
  (local original-themes app.themes)
  (local original-scene app.physics-containment-scene)
  (local original-config app.physics-containment-config)
  (local (ok err)
    (pcall
      (fn []
        (PhysicsContainment.clear)
        (var create-colors [])
        (var refreshed-colors [])
        (var active-color (glm.vec4 0.45 0.72 0.95 0.28))
        (set app.themes
             {:get-active-theme
              (fn []
                {:physics-containment {:visualization {:color active-color}}})})
        (assert
          (PhysicsContainment.ensure-installed
            {:config {:mode "manual-bounds"
                      :bounds {:min [-10 -20 -30]
                               :max [10 20 30]}}
             :scene {:update (fn [_self])
                     :build-context {:lines {:create-line-batch
                                             (fn [_self params]
                                               (table.insert create-colors params.color)
                                               {:drop (fn [_batch])
                                                :set-color (fn [_batch color]
                                                             (table.insert refreshed-colors color))})}}}})
          "Expected containment visualization install to succeed")
        (set active-color (glm.vec4 0.14 0.31 0.58 0.42))
        (assert (PhysicsContainment.refresh-visualization
                  {:scene app.physics-containment-scene
                   :config app.physics-containment-config})
                "Expected containment visualization refresh to succeed")
        (assert (= (length create-colors) 2)
                "Containment visualization refresh should rebuild the line batch")
        (assert (vec4= (. create-colors 1) (glm.vec4 0.45 0.72 0.95 0.28))
                "Initial containment visualization should use the first theme color")
        (assert (vec4= (. create-colors 2) (glm.vec4 0.14 0.31 0.58 0.42))
                "Containment visualization refresh should use the new theme color")
        (assert (= (length refreshed-colors) 0)
                "Containment visualization refresh should rebuild instead of mutating the old batch"))))
  (PhysicsContainment.clear)
  (set app.themes original-themes)
  (set app.physics-containment-scene original-scene)
  (set app.physics-containment-config original-config)
  (when (not ok)
    (error err)))

(table.insert tests {:name "PhysicsContainment installs default manual containment box"
                     :fn installs-default-manual-containment-box})
(table.insert tests {:name "PhysicsContainment automatic terrain bounds respect scene transform and padding"
                     :fn automatic-terrain-bounds-respect-scene-transform-and-padding})
(table.insert tests {:name "PhysicsContainment terrain change refresh debounces until latest deadline"
                     :fn terrain-change-refresh-debounces-until-latest-deadline})
(table.insert tests {:name "PhysicsContainment automatic bounds follow terrain transform changes"
                     :fn automatic-bounds-follow-terrain-transform-changes})
(table.insert tests {:name "PhysicsContainment clear cancels pending refresh"
                     :fn clear-cancels-pending-refresh})
(table.insert tests {:name "PhysicsContainment manual bounds block horizontal escape"
                     :fn manual-bounds-block-horizontal-escape})
(table.insert tests {:name "PhysicsContainment manual bounds block horizontal escape from negative side"
                     :fn manual-bounds-block-horizontal-escape-from-negative-side})
(table.insert tests {:name "PhysicsContainment automatic bounds follow terrain record replacements"
                     :fn automatic-bounds-follow-terrain-record-replacements})
(table.insert tests {:name "PhysicsContainment serialization drops legacy visualization color"
                     :fn serialization-drops-legacy-visualization-color})
(table.insert tests {:name "PhysicsContainment visualization uses theme color"
                     :fn visualization-uses-theme-color})
(table.insert tests {:name "PhysicsContainment visualization refreshes on theme change"
                     :fn visualization-refreshes-on-theme-change})

(fn scene-slot-deactivation-retains-slot-state []
  ;; Regression: deactivating the active scene slot must retain the slot itself
  ;; while removing its active physics bodies. The scene surface should be
  ;; left with no active slot and nil entity after deactivation. The physics
  ;; body added by this test must be removed from the Bullet world on
  ;; deactivation, returning collision count to baseline.
  (with-scene
    {:position (glm.vec3 0 0 0)
     :rotation (glm.quat 1 0 0 0)}
    (fn [scene]
      (scene:build-default {:terrains [(flat-heightfield-record {:height 0.0})]})
      (assert scene.entity "Sandbox slot entity must exist after build-default")
      (assert (= scene.active-activity-slot-id "sandbox") "Sandbox must be active")
      (local slot (. scene.activity-slots "sandbox"))
      (assert slot "Sandbox slot must exist after activation")
      (assert slot.visible? "Sandbox slot must be visible while active")
      (set scene.camera {:position (glm.vec3 0 0 50)
                         :rotation (glm.quat 1 0 0 0)})
      (local baseline (collision-object-count))
      (local body-element
        (scene:add-physics-body {:position (glm.vec3 0 0 0)
                                 :size (glm.vec3 4 4 4)}))
      (assert body-element "Expected add-physics-body to create a runtime body")
      (local with-body (collision-object-count))
      (assert (> with-body baseline)
              (string.format
                "Adding a physics body should increase collision objects (baseline=%d with=%d)"
                baseline with-body))
      ;; Explicitly deactivate physics bodies on the entity to verify
      ;; that the Bullet body is removed from the world.
      (local LayoutPhysicsBodies (require :layout-physics-bodies))
      (local body-count-before (collision-object-count))
      (LayoutPhysicsBodies.deactivate scene.entity)
      (local body-count-after (collision-object-count))
      (assert (< body-count-after body-count-before)
              (string.format
                "LayoutPhysicsBodies.deactivate must remove active bodies (before=%d after=%d)"
                body-count-before body-count-after))
      ;; Now deactivate the slot. After deactivation, the slot object and
      ;; its fields must survive, while the scene surface is cleared.
      (scene:deactivate-activity-slot "sandbox")
      (assert (. scene.activity-slots "sandbox")
              "Slot must still be present in the scene after deactivation")
      (assert (not slot.visible?)
              "Slot must be marked invisible after deactivation")
      (assert (= scene.active-activity-slot nil)
              "Scene must have no active slot after deactivation")
      (assert (= scene.entity nil)
              "Scene entity must be nil after slot deactivation"))))
(table.insert tests {:name "Scene slot deactivation retains slot state while removing active bodies"
                     :fn scene-slot-deactivation-retains-slot-state})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "physics-containment"
                       :tests tests})))

{:main main}
