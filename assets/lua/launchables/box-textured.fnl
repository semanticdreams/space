(local Helpers (require :launchables-helpers))
(local Persistence (require :scene-panel-persistence))

(local kind "scene-box-textured")
(local restorer-module "launchables/box-textured")

(fn open-panel [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene options.target app.scene)
                       "box-textured requires scene target"))
  (local transform (Persistence.panel-transform-options (or options.panel {})))
  (Helpers.add-box-textured {:scene scene
                             :position transform.position
                             :rotation transform.rotation}))

(fn restore [opts]
  (open-panel opts))

{:name "box-textured"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:scene app.scene}))}
