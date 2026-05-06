(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))

(fn hud-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (icollect [_ relative (ipairs ["hud-unit.fnl"
                                 "hud.fnl"
                                 "hud-layout.fnl"
                                 "hud-panel-persistence.fnl"
                                 "hud-control-panel.fnl"
                                 "hud-control-panel-layout.fnl"
                                 "hud-status-panel.fnl"
                                 "hud-status-panel-layout.fnl"
                                 "hud-command-hints.fnl"])]
    (fs.join-path lua-root relative)))

(fn clear-overlay! []
  (when (and app.hud app.active-world-hud-overlay)
    (app.hud:remove-overlay-child app.active-world-hud-overlay)
    (set app.active-world-hud-overlay nil))
  true)

(fn current-hud-module []
  (local module (require :hud))
  (assert (= (type module) :table) "hud-unit requires :hud to return a table")
  (assert (= (type module.Hud) :function) "hud-unit requires :hud.Hud")
  module)

(fn create-focus-scope! []
  (assert app.focus "HudUnit.load requires app.focus")
  (when app.hud-focus-scope
    (app.focus:detach app.hud-focus-scope)
    (set app.hud-focus-scope nil))
  (local scope
    (app.focus:create-scope {:name "hud"
                             :directional-traversal-boundary? true}))
  (app.focus:attach scope (app.focus:get-root-scope))
  (set app.hud-focus-scope scope)
  scope)

(fn create-hud! []
  (assert (not app.hud) "HudUnit.load requires app.hud to be nil")
  (local HudModule (current-hud-module))
  (local hud
    (HudModule.Hud {:scene app.scene
                    :focus-manager app.focus
                    :focus-scope (create-focus-scope!)
                    :icons app.icons
                    :states app.states
                    :movables app.movables}))
  (set app.hud hud)
  hud)

(fn bind-hud! []
  (when app.bind-hud-runtime
    (app.bind-hud-runtime))
  true)

(fn load-hud! []
  (create-hud!)
  (bind-hud!))

(fn unload-hud! []
  (clear-overlay!)
  (set app.active-world-hud-contrib nil)
  (when app.hud
    (set app.hud.world-hud-contrib nil)
    (app.hud:drop)
    (set app.hud nil))
  (set app.hud-focus-scope nil)
  true)

(fn snapshot-hud! []
  (and app.hud
       app.hud.capture-state
       (app.hud:capture-state)))

(fn restore-hud! [state]
  (bind-hud!)
  (when (and state app.hud app.hud.restore-state)
    (app.hud:restore-state state))
  true)

{:hud-owned-paths hud-owned-paths
 :load-hud! load-hud!
 :unload-hud! unload-hud!
 :snapshot-hud! snapshot-hud!
 :restore-hud! restore-hud!}
