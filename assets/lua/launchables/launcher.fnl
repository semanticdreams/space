(local LauncherView (require :launcher-view))

{:name "Launcher"
 :run (fn []
        (assert (and app app.hud app.hud.add-panel-child)
                "Launcher requires app.hud:add-panel-child")
        (var element nil)
        (set element
             (app.hud:add-panel-child
               {:builder
                (LauncherView {:title "Launcher"})
                :builder-options {:on-close (fn [_dialog _button _event]
                                              (when (and element app.hud)
                                                (app.hud:remove-panel-child element)))}}))
        element)}
