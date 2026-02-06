(local Helpers (require :launchables-helpers))

{:name "Sub App One"
 :run (fn []
        (local scene app.scene)
        (local hud app.hud)
        (assert (and scene scene.add-panel-child) "Sub App One requires app.scene.add-panel-child")
        (assert hud "Sub App One requires app.hud")
        (scene:add-panel-child {:builder (Helpers.make-sub-app-one-dialog hud)}))}
