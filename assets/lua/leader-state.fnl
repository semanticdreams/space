(local State (require :state))
(local Routes (require :state-routes))
(local DefaultConfig (require :state-default-config))
(local LauncherLaunchable (require :launchables/launcher))

(local KEY
  {:escape 27
   :q (string.byte "q")
   :c (string.byte "c")
   :p (string.byte "p")})

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn open-launcher []
  (LauncherLaunchable.open-panel {:hud app.hud}))

(fn LeaderState []
  (local LeaderCommands
    {:key-down (fn [_ctx payload]
                 (local key (and payload payload.key))
                 (if (= key KEY.escape)
                     (do (set-state :normal) true)
                     (= key KEY.c) (do (set-state :camera) true)
                     (= key KEY.q) (do (set-state :quit) true)
                     (= key KEY.p) (do
                                     (open-launcher)
                                     true)
                     true))})
  (State
    {:name :leader
     :routes (DefaultConfig.routes
               {:key-down (Routes.FirstHandlerWins [LeaderCommands])})
     :enter DefaultConfig.enter
     :leave DefaultConfig.leave}))

LeaderState
