(local fs (require :fs))
(local Units (require :units))
(local UnitManager (require :unit-manager))
(local tempfile (require :tempfile))
(local Activities (require :activities))
(local ExternalUnitService (require :llm/external-unit-mcp/service))

(local tests [])

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "ext-unit-mcp-reload-test-"}))
  (local (ok result) (pcall f handle.path))
  (handle:drop)
  (if ok result (error result)))

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn reset-live-dev-app-state! []
  (tset _G.app :activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.__live_dev_activations 0)
  (set app.active-world-runtime {})
  true)

(fn write-live-dev-unit [dir]
  (local path (fs.join-path dir "live-dev.fnl"))
  (fs.write-file path
    (.. "(fn init []\n"
        "  (local Activities (require :activities))\n"
        "  (when (Activities.activity-registered? \"user-live-dev\")\n"
        "    (Activities.unregister-activity \"user-live-dev\"))\n"
        "  (Activities.register-activity\n"
        "    {:id \"user-live-dev\"\n"
        "     :label \"User Live Dev\"\n"
        "     :activate (fn [_ctx retained]\n"
        "                 (set app.__live_dev_activations (+ app.__live_dev_activations 1))\n"
        "                 (if retained retained {:unit \"user-live-dev\"}))})\n"
        "  true)\n"
        "(fn drop []\n"
        "  (local Activities (require :activities))\n"
        "  (when (Activities.activity-registered? \"user-live-dev\")\n"
        "    (Activities.unregister-activity \"user-live-dev\"))\n"
        "  true)\n"
        "{:init init :drop drop}"))
  path)

(fn register-live-dev-unit [mgr dir path]
  (local unit
    (Units.ModuleUnit
      {:id "user-live-dev"
       :module-name "live-dev"
       :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
       :source :user
       :suppress-run-main? true
       :owned-paths [path]}))
  (mgr:register unit)
  (unit:load {})
  unit)

(fn assert-reload-evidence [result]
  (assert (= result.unit-id "user-live-dev") "reload should return the unit id")
  (assert (= result.reloaded true) "reload should report success")
  (assert result.activity "reload should include activity evidence")
  (assert (= result.activity.active-activity-before "user-live-dev")
          "activity evidence should include active id before reload")
  (assert (= result.activity.active-activity-after "user-live-dev")
          "activity evidence should include active id after reload")
  (assert (= result.activity.reactivation-attempted true)
          "activity evidence should report reactivation attempt")
  (assert (= result.activity.registered-after? true)
          "activity evidence should report registration after reload")
  (assert (= result.activity.has-active-session-after? true)
          "activity evidence should report active session after reload"))

(fn cleanup-live-dev-test! [mgr state]
  (when (Activities.activity-registered? "user-live-dev")
    (Activities.unregister-activity "user-live-dev"))
  (mgr:clear)
  (restore-app-fields! state)
  true)

(fn run-reload-evidence-scenario [dir]
  (local state (snapshot-app-fields [:active-world-runtime
                                     :activity-registry
                                     :activities-changed
                                     :active-activity-id
                                     :__live_dev_activations]))
  (local mgr (UnitManager {}))
  (local path (write-live-dev-unit dir))
  (local (ok result)
    (pcall
      (fn []
        (reset-live-dev-app-state!)
        (register-live-dev-unit mgr dir path)
        (local service (ExternalUnitService.ExternalUnitService {:app {:unit-manager mgr}}))
        (Activities.activate-activity "user-live-dev")
        (assert-reload-evidence (service:reload {:unit_id "user-live-dev"})))))
  (cleanup-live-dev-test! mgr state)
  (if ok result (error result)))

(fn reload-returns-active-activity-reactivation-evidence []
  (with-temp-dir run-reload-evidence-scenario))

(table.insert tests {:name "external-unit-mcp: reload returns active activity reactivation evidence"
                     :fn reload-returns-active-activity-reactivation-evidence})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "external-unit-mcp-reload-evidence"
                     :tests tests}))

{:name "external-unit-mcp-reload-evidence"
 :tests tests
 :main main}
