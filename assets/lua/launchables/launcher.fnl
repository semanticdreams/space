(local LauncherView (require :launcher-view))
(local Persistence (require :hud-panel-persistence))

(local kind "launcher-view-dialog")
(local restorer-module "launchables/launcher")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Launcher requires HUD target"))
  (local panel (or options.panel {}))
  (local placement (Persistence.panel-placement-options panel target))
  (var element nil)
  (set element
       (target:add-panel-child
         {:builder (LauncherView {:title "Launcher"})
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

{:name "Launcher"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:hud app.hud}))}
