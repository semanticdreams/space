(local Helpers (require :launchables-helpers))
(local Persistence (require :hud-panel-persistence))

(local kind "icon-browser-dialog")
(local restorer-module "launchables/icon-browser")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Icon Browser requires HUD target"))
  (local placement (Persistence.panel-placement-options options.panel))
  (target:add-panel-child {:builder (Helpers.make-icon-browser-dialog {})
                           :location placement.location
                           :align-x placement.align-x
                           :align-y placement.align-y
                           :position placement.position
                           :rotation placement.rotation
                           :size placement.size
                           :persistence {:kind kind
                                         :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "Icon Browser"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:hud app.hud}))}
