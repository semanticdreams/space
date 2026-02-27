(local TetrisView (require :tetris-view))
(local Persistence (require :scene-panel-persistence))

(local kind "scene-tetris-dialog")
(local restorer-module "launchables/tetris")

(fn open-panel [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene options.target app.scene)
                       "Tetris launchable requires scene target"))
  (assert scene.add-panel-child "Tetris launchable target requires :add-panel-child")
  (local transform (Persistence.panel-transform-options (or options.panel {})))
  (scene:add-panel-child {:builder (TetrisView.TetrisDialog {})
                          :position transform.position
                          :rotation transform.rotation
                          :skip-cuboid true
                          :persistence {:kind kind
                                        :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "Tetris"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:scene app.scene}))}
