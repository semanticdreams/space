(local tests [])
(local glm (require :glm))
(local ActivityCameraState (require :activity-camera-state))

(fn captures-and-restores-camera-state []
  (local camera (ActivityCameraState.camera-from-state
                  {:position [1 2 3]}
                  {:position (glm.vec3 0 0 100)}))
  (assert (= camera.position.x 1)
          (.. "Expected camera position x=1, got " (tostring camera.position.x)))
  (assert (= camera.position.y 2)
          (.. "Expected camera position y=2, got " (tostring camera.position.y)))
  (assert (= camera.position.z 3)
          (.. "Expected camera position z=3, got " (tostring camera.position.z)))
  (local captured (ActivityCameraState.capture-camera camera))
  (assert (= (. captured.position 1) 1))
  (assert (= (. captured.position 2) 2))
  (assert (= (. captured.position 3) 3))
  (ActivityCameraState.restore-camera! camera {:position [9 8 7]})
  (assert (= camera.position.x 9))
  (assert (= camera.position.y 8))
  (assert (= camera.position.z 7))
  (camera:drop))

(table.insert tests {:name "Activity camera state captures and restores"
                     :fn captures-and-restores-camera-state})

(fn camera-from-state-uses-defaults-when-state-missing []
  (local camera (ActivityCameraState.camera-from-state
                  {}
                  {:position (glm.vec3 5 6 7)}))
  (assert (= camera.position.x 5))
  (assert (= camera.position.y 6))
  (assert (= camera.position.z 7))
  (camera:drop))

(table.insert tests {:name "Camera from state uses defaults when state is empty"
                     :fn camera-from-state-uses-defaults-when-state-missing})

(fn camera-from-state-handles-rotation []
  (local camera (ActivityCameraState.camera-from-state
                  {:position [1 2 3]
                   :rotation [0 0 0 1]}
                  {:position (glm.vec3 0 0 0)}))
  (assert camera.rotation "Camera from state should set rotation")
  (camera:drop))

(table.insert tests {:name "Camera from state handles rotation"
                     :fn camera-from-state-handles-rotation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-camera-state"
                       :tests tests})))

{:name "activity-camera-state"
 :tests tests
 :main main}
