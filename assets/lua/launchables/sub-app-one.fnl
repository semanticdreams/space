(local Helpers (require :launchables-helpers))
(local Persistence (require :scene-panel-persistence))

(local kind "scene-sub-app-one-dialog")
(local restorer-module "launchables/sub-app-one")

(fn open-panel [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene options.target app.scene)
                       "Sub App One requires scene target"))
  (local hud (assert (or options.hud app.hud)
                     "Sub App One requires app.hud"))
  (assert scene.add-panel-child "Sub App One target requires :add-panel-child")
  (local transform (Persistence.panel-transform-options (or options.panel {})))
  (scene:add-panel-child {:builder (Helpers.make-sub-app-one-dialog hud)
                          :position transform.position
                          :rotation transform.rotation
                          :persistence {:kind kind
                                        :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "Sub App One"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:scene app.scene
                     :hud app.hud}))}
