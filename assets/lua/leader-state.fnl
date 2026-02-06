(local StateBase (require :state-base))
(local LauncherView (require :launcher-view))

(local KEY
  {:escape 27
   :q (string.byte "q")
   :c (string.byte "c")
   :p (string.byte "p")})

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn open-launcher []
  (assert (and app app.hud app.hud.add-panel-child)
          "Leader state launcher requires app.hud:add-panel-child")
  (var element nil)
  (set element
       (app.hud:add-panel-child
         {:builder
          (LauncherView {:title "Launcher"})
          :builder-options {:on-close (fn [_dialog _button _event]
                                        (when (and element app.hud)
                                          (app.hud:remove-panel-child element)))}}))
  element)

(fn LeaderState []
  (StateBase.make-state
    {:name :leader
     :on-key-down (fn [payload]
                    (local key (and payload payload.key))
                    (if (= key KEY.escape)
                        (do (set-state :normal) true)
                        (= key KEY.c) (do (set-state :camera) true)
                        (= key KEY.q) (do (set-state :quit) true)
                        (= key KEY.p) (do
                                        (open-launcher)
                                        true)
                        true))}))

LeaderState
