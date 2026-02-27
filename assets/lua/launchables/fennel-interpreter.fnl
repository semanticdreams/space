(local Helpers (require :launchables-helpers))
(local Persistence (require :scene-panel-persistence))

(local kind "scene-fennel-interpreter-dialog")
(local restorer-module "launchables/fennel-interpreter")

(fn open-panel [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene options.target app.scene)
                       "Fennel Interpreter launchable requires scene target"))
  (assert scene.add-panel-child "Fennel Interpreter target requires :add-panel-child")
  (local transform (Persistence.panel-transform-options (or options.panel {})))
  (scene:add-panel-child {:builder (Helpers.make-fennel-interpreter-dialog {})
                          :position transform.position
                          :rotation transform.rotation
                          :persistence {:kind kind
                                        :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "Fennel Interpreter"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:scene app.scene}))}
