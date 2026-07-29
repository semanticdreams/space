(local tests [])
(local CameraAnimation (require :camera-animation))

;; snap sets value to target immediately
(fn snap-set-to-target []
  (local channel (CameraAnimation.scalar-channel {:value 0 :target 0 :smoothing-rate 5}))
  (channel:set-target 100)
  (let [v (channel:snap 100)]
    (assert (= v 100) "snap must return the new value"))
  (assert (= (channel:value) 100)
          "snap must set value to target")
  true)

;; set-target changes target but not current value
(fn set-target-does-not-move-value []
  (local channel (CameraAnimation.scalar-channel {:value 0 :target 0 :smoothing-rate 5}))
  (channel:set-target 100)
  (assert (= (channel:value) 0)
          "set-target must not change current value")
  true)

;; update approaches target monotonically
(fn update-approaches-target []
  (local channel (CameraAnimation.scalar-channel {:value 0 :target 100 :smoothing-rate 5}))
  (local first (channel:update 0.1))
  (assert (> first 0) "update must move value toward target")
  (assert (< first 100) "update must not overshoot target")
  (local second (channel:update 0.1))
  (assert (> second first) "successive updates must make monotonic progress")
  (assert (< second 100) "update must still not overshoot")
  true)

;; snap to value when distance is within epsilon
(fn snap-at-tiny-distance []
  (local channel (CameraAnimation.scalar-channel {:value 99.999999 :target 100 :smoothing-rate 5}))
  ;; distance is 1e-6, below the 1e-5 epsilon
  (local result (channel:update 0.016))
  (assert (= result 100) "must snap to target when distance < 1e-5")
  true)

;; deterministic fixed-delta output
(fn deterministic-output []
  (var a nil)
  (var b nil)
  (do
    (local channel (CameraAnimation.scalar-channel {:value 0 :target 100 :smoothing-rate 5}))
    (set a (channel:update 0.1)))
  (do
    (local channel (CameraAnimation.scalar-channel {:value 0 :target 100 :smoothing-rate 5}))
    (set b (channel:update 0.1)))
  (assert (= a b) "scalar-channel must produce deterministic output")
  true)

;; error on non-number value
(fn errors-on-non-number-value []
  (local status
    (pcall CameraAnimation.scalar-channel {:value "not-a-number" :target 0 :smoothing-rate 1}))
  (assert (not status) "must error on non-number value")
  true)

;; error on non-number target
(fn errors-on-non-number-target []
  (local status
    (pcall CameraAnimation.scalar-channel {:value 0 :target nil :smoothing-rate 1}))
  (assert (not status) "must error on non-number target")
  true)

;; error on non-number delta
(fn errors-on-non-number-delta []
  (local channel (CameraAnimation.scalar-channel {:value 0 :target 0 :smoothing-rate 5}))
  (local status (pcall channel.update channel "not-a-number"))
  (assert (not status) "must error on non-number delta")
  true)

(table.insert tests {:name "snap sets value to target" :fn snap-set-to-target})
(table.insert tests {:name "set-target does not move value" :fn set-target-does-not-move-value})
(table.insert tests {:name "update approaches target monotonically" :fn update-approaches-target})
(table.insert tests {:name "snap at tiny distance" :fn snap-at-tiny-distance})
(table.insert tests {:name "deterministic fixed-delta output" :fn deterministic-output})
(table.insert tests {:name "errors on non-number value" :fn errors-on-non-number-value})
(table.insert tests {:name "errors on non-number target" :fn errors-on-non-number-target})
(table.insert tests {:name "errors on non-number delta" :fn errors-on-non-number-delta})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "camera-animation"
                       :tests tests})))

{:name "camera-animation"
 :tests tests
 :main main}
