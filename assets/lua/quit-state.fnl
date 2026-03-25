(local State (require :state))
(local Routes (require :state-routes))
(local DefaultConfig (require :state-default-config))

(local KEY
  {:escape 27
   :q (string.byte "q")})

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn QuitState []
  (local QuitCommands
    {:key-down (fn [_ctx payload]
                 (local key (and payload payload.key))
                 (if (= key KEY.escape)
                     (do (set-state :normal) true)
                     (= key KEY.q) (do
                                     (assert app.engine.quit "app.engine.quit binding missing")
                                     (app.engine.quit)
                                     true)
                     true))})
  (State
    {:name :quit
     :routes (DefaultConfig.routes
               {:key-down (Routes.FirstHandlerWins [QuitCommands])})
     :enter DefaultConfig.enter
     :leave DefaultConfig.leave}))

QuitState
