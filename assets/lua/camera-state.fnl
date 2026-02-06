(local StateBase (require :state-base))
(local glm (require :glm))

(local KEY
  {:escape 27
   :f (string.byte "f")
   :zero (string.byte "0")})

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn reset-camera! []
  (assert app.camera "camera-state expects app.camera")
  (assert app.camera.set-position "camera-state expects app.camera:set-position")
  (assert app.camera.set-rotation "camera-state expects app.camera:set-rotation")
  (app.camera:set-position (glm.vec3 0 0 0))
  (app.camera:set-rotation (glm.quat 1 0 0 0)))

(fn CameraState []
  (local base (StateBase.make-state {:name :camera}))
  (local base-on-key-down base.on-key-down)
  (StateBase.make-state
    {:name :camera
     :on-key-down (fn [payload]
                    (local key (and payload payload.key))
                    (if (= key KEY.escape)
                        (do (set-state :normal) true)
                        (= key KEY.f)
                        (do (set-state :fpc) true)
                        (= key KEY.zero)
                        (do (reset-camera!) true)
                        (base-on-key-down payload)))}))

CameraState
