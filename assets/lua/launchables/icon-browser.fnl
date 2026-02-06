(local Helpers (require :launchables-helpers))

{:name "Icon Browser"
 :run (fn []
        (assert (and app.hud app.hud.add-panel-child) "Icon Browser requires app.hud.add-panel-child")
        (app.hud:add-panel-child {:builder (Helpers.make-icon-browser-dialog {})}))}
