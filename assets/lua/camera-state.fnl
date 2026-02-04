(local StateBase (require :state-base))

(local KEY
  {:escape 27
   :f (string.byte "f")})

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

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
                        (base-on-key-down payload)))}))

CameraState
