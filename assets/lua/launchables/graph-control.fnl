(local GraphViewControlView (require :graph-view-control-view))
(local PanelUtils (require :target-panel-utils))

(local kind "graph-control-view-dialog")
(local restorer-module "launchables/graph-control")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Graph Control requires target"))
  (local placement (PanelUtils.panel-placement-options target options.panel))
  (target:add-panel-child {:builder (GraphViewControlView {})
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

{:name "Graph Control"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:target (or app.canvas app.hud)}))}
