(local Helpers (require :launchables-helpers))

{:name "Terminal"
 :run (fn []
        (local scene app.scene)
        (assert (and scene scene.add-panel-child) "Terminal launchable requires app.scene.add-panel-child")
        (scene:add-panel-child {:builder (Helpers.make-terminal-dialog {})}))}
