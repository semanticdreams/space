(local MorphView (require :morph-view))
(local Persistence (require :hud-panel-persistence))

(local kind "morph-view-dialog")
(local restorer-module "launchables/morphs")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Morphs launchable requires HUD target"))
  (local placement (Persistence.panel-placement-options options.panel target))
  (target:add-panel-child {:builder (MorphView {})
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

{:name "Morphs"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:hud app.hud}))}
