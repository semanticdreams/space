(local WorkbenchView (require :repo/workbench-view))
(local Persistence (require :hud-panel-persistence))

(local kind "repo-workbench-dialog")
(local restorer-module "launchables/repository-workbench")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Repository Workbench requires HUD target"))
  (local panel (or options.panel {}))
  (local placement (Persistence.panel-placement-options panel target))
  (var element nil)
  (set element
       (target:add-panel-child
         {:builder (WorkbenchView {:title "Repository Workbench"})
          :location placement.location
          :align-x placement.align-x
          :align-y placement.align-y
          :position placement.position
          :rotation placement.rotation
          :size placement.size
          :persistence {:kind kind
                        :restorer-module restorer-module}
          :builder-options {:on-close (fn [_dialog _button _event]
                                        (when (and element target)
                                          (target:remove-panel-child element)))}}))
  element)

(fn restore [opts]
  (open-panel opts))

{:name "Repository Workbench"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:hud app.hud}))}
