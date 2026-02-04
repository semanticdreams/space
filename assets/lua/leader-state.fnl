(local StateBase (require :state-base))

(local KEY
  {:escape 27
   :q (string.byte "q")
   :c (string.byte "c")})

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn LeaderState []
  (StateBase.make-state
    {:name :leader
     :on-key-down (fn [payload]
                    (local key (and payload payload.key))
                    (if (= key KEY.escape)
                        (do (set-state :normal) true)
                        (= key KEY.c) (do (set-state :camera) true)
                        (= key KEY.q) (do (set-state :quit) true)
                        true))}))

LeaderState
