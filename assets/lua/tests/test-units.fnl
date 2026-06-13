(local callbacks (require :callbacks))
(local fennel (require :fennel))
(local fs (require :fs))
(local tempfile (require :tempfile))
(local FileWatch (require :file-watch))
(local HotReload (require :hot-reload))
(local runtime (require :runtime))
(local CanvasModes (require :canvas-modes))
(local Units (require :units))

(local tests [])

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "units-test-"}))
  (local path handle.path)
  (local (ok result) (pcall f path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn with-temp-module-search-path [dir f]
  (local original-fennel-path fennel.path)
  (local original-package-path package.path)
  (local fennel-prefix (.. dir "/?.fnl;" dir "/?/init.fnl"))
  (local package-prefix (.. dir "/?.lua"))
  (set fennel.path (.. fennel-prefix ";" original-fennel-path))
  (set package.path (.. package-prefix ";" original-package-path))
  (local (ok result) (pcall f))
  (set fennel.path original-fennel-path)
  (set package.path original-package-path)
  (if ok
      result
      (error result)))

(fn clear-loaded-modules! [module-names]
  (each [_ module-name (ipairs module-names)]
    (set (. package.loaded module-name) nil))
  true)

(fn wait-until [predicate opts]
  (local options (or opts {}))
  (callbacks.run-loop {:sleep-ms (or options.sleep-ms 10)
                       :timeout-ms (or options.timeout-ms 2000)
                       :until predicate}))

;; Fast unit tests for file-watch, module units, hot-reload controller, and canvas-mode registry.

(fn file-watch-detects-basic-events []
  (with-temp-dir
    (fn [dir]
      (local watcher (FileWatch.FileWatcher {}))
      (local path (fs.join-path dir "watched.fnl"))
      (var saw-write? false)
      (var saw-delete? false)
      (watcher:add-watch dir false)
      (watcher:start)
      (fs.write-file path "(local x 1)\n")
      (fs.append-file path "(local y 2)\n")
      (assert (wait-until
                (fn []
                  (each [_ event (ipairs (watcher:poll))]
                    (when (and (= event.path path)
                               (or (= event.action "add")
                                   (= event.action "modified")))
                      (set saw-write? true)))
                  saw-write?))
              "Expected file-watch to observe write event")
      (fs.remove path)
      (assert (wait-until
                (fn []
                  (each [_ event (ipairs (watcher:poll))]
                    (when (and (= event.path path)
                               (= event.action "delete"))
                      (set saw-delete? true)))
                  saw-delete?))
              "Expected file-watch to observe delete event")
      (watcher:drop)
      true)))

(fn module-unit-reload-applies-edited-implementation []
  (with-temp-dir
    (fn [dir]
      (with-temp-module-search-path
        dir
        (fn []
          (local module-names ["tmp_reload_impl"
                               "tmp_reload_unit"])
          (clear-loaded-modules! module-names)
          (fs.write-file (fs.join-path dir "tmp_reload_impl.fnl")
                         "{:version \"v1\"}\n")
          (fs.write-file (fs.join-path dir "tmp_reload_unit.fnl")
                         (.. "(local TempImpl (require :tmp_reload_impl))\n"
                             "(fn load-child! []\n"
                             "  (set app.__tmp-reload-version TempImpl.version)\n"
                             "  true)\n"
                             "(fn unload-child! [] true)\n"
                             "(fn snapshot-child! [] app.__tmp-reload-version)\n"
                             "(fn restore-child! [state]\n"
                             "  (set app.__tmp-reload-restored state)\n"
                             "  true)\n"
                             "{:load-child! load-child!\n"
                             " :unload-child! unload-child!\n"
                             " :snapshot-child! snapshot-child!\n"
                             " :restore-child! restore-child!}\n"))
          (local previous-engine (and app app.engine))
          (set app.engine {:now-ms (fn [_self]
                                     (math.floor (* (os.clock) 1000.0)))})
          (local unit
            (Units.ModuleUnit
              {:id "tmp-reload"
               :module-name "tmp_reload_unit"
               :owned-paths [dir]
               :load-export "load-child!"
               :unload-export "unload-child!"
               :snapshot-export "snapshot-child!"
               :restore-export "restore-child!"}))
          (local controller
            (HotReload.HotReloadController
              {:unit unit
               :watch-paths [dir]
               :preserve-modules ["hot-reload" "tests.test-units" "units"]}))
          (local (ok result)
            (pcall
              (fn []
                (unit:load)
                (assert (= app.__tmp-reload-version "v1")
                        "Expected initial module unit load to use v1")
                (fs.write-file (fs.join-path dir "tmp_reload_impl.fnl")
                               "{:version \"v2\"}\n")
                (assert (controller:reload-now!
                          {:changes [{:path (fs.join-path dir "tmp_reload_impl.fnl")
                                      :action "modified"}]})
                        "Expected module unit reload to succeed")
                (assert (= app.__tmp-reload-version "v2")
                        "Expected module unit reload to apply updated dependency code")
                (assert (= app.__tmp-reload-restored "v1")
                        "Expected module unit reload to restore prior snapshot state")
                true)))
          (controller:drop)
          (clear-loaded-modules! module-names)
          (set app.__tmp-reload-version nil)
          (set app.__tmp-reload-restored nil)
          (set app.engine previous-engine)
          (if ok
              result
              (error result)))))))

(fn hot-reload-clears-deleted-modules-by-known-source-path []
  (with-temp-dir
    (fn [dir]
      (with-temp-module-search-path
        dir
        (fn []
          (local module-names ["tmp_delete_dep"
                               "tmp_delete_unit"])
          (clear-loaded-modules! module-names)
          (local dep-path (fs.join-path dir "tmp_delete_dep.fnl"))
          (local unit-path (fs.join-path dir "tmp_delete_unit.fnl"))
          (fs.write-file dep-path
                         "{:value \"with-dep\"}\n")
          (fs.write-file unit-path
                         (.. "(local TempDep (require :tmp_delete_dep))\n"
                             "(fn load-child! []\n"
                             "  (set app.__tmp-delete-value TempDep.value)\n"
                             "  true)\n"
                             "(fn unload-child! [] true)\n"
                             "(fn snapshot-child! [] app.__tmp-delete-value)\n"
                             "(fn restore-child! [state]\n"
                             "  (set app.__tmp-delete-restored state)\n"
                             "  true)\n"
                             "{:load-child! load-child!\n"
                             " :unload-child! unload-child!\n"
                             " :snapshot-child! snapshot-child!\n"
                             " :restore-child! restore-child!}\n"))
          (local previous-engine (and app app.engine))
          (set app.engine {:now-ms (fn [_self]
                                     (math.floor (* (os.clock) 1000.0)))})
          (local unit
            (Units.ModuleUnit
              {:id "tmp-delete"
               :module-name "tmp_delete_unit"
               :owned-paths [dir]
               :load-export "load-child!"
               :unload-export "unload-child!"
               :snapshot-export "snapshot-child!"
               :restore-export "restore-child!"}))
          (local controller
            (HotReload.HotReloadController
              {:unit unit
               :watch-paths [dir]
               :preserve-modules ["hot-reload" "tests.test-units" "units"]}))
          (local (ok result)
            (pcall
              (fn []
                (unit:load)
                (assert (= app.__tmp-delete-value "with-dep")
                        "Expected initial module load to use dependency")
                (assert (. package.loaded "tmp_delete_dep")
                        "Expected dependency module to be loaded")
                (fs.write-file unit-path
                               (.. "(fn load-child! []\n"
                                   "  (set app.__tmp-delete-value \"without-dep\")\n"
                                   "  true)\n"
                                   "(fn unload-child! [] true)\n"
                                   "(fn snapshot-child! [] app.__tmp-delete-value)\n"
                                   "(fn restore-child! [state]\n"
                                   "  (set app.__tmp-delete-restored state)\n"
                                   "  true)\n"
                                   "{:load-child! load-child!\n"
                                   " :unload-child! unload-child!\n"
                                   " :snapshot-child! snapshot-child!\n"
                                   " :restore-child! restore-child!}\n"))
                (fs.remove dep-path)
                (assert (controller:reload-now!
                          {:changes [{:path dep-path
                                      :action "delete"}
                                     {:path unit-path
                                      :action "modified"}]})
                        "Expected reload after dependency deletion to succeed")
                (assert (= app.__tmp-delete-value "without-dep")
                        "Expected reloaded unit to use updated implementation")
                (assert (= app.__tmp-delete-restored "with-dep")
                        "Expected delete reload to restore prior snapshot state")
                (assert (= (. package.loaded "tmp_delete_dep") nil)
                        "Expected deleted module to be cleared from package.loaded")
                true)))
          (controller:drop)
          (clear-loaded-modules! module-names)
          (set app.__tmp-delete-value nil)
          (set app.__tmp-delete-restored nil)
          (set app.engine previous-engine)
          (if ok
              result
              (error result)))))))

(fn canvas-modes-require-registration-before-activation []
  (local previous-registry app.canvas-mode-registry)
  (local previous-root-actions app.canvas-mode-root-actions)
  (local previous-selection-actions app.canvas-mode-selection-actions)
  (local previous-left-dock-builder app.canvas-mode-left-dock-builder)
  (local previous-command-hints-provider app.canvas-mode-command-hints-provider)
  (local previous-delete-selection app.canvas-mode-delete-selection)
  (local previous-activate-focused app.canvas-mode-activate-focused)
  (local previous-drawing-enabled app.canvas-mode-drawing-enabled?)
  (local previous-target-enabled app.canvas-mode-target-enabled?)
  (local previous-mode-update app.canvas-mode-update)
  (set app.canvas-mode-registry nil)
  (CanvasModes.clear-mode-runtime-hooks!)
  (local (resolve-ok _resolve-err)
    (pcall CanvasModes.resolve "graph"))
  (assert (not resolve-ok)
          "CanvasModes.resolve should reject built-in ids before they are registered")
  (CanvasModes.register-mode
    {:id "graph"
     :label "Graph"
     :icon "account_tree"
     :button-name "graph-canvas-mode"
     :show-in-sidebar? true
     :activate (fn [ctx]
                 (ctx:set-root-actions! (fn [_context] []))
                 {:mode-id "graph"})
     :deactivate (fn [_ctx _session]
                   true)})
  (CanvasModes.activate-mode "graph")
  (assert (= (CanvasModes.active-mode-id) "graph")
          "CanvasModes.activate-mode should activate a registered mode")
  (CanvasModes.unregister-mode "graph")
  (local (activate-ok _activate-err)
    (pcall CanvasModes.activate-mode "graph"))
  (set app.canvas-mode-registry previous-registry)
  (set app.canvas-mode-root-actions previous-root-actions)
  (set app.canvas-mode-selection-actions previous-selection-actions)
  (set app.canvas-mode-left-dock-builder previous-left-dock-builder)
  (set app.canvas-mode-command-hints-provider previous-command-hints-provider)
  (set app.canvas-mode-delete-selection previous-delete-selection)
  (set app.canvas-mode-activate-focused previous-activate-focused)
  (set app.canvas-mode-drawing-enabled? previous-drawing-enabled)
  (set app.canvas-mode-target-enabled? previous-target-enabled)
  (set app.canvas-mode-update previous-mode-update)
  (assert (not activate-ok)
          "CanvasModes.activate-mode should reject modes once they are unregistered"))

(table.insert tests {:name "file-watch detects write/delete events"
                     :fn file-watch-detects-basic-events})
(table.insert tests {:name "module unit reload applies edited implementation"
                     :fn module-unit-reload-applies-edited-implementation})
(table.insert tests {:name "hot reload clears deleted modules by known source path"
                     :fn hot-reload-clears-deleted-modules-by-known-source-path})
(table.insert tests {:name "canvas modes require registration before activation"
                     :fn canvas-modes-require-registration-before-activation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "units"
                       :tests tests})))

{:name "units"
 :tests tests
 :main main}
