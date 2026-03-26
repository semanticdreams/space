(local tests [])
(local glm (require :glm))
(local Scene (require :scene))
(local PhysicsContainment (require :physics-containment))

(fn vec3= [left right]
  (and (= left.x right.x)
       (= left.y right.y)
       (= left.z right.z)))

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
      (assert (vec3= app.__physics-global-containment.bounds.min (glm.vec3 10 -135 20))
              "Containment should refresh horizontal placement after terrain record replacement")
      (assert (vec3= app.__physics-global-containment.bounds.max (glm.vec3 130 415 60))
              "Containment should refresh size and height after terrain record replacement"))))

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
(table.insert tests {:name "PhysicsContainment automatic bounds follow terrain record replacements"
                     :fn automatic-bounds-follow-terrain-record-replacements})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "physics-containment"
                       :tests tests})))

{:main main}
