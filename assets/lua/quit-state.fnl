(local StateBase (require :state-base))

(local KEY
  {:escape 27
   :q (string.byte "q")})

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn QuitState []
  (StateBase.make-state
    {:name :quit
     :on-key-down (fn [payload]
                    (local key (and payload payload.key))
                    (if (= key KEY.escape)
                        (do (set-state :normal) true)
                        (= key KEY.q) (do
                                        (assert app.engine.quit "app.engine.quit binding missing")
                                        (app.engine.quit)
                                        true)
                        true))}))

QuitState
