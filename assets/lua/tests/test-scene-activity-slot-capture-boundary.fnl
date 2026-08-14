(local glm (require :glm))
(local Scene (require :scene))
(local Camera (require :camera))
(local AppProjection (require :app-projection))

(local tests [])

(fn make-scene []
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local scene (Scene {:camera camera}))
  {:camera camera
   :scene scene})

(fn drop-fixture [fixture]
  (fixture.scene:drop)
  (fixture.camera:drop))

(fn with-restored-app-fields [keys f]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs keys)]
    (set (. app key) (. snapshot key)))
  (if ok
      result
      (error result)))

(fn inactive-retained-scene-slot-captures-while-foreign-active []
  (with-restored-app-fields
    [:active-activity-id :activity-registry]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local fixture (make-scene))
      (local scene fixture.scene)
      (local graph-slot (scene:ensure-activity-slot "graph"))
      (local board-slot (scene:ensure-activity-slot "board"))
      (set graph-slot.scene-state (ActivitySceneState.empty-state))
      (set graph-slot.scene-state.terrains [{:id "graph-terrain"}])
      (scene:activate-activity-slot "board")
      (set app.activity-registry {:active-activity-id "board"})
      (set app.active-activity-id "board")
      (local captured (scene:capture-activity-slot-state "graph"))
      (assert (= (length captured.terrains) 1)
              "Inactive retained graph scene slot should be captured while board is active")
      (assert (= (. (. captured.terrains 1) :id) "graph-terrain")
              "Inactive capture should read the retained graph slot state")
      (assert (= (. scene.activity-slots "graph") graph-slot)
              "Capture should not replace the retained graph slot")
      (assert (= scene.active-activity-slot board-slot)
              "Capture should not change the active board slot")
      (drop-fixture fixture))))

(fn capture-missing-scene-slot-fails-without-creating []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local (ok err) (pcall (fn [] (scene:capture-activity-slot-state "missing"))))
  (assert (not ok)
          "Capturing a missing scene activity slot should fail")
  (assert (string.find (tostring err)
                       "Scene.capture-activity-slot-state no slot for activity missing"
                       1
                       true)
          "Missing scene slot capture should report an explicit error")
  (assert (= (scene:activity-slot "missing") nil)
          "Capture must not create missing scene activity slots")
  (drop-fixture fixture))

(table.insert tests {:name "Scene inactive retained slot capture works under foreign active owner"
                     :fn inactive-retained-scene-slot-captures-while-foreign-active})
(table.insert tests {:name "Scene capture missing activity slot fails without creating"
                     :fn capture-missing-scene-slot-fails-without-creating})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-activity-slot-capture-boundary"
                       :tests tests})))

{:name "scene-activity-slot-capture-boundary"
 :tests tests
 :main main}
