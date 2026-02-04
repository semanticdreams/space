(local glm (require :glm))
(local _ (require :main))
(local {: FirstPersonControls} (require :first-person-controls))
(local Camera (require :camera))

(local tests [])

(fn reset-env []
  (reset-engine-events)
  (app.set-viewport {:width 100 :height 100})
  (when app.first-person-controls
    (app.first-person-controls:drop)
    (set app.first-person-controls nil)))

(fn keyboard-move-updates-camera-position []
  (reset-env)
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local controls (FirstPersonControls {:camera camera}))
  (controls:on-key-down {:key 44})
  (controls:update 0.5)
  (assert (< camera.position.z 0))
  (controls:on-key-up {:key 44})
  (controls:update 0.5)
  (controls:drop))

(fn scroll-wheel-zooms-camera []
  (reset-env)
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local controls (FirstPersonControls {:camera camera}))
  (local original-screen-ray app.screen-pos-ray)
  (set app.screen-pos-ray (fn [_ _]
                                   {:origin (glm.vec3 0 0 0)
                                    :direction (glm.vec3 0 0 -1)}))
  (controls:on-mouse-wheel {:x 0 :y 1})
  (controls:update 0.016)
  (assert (< camera.position.z 0))
  (set app.screen-pos-ray original-screen-ray)
  (controls:drop))

(table.insert tests {:name "First-person controls move forward on key press" :fn keyboard-move-updates-camera-position})
(table.insert tests {:name "Mouse wheel drives camera zoom" :fn scroll-wheel-zooms-camera})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "first-person-controls"
                       :tests tests})))

{:name "first-person-controls"
 :tests tests
 :main main}
