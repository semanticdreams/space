(local DefaultDialog (require :default-dialog))
(local RipgrepView (require :ripgrep-view))
(local Persistence (require :hud-panel-persistence))

(local kind "fs-ripgrep-dialog")
(local restorer-module "graph/view/views/fs-ripgrep-dialog")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Fs ripgrep dialog requires HUD target"))
  (local panel (or options.panel {}))
  (local path
    (or options.path
        (Persistence.assert-string-field panel :path
                                         "fs-ripgrep-dialog requires string :path")))
  (local label (or options.label path))
  (local placement (Persistence.panel-placement-options panel))
  (target:add-panel-child {:builder (DefaultDialog {:title (.. "Ripgrep: " label)
                                                    :child (RipgrepView {:path path})})
                           :location placement.location
                           :align-x placement.align-x
                           :align-y placement.align-y
                           :position placement.position
                           :rotation placement.rotation
                           :size placement.size
                           :builder-options {:path path}
                           :persistence {:kind kind
                                         :path path
                                         :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore}
