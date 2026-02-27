(local Helpers (require :launchables-helpers))
(local Persistence (require :scene-panel-persistence))

(local kind "scene-next-app-dialog")
(local restorer-module "launchables/next-app")

(fn open-panel [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene options.target app.scene)
                       "Next App requires scene target"))
  (local hud (assert (or options.hud app.hud)
                     "Next App requires app.hud"))
  (assert scene.add-panel-child "Next App target requires :add-panel-child")
  (local transform (Persistence.panel-transform-options (or options.panel {})))
  (scene:add-panel-child {:builder (Helpers.make-next-app-dialog hud)
                          :position transform.position
                          :rotation transform.rotation
                          :persistence {:kind kind
                                        :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "Next App"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:scene app.scene
                     :hud app.hud}))}
