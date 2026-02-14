(local Helpers (require :launchables-helpers))

{:name "Next App"
 :run (fn []
        (local scene app.scene)
        (local hud app.hud)
        (assert (and scene scene.add-panel-child) "Next App requires app.scene.add-panel-child")
        (assert hud "Next App requires app.hud")
        (scene:add-panel-child {:builder (Helpers.make-next-app-dialog hud)}))}
