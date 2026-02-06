(local TetrisView (require :tetris-view))

{:name "Tetris"
 :run (fn []
        (local scene app.scene)
        (assert (and scene scene.add-panel-child) "Tetris launchable requires app.scene.add-panel-child")
        (scene:add-panel-child {:builder (TetrisView.TetrisDialog {})
                                :skip-cuboid true}))}
