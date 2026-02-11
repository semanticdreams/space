(local Helpers (require :launchables-helpers))

{:name "Fennel Interpreter"
 :run (fn []
        (local scene app.scene)
        (assert (and scene scene.add-panel-child) "Fennel Interpreter launchable requires app.scene.add-panel-child")
        (scene:add-panel-child {:builder (Helpers.make-fennel-interpreter-dialog {})}))}
