(local callbacks (require :callbacks))
(local AppBootstrap (require :app-bootstrap))
(local fennel (require :fennel))
(local fs (require :fs))
(local tempfile (require :tempfile))
(local FileWatch (require :file-watch))
(local HotReload (require :hot-reload))
(local LauncherLaunchable (require :launchables/launcher))
(local runtime (require :runtime))
(local Units (require :units))

(local tests [])

(fn require-main! []
  (set (. package.loaded "main") nil)
  (require :main))

(fn install-renderer-stub! []
  (var skybox-state {})
  (var background-state {})
  (set app.renderers {:skybox {:set-state (fn [_self state]
                                            (set skybox-state state)
                                            true)
                               :get-state (fn [_self]
                                            skybox-state)}
                      :set-background-state (fn [_self state]
                                              (set background-state state)
                                              true)
                      :get-background-state (fn [_self]
                                              background-state)
                      :apply-theme (fn [_self _theme] true)
                      :prerender-sub-apps (fn [_self] true)
                      :draw-target (fn [_self _target _opts] true)
                      :update (fn [_self] true)
                      :on-viewport-changed (fn [_self _viewport] true)
                      :drop (fn [_self] true)})
  app.renderers)

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

(fn count-searcher-occurrences [target]
  (var count 0)
  (each [_ searcher (ipairs package.searchers)]
    (when (= searcher target)
      (set count (+ count 1))))
  count)

(fn wait-until [predicate opts]
  (local options (or opts {}))
  (callbacks.run-loop {:sleep-ms (or options.sleep-ms 10)
                       :timeout-ms (or options.timeout-ms 2000)
                       :until predicate}))

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

(fn full-app-root-reload-roundtrips-active-world []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local DebugLog (require :debug-log))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-config app.hot-reload-config)
      (local original-controller app.hot-reload-controller)
      (local original-worlds-dir app.worlds-dir)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [_opts]
             (install-renderer-stub!)))
      (set app.hot-reload-controller nil)
      (set app.hot-reload-config {:enabled true
                                  :watch-paths [watch-root]
                                  :preserve-modules ["app-bootstrap"
                                                     "hot-reload"
                                                     "tests.test-units"
                                                     "units"]})
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init-app!))
            (DebugLog.log "test" "root reload marker")
            (local before-debug-log (fs.read-file DebugLog.log-path))
            (assert (string.find before-debug-log "root reload marker" 1 true)
                    "Expected debug log marker before root reload")
            (assert package.__space_fennel_cache_searcher
                    "Expected installed fennel cache searcher before root reload")
            (assert (= (count-searcher-occurrences package.__space_fennel_cache_searcher) 1)
                    "Expected exactly one installed fennel cache searcher before root reload")
            (local created-world
              (app.world-manager:create-home-world {:activate? false}))
            (local before-id created-world.id)
            (assert (app.world-manager:activate-world-id before-id)
                    "Expected to activate created world before reload")
            (local controller
              (or app.hot-reload-controller
                  (HotReload.AppRootController {:watch-paths [watch-root]
                                                :preserve-modules ["app-bootstrap"
                                                                   "hot-reload"
                                                                   "tests.test-units"
                                                                   "units"]})))
            (assert (controller:reload-now! {:changes [{:path (fs.join-path runtime.assets-path "lua" "main.fnl")
                                                        :action "modified"}]})
                    "Expected root hot reload to succeed")
            (assert app.world-manager "Expected app.world-manager after reload")
            (assert (= (app.world-manager:active-world-id) before-id)
                    "Expected active world id to roundtrip through full-app reload")
            (local after-debug-log (fs.read-file DebugLog.log-path))
            (assert (string.find after-debug-log "root reload marker" 1 true)
                    "Expected root reload to preserve debug.log history")
            (assert package.__space_fennel_cache_searcher
                    "Expected installed fennel cache searcher after root reload")
            (assert (= (count-searcher-occurrences package.__space_fennel_cache_searcher) 1)
                    "Expected exactly one installed fennel cache searcher after root reload")
            (when (and controller controller.drop)
              (controller:drop))
            (set app.hot-reload-controller nil)
            true)))
      (when app.hot-reload-controller
        (app.hot-reload-controller:drop)
        (set app.hot-reload-controller nil))
      (when (= (type (. (require :main) :drop-app!)) :function)
        ((. (require :main) :drop-app!)))
      (set AppBootstrap.init-renderers original-init-renderers)
      (set app.hot-reload-config original-config)
      (set app.hot-reload-controller original-controller)
      (set app.worlds-dir original-worlds-dir)
      (if ok
          result
          (error result)))))

(fn drop-app-cleans-hot-reload-controller-and-callback []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-config app.hot-reload-config)
      (set AppBootstrap.init-renderers
           (fn [_opts]
             (install-renderer-stub!)))
      (set app.hot-reload-config {:enabled true
                                  :watch-paths [(fs.join-path runtime.assets-path "lua")]
                                  :preserve-modules ["app-bootstrap"
                                                     "hot-reload"
                                                     "tests.test-units"
                                                     "units"]})
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init-app!))
            (assert app.hot-reload-controller
                    "Expected app.hot-reload-controller after init")
            (assert app.hot-reload-callback-id
                    "Expected app.hot-reload-callback-id after init")
            ((. Main :drop-app!))
            (assert (= app.hot-reload-controller nil)
                    "Expected drop-app! to clear app.hot-reload-controller")
            (assert (= app.hot-reload-callback-id nil)
                    "Expected drop-app! to clear app.hot-reload-callback-id")
            true)))
      (set AppBootstrap.init-renderers original-init-renderers)
      (set app.hot-reload-config original-config)
      (if ok
          result
          (error result)))))

(fn hud-unit-reload-roundtrips-panel-state []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (set AppBootstrap.init-renderers
           (fn [_opts]
             (install-renderer-stub!)))
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init-app!))
            (assert app.hud-unit "Expected app.hud-unit after app init")
            (assert app.hud "Expected app.hud after app init")
            (local old-hud app.hud)
            (local old-scope app.hud-focus-scope)
            (LauncherLaunchable.open-panel
              {:hud app.hud
               :panel {:layer "float"
                       :position [2 3 0]
                       :rotation [1 0 0 0]
                       :size [12 8 0]}})
            (app.hud:update)
            (local before-state (app.hud:capture-state))
            (local before-panel (. before-state.panels 1))
            (assert before-panel "Expected HUD panel before reload")
            (assert (app.hud-unit:reload {})
                    "Expected HUD unit reload to succeed")
            (assert app.hud "Expected app.hud after HUD unit reload")
            (assert (not (= app.hud old-hud))
                    "HUD unit reload should replace the HUD instance")
            (assert (not (= app.hud-focus-scope old-scope))
                    "HUD unit reload should replace the HUD focus scope")
            (app.hud:update)
            (local after-state (app.hud:capture-state))
            (local after-panel (. after-state.panels 1))
            (assert after-panel "Expected HUD panel after reload")
            (assert (= (length (or after-state.panels []))
                       (length (or before-state.panels [])))
                    "Expected HUD unit reload to preserve panel count")
            (assert (= after-panel.kind before-panel.kind)
                    "Expected HUD unit reload to preserve panel kind")
            (assert (= after-panel.layer before-panel.layer)
                    "Expected HUD unit reload to preserve panel layer")
            (assert (= after-panel.restorer-module before-panel.restorer-module)
                    "Expected HUD unit reload to preserve panel restorer module")
            (assert (= (fennel.view after-panel.relative-size)
                       (fennel.view before-panel.relative-size))
                    "Expected HUD unit reload to preserve panel size")
            (assert after-panel.relative-position
                    "Expected HUD unit reload to preserve panel position state")
            true)))
      (when (and (= (type (. (require :main) :drop-app!)) :function)
                 app.engine)
        ((. (require :main) :drop-app!)))
      (set AppBootstrap.init-renderers original-init-renderers)
      (if ok
          result
          (error result)))))

(fn hot-reload-routes-hud-file-changes-to-hud-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [_opts]
             (install-renderer-stub!)))
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init-app!))
            (assert app.hud-unit "Expected app.hud-unit after app init")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init-app!"
                 :unload-export "drop-app!"
                 :snapshot-export "snapshot-app!"
                 :restore-export "restore-app!"}))
            (local controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                             [app.hud-unit])
                 :root-unit-id "app-root"
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-units"
                                    "units"]}))
            (local old-hud app.hud)
            (local old-scope app.hud-focus-scope)
            (local old-world-manager app.world-manager)
            (LauncherLaunchable.open-panel
              {:hud app.hud
               :panel {:layer "float"
                       :position [4 5 0]
                       :rotation [1 0 0 0]
                       :size [14 9 0]}})
            (app.hud:update)
            (local before-state (app.hud:capture-state))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root "hud.fnl")
                                  :action "modified"}]})
                    "Expected HUD file change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "hud")
                    "Expected HUD file change to target hud unit")
            (assert app.hud "Expected app.hud after routed reload")
            (assert (not (= app.hud old-hud))
                    "Expected routed HUD reload to replace app.hud")
            (assert (not (= app.hud-focus-scope old-scope))
                    "Expected routed HUD reload to replace HUD focus scope")
            (assert (= app.world-manager old-world-manager)
                    "Expected routed HUD reload to avoid reloading app root")
            (app.hud:update)
            (local after-state (app.hud:capture-state))
            (assert (= (length (or after-state.panels []))
                       (length (or before-state.panels [])))
                    "Expected routed HUD reload to preserve panel count")
            (controller:drop)
            true)))
      (when (and (= (type (. (require :main) :drop-app!)) :function)
                 app.engine)
        ((. (require :main) :drop-app!)))
      (set AppBootstrap.init-renderers original-init-renderers)
      (if ok
          result
          (error result)))))

(fn canvas-unit-reload-roundtrips-surface-state []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (set AppBootstrap.init-renderers
           (fn [_opts]
             (install-renderer-stub!)))
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init-app!))
            (assert app.canvas-unit "Expected app.canvas-unit after app init")
            (assert app.canvas "Expected app.canvas after app init")
            (assert app.canvas-controls "Expected app.canvas-controls after app init")
            (assert app.graph-view "Expected app.graph-view after app init")
            (assert app.object-selector "Expected app.object-selector after app init")
            (local old-canvas app.canvas)
            (local old-scope app.canvas-focus-scope)
            (local old-controls app.canvas-controls)
            (local old-graph-view app.graph-view)
            (local old-object-selector app.object-selector)
            (local old-graph app.graph)
            (local old-drawing-controller app.drawing-controller)
            (local old-world-manager app.world-manager)
            (LauncherLaunchable.open-panel
              {:target app.canvas
               :panel {:layer "float"
                       :position [6 7 0]
                       :rotation [1 0 0 0]
                       :size [16 10 0]}})
            (app.set-active-canvas-feature "drawing")
            (app.set-active-interaction-surface :canvas
                                                {:sync-canvas-visibility true})
            (app.canvas:update)
            (local before-state (app.canvas:capture-state))
            (local before-panel (. before-state.panels 1))
            (assert before-panel "Expected canvas panel before reload")
            (assert (app.canvas-unit:reload {})
                    "Expected canvas unit reload to succeed")
            (assert app.canvas "Expected app.canvas after canvas unit reload")
            (assert (not (= app.canvas old-canvas))
                    "Canvas unit reload should replace the canvas instance")
            (assert (not (= app.canvas-focus-scope old-scope))
                    "Canvas unit reload should replace the canvas focus scope")
            (assert (not (= app.canvas-controls old-controls))
                    "Canvas unit reload should replace canvas controls")
            (assert (not (= app.graph-view old-graph-view))
                    "Canvas unit reload should replace graph view")
            (assert (not (= app.object-selector old-object-selector))
                    "Canvas unit reload should replace object selector")
            (assert (= app.graph old-graph)
                    "Canvas unit reload should preserve graph state owner")
            (assert (= app.drawing-controller old-drawing-controller)
                    "Canvas unit reload should preserve drawing controller")
            (assert (= app.world-manager old-world-manager)
                    "Canvas unit reload should avoid reloading world manager")
            (assert (= app.active-canvas-feature "drawing")
                    "Canvas unit reload should preserve active canvas feature")
            (assert (= app.active-interaction-surface :canvas)
                    "Canvas unit reload should preserve active interaction surface")
            (assert (= app.canvas-visible? true)
                    "Canvas unit reload should preserve canvas visibility")
            (app.canvas:update)
            (local after-state (app.canvas:capture-state))
            (local after-panel (. after-state.panels 1))
            (assert after-panel "Expected canvas panel after reload")
            (assert (= (length (or after-state.panels []))
                       (length (or before-state.panels [])))
                    "Expected canvas unit reload to preserve panel count")
            (assert (= after-panel.kind before-panel.kind)
                    "Expected canvas unit reload to preserve panel kind")
            (assert (= after-panel.restorer-module before-panel.restorer-module)
                    "Expected canvas unit reload to preserve panel restorer module")
            true)))
      (when (and (= (type (. (require :main) :drop-app!)) :function)
                 app.engine)
        ((. (require :main) :drop-app!)))
      (set AppBootstrap.init-renderers original-init-renderers)
      (if ok
          result
          (error result)))))

(fn hot-reload-routes-canvas-file-changes-to-canvas-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [_opts]
             (install-renderer-stub!)))
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init-app!))
            (assert app.canvas-unit "Expected app.canvas-unit after app init")
            (assert app.hud-unit "Expected app.hud-unit after app init")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init-app!"
                 :unload-export "drop-app!"
                 :snapshot-export "snapshot-app!"
                 :restore-export "restore-app!"}))
            (local controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                             [app.canvas-unit app.hud-unit])
                 :root-unit-id "app-root"
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-units"
                                    "units"]}))
            (local old-canvas app.canvas)
            (local old-world-manager app.world-manager)
            (local old-graph app.graph)
            (LauncherLaunchable.open-panel
              {:target app.canvas
               :panel {:layer "float"
                       :position [8 9 0]
                       :rotation [1 0 0 0]
                       :size [18 11 0]}})
            (app.set-active-canvas-feature "drawing")
            (app.set-active-interaction-surface :canvas
                                                {:sync-canvas-visibility true})
            (app.canvas:update)
            (local before-state (app.canvas:capture-state))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root "canvas.fnl")
                                  :action "modified"}]})
                    "Expected canvas file change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "canvas")
                    "Expected canvas file change to target canvas unit")
            (assert app.canvas "Expected app.canvas after routed canvas reload")
            (assert (not (= app.canvas old-canvas))
                    "Expected routed canvas reload to replace app.canvas")
            (assert (= app.world-manager old-world-manager)
                    "Expected routed canvas reload to avoid reloading app root")
            (assert (= app.graph old-graph)
                    "Expected routed canvas reload to preserve graph owner")
            (assert (= app.active-canvas-feature "drawing")
                    "Expected routed canvas reload to preserve active canvas feature")
            (assert (= app.active-interaction-surface :canvas)
                    "Expected routed canvas reload to preserve interaction surface")
            (app.canvas:update)
            (local after-state (app.canvas:capture-state))
            (assert (= (length (or after-state.panels []))
                       (length (or before-state.panels [])))
                    "Expected routed canvas reload to preserve panel count")
            (controller:drop)
            true)))
      (when (and (= (type (. (require :main) :drop-app!)) :function)
                 app.engine)
        ((. (require :main) :drop-app!)))
      (set AppBootstrap.init-renderers original-init-renderers)
      (if ok
          result
          (error result)))))

(fn hot-reload-routes-canvas-shell-state-file-changes-to-canvas-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [_opts]
             (install-renderer-stub!)))
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init-app!))
            (assert app.canvas-unit "Expected app.canvas-unit after app init")
            (assert app.hud-unit "Expected app.hud-unit after app init")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init-app!"
                 :unload-export "drop-app!"
                 :snapshot-export "snapshot-app!"
                 :restore-export "restore-app!"}))
            (local controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                             [app.canvas-unit app.hud-unit])
                 :root-unit-id "app-root"
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-units"
                                    "units"]}))
            (local old-canvas app.canvas)
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root
                                                      "home-world-canvas-shell-state.fnl")
                                  :action "modified"}]})
                    "Expected canvas shell state change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "canvas")
                    "Expected canvas shell state change to target canvas unit")
            (assert app.canvas "Expected app.canvas after routed canvas helper reload")
            (assert (not (= app.canvas old-canvas))
                    "Expected routed canvas helper reload to replace app.canvas")
            (controller:drop)
            true)))
      (when (and (= (type (. (require :main) :drop-app!)) :function)
                 app.engine)
        ((. (require :main) :drop-app!)))
      (set AppBootstrap.init-renderers original-init-renderers)
      (if ok
          result
          (error result)))))

(table.insert tests {:name "file-watch detects write/delete events"
                     :fn file-watch-detects-basic-events})
(table.insert tests {:name "module unit reload applies edited implementation"
                     :fn module-unit-reload-applies-edited-implementation})
(table.insert tests {:name "hot reload clears deleted modules by known source path"
                     :fn hot-reload-clears-deleted-modules-by-known-source-path})
(table.insert tests {:name "full app root reload roundtrips active world"
                     :fn full-app-root-reload-roundtrips-active-world})
(table.insert tests {:name "drop app cleans hot reload controller and callback"
                     :fn drop-app-cleans-hot-reload-controller-and-callback})
(table.insert tests {:name "HUD unit reload roundtrips panel state"
                     :fn hud-unit-reload-roundtrips-panel-state})
(table.insert tests {:name "hot reload routes hud file changes to hud unit"
                     :fn hot-reload-routes-hud-file-changes-to-hud-unit})
(table.insert tests {:name "canvas unit reload roundtrips surface state"
                     :fn canvas-unit-reload-roundtrips-surface-state})
(table.insert tests {:name "hot reload routes canvas file changes to canvas unit"
                     :fn hot-reload-routes-canvas-file-changes-to-canvas-unit})
(table.insert tests {:name "hot reload routes canvas shell state file changes to canvas unit"
                     :fn hot-reload-routes-canvas-shell-state-file-changes-to-canvas-unit})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "units"
                       :tests tests})))

{:name "units"
 :tests tests
 :main main}
