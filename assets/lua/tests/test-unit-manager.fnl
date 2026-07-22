(local Units (require :units))
(local UnitManager (require :unit-manager))
(local Main (require :main))
(local fs (require :fs))
(local tempfile (require :tempfile))

(local tests [])

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "unit-manager-test-"}))
  (local path handle.path)
  (local (ok result) (pcall f path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn unit-manager-register-lists-and-unregisters []
  (local manager (UnitManager {}))
  (var loaded-count 0)
  (var unloaded-count 0)
  (local unit
    (Units.Unit {:id "test-unit"
                 :load (fn [_ctx]
                         (set loaded-count (+ loaded-count 1)))
                 :unload (fn [_ctx]
                           (set unloaded-count (+ unloaded-count 1)))}))
  (assert (= (manager:count) 0) "manager should start empty")
  (manager:register unit)
  (unit:load {})
  (assert (= (manager:count) 1) "manager should have 1 unit")
  (assert (= (manager:get "test-unit") unit) "get should return registered unit")
  (local units (manager:list))
  (assert (= (length units) 1) "list should return 1 unit")
  (assert (= (. units 1) unit) "list should contain the unit")
  (assert (= loaded-count 1) "load should have been called")
  (manager:unregister "test-unit")
  (assert (= (manager:count) 0) "manager should be empty after unregister")
  (assert (= unloaded-count 1) "unregister should call unload when unit was loaded")
  (assert (= (manager:get "test-unit") nil) "get should return nil after unregister"))

(fn unit-manager-rejects-duplicate-id []
  (local manager (UnitManager {}))
  (local unit-a (Units.Unit {:id "dup" :load (fn [_] true) :unload (fn [_] true)}))
  (local unit-b (Units.Unit {:id "dup" :load (fn [_] true) :unload (fn [_] true)}))
  (manager:register unit-a)
  (local (ok err) (pcall manager.register manager unit-b))
  (assert (not ok) "should reject duplicate id")
  (assert (string.find err "already registered") "error should mention already registered"))

(fn unit-manager-reload-unit-runs-full-lifecycle []
  (local manager (UnitManager {}))
  (var load-count 0)
  (var unload-count 0)
  (var snapshot-called? false)
  (var restore-value nil)
  (local unit
    (Units.Unit {:id "reload-target"
                 :load (fn [_ctx]
                         (set load-count (+ load-count 1)))
                 :unload (fn [_ctx]
                           (set unload-count (+ unload-count 1)))
                 :snapshot (fn [_ctx]
                             (set snapshot-called? true)
                             "snap-val")
                 :restore (fn [state _ctx]
                            (set restore-value state)
                            true)}))
  (manager:register unit)
  (manager:reload-unit "reload-target" {:reload-ctx 42})
  (assert (= load-count 1) "reload should call load once")
  (assert (= unload-count 1) "reload should call unload once")
  (assert snapshot-called? "reload should call snapshot")
  (assert (= restore-value "snap-val") "reload should restore snapshot"))

(fn unit-manager-clear-unloads-all-in-reverse-order []
  (local manager (UnitManager {}))
  (var order [])
  (local unit-a (Units.Unit {:id "a"
                              :unload (fn [_] (table.insert order :a) true)
                              :load (fn [_] true)}))
  (local unit-b (Units.Unit {:id "b"
                              :unload (fn [_] (table.insert order :b) true)
                              :load (fn [_] true)}))
  (local unit-c (Units.Unit {:id "c"
                              :unload (fn [_] (table.insert order :c) true)
                              :load (fn [_] true)}))
  (manager:register unit-a)
  (manager:register unit-b)
  (manager:register unit-c)
  (unit-a:load {})
  (unit-b:load {})
  (unit-c:load {})
  (assert (= (manager:count) 3))
  (manager:clear)
  (assert (= (manager:count) 0) "clear should remove all")
  (assert (= (length order) 3) "clear should unload all")
  (assert (= (. order 1) :c) "clear should unload in reverse insertion order")
  (assert (= (. order 2) :b) "clear should unload in reverse insertion order")
  (assert (= (. order 3) :a) "clear should unload in reverse insertion order"))

(fn unit-manager-clear-empty-is-noop []
  (local manager (UnitManager {}))
  (manager:clear)
  (assert (= (manager:count) 0) "clear on empty should be safe"))

(fn source-unit-loads-and-runs-inline-fennel []
  (local source
    (.. "(fn init []\n"
        "  (set app.__source-test-value \"hello from source\")\n"
        "  true)\n"
        "(fn drop []\n"
        "  (set app.__source-test-value \"cleaned\")\n"
        "  true)\n"
        "{:init init\n"
        " :drop drop}"))
  (set app.__source-test-value nil)
  (local unit (Units.SourceUnit {:id "source-test"
                                  :source source}))
  (unit:load)
  (assert (= app.__source-test-value "hello from source")
          "SourceUnit load should execute source code")
  (unit:unload)
  (assert (= app.__source-test-value "cleaned")
          "SourceUnit unload should call drop export")
  (set app.__source-test-value nil))

(fn source-unit-snapshot-and-restore []
  (local source
    (.. "(local value 10)\n"
        "(fn init []\n"
        "  (set app.__snap-value value)\n"
        "  true)\n"
        "(fn drop [] true)\n"
        "(fn snapshot []\n"
        "  (.. \"snap-\" (tostring value)))\n"
        "(fn restore [state]\n"
        "  (set app.__restored-state state)\n"
        "  true)\n"
        "{:init init\n"
        " :drop drop\n"
        " :snapshot snapshot\n"
        " :restore restore}"))
  (set app.__snap-value nil)
  (set app.__restored-state nil)
  (local unit (Units.SourceUnit {:id "source-snap"
                                  :source source
                                  :snapshot-export "snapshot"
                                  :restore-export "restore"}))
  (unit:load)
  (assert (= app.__snap-value 10) "load should execute source")
  (local state (unit:snapshot))
  (assert (= state "snap-10") "snapshot should return value from source")
  (unit:restore state)
  (assert (= app.__restored-state "snap-10") "restore should pass state to export")
  (unit:unload)
  (set app.__snap-value nil)
  (set app.__restored-state nil))

(fn source-unit-reload-roundtrips []
  (local source
    (.. "(fn init []\n"
        "  (set app.__reload-val (or app.__reload-val 0))\n"
        "  (set app.__reload-val (+ app.__reload-val 1))\n"
        "  true)\n"
        "(fn drop [] true)\n"
        "(fn snapshot []\n"
        "  (.. \"v\" (tostring app.__reload-val)))\n"
        "(fn restore [state]\n"
        "  (set app.__reload-restored state)\n"
        "  true)\n"
        "{:init init\n"
        " :drop drop\n"
        " :snapshot snapshot\n"
        " :restore restore}"))
  (set app.__reload-val nil)
  (set app.__reload-restored nil)
  (local unit (Units.SourceUnit {:id "source-reload"
                                  :source source
                                  :snapshot-export "snapshot"
                                  :restore-export "restore"}))
  (unit:load)
  (assert (= app.__reload-val 1) "first load should set val to 1")
  (unit:reload)
  (assert (= app.__reload-val 2) "after reload load-phase should re-execute source incrementing val")
  (assert (= app.__reload-restored "v1") "restore should receive snapshot from before reload")
  (unit:unload)
  (set app.__reload-val nil)
  (set app.__reload-restored nil))

(fn source-unit-optional-snapshot-restore []
  "SourceUnit should work without snapshot/restore exports"
  (local source
    (.. "(fn init []\n"
        "  (set app.__opt-val \"loaded\")\n"
        "  true)\n"
        "(fn drop []\n"
        "  (set app.__opt-val \"dropped\")\n"
        "  true)\n"
        "{:init init\n"
        " :drop drop}"))
  (set app.__opt-val nil)
  (local unit (Units.SourceUnit {:id "source-optional"
                                  :source source}))
  (unit:load)
  (assert (= app.__opt-val "loaded"))
  (local state (unit:snapshot))
  (assert (= state nil) "snapshot without export should return nil")
  (unit:reload)
  (assert (= app.__opt-val "loaded") "reload without snapshot/restore should work")
  (unit:unload)
  (set app.__opt-val nil))

(fn module-unit-respects-module-paths []
  (with-temp-dir
    (fn [dir]
      (local old-fennel-path (. (require :fennel) :path))
      (fs.write-file (fs.join-path dir "custom-module.fnl")
                     (.. "(fn init []\n"
                         "  (set app.__custom-val \"works\")\n"
                         "  true)\n"
                         "(fn drop []\n"
                         "  (set app.__custom-val nil)\n"
                         "  true)\n"
                         "{:init init\n"
                         " :drop drop}"))
      (set app.__custom-val nil)
      (local fennel-module-prefix (.. dir "/?.fnl;" dir "/?/init.fnl"))
      (local (ok err)
        (pcall
          (fn []
            (local unit
              (Units.ModuleUnit {:id "custom-module"
                                 :module-name "custom-module"
                                 :module-paths fennel-module-prefix
                                 :load-export "init"
                                 :unload-export "drop"
                                 :suppress-run-main? false}))
            (unit:load)
            (assert (= app.__custom-val "works")
                    "ModuleUnit with module-paths should find module in custom dir")
            (unit:unload)
            (assert (= app.__custom-val nil) "unload should clear custom val"))))
      (tset (require :fennel) :path old-fennel-path)
      (set app.__custom-val nil)
      (when (not ok)
        (error err)))))

(fn unit-registry-survives-clear-and-reuse []
  "After clear, the same manager can be reused for new units"
  (local manager (UnitManager {}))
  (var load-a-count 0)
  (var load-b-count 0)
  (local unit-a (Units.Unit {:id "a"
                              :load (fn [_] (set load-a-count (+ load-a-count 1)))
                              :unload (fn [_] true)}))
  (manager:register unit-a)
  (assert (= (manager:count) 1))
  (manager:clear)
  (assert (= (manager:count) 0))
  (local unit-b (Units.Unit {:id "b"
                              :load (fn [_] (set load-b-count (+ load-b-count 1)))
                              :unload (fn [_] true)}))
  (manager:register unit-b)
  (assert (= (manager:count) 1) "manager should accept new units after clear")
  (assert (= (manager:get "a") nil) "unit a should be gone")
  (assert (= (manager:get "b") unit-b) "unit b should be registered"))

(fn unit-manager-list-returns-insertion-order []
  (local manager (UnitManager {}))
  (local a (Units.Unit {:id "z-first" :load (fn [_] true) :unload (fn [_] true)}))
  (local b (Units.Unit {:id "a-second" :load (fn [_] true) :unload (fn [_] true)}))
  (manager:register a)
  (manager:register b)
  (local units (manager:list))
  (assert (= (length units) 2))
  (assert (= (. (. units 1) :id) "z-first") "first registered should be first in list")
  (assert (= (. (. units 2) :id) "a-second") "second registered should be second in list"))

(table.insert tests {:name "unit-manager register lists and unregisters"
                     :fn unit-manager-register-lists-and-unregisters})
(table.insert tests {:name "unit-manager rejects duplicate id"
                     :fn unit-manager-rejects-duplicate-id})
(table.insert tests {:name "unit-manager reload-unit runs full lifecycle"
                     :fn unit-manager-reload-unit-runs-full-lifecycle})
(table.insert tests {:name "unit-manager clear unloads all in reverse order"
                     :fn unit-manager-clear-unloads-all-in-reverse-order})
(table.insert tests {:name "unit-manager clear empty is noop"
                     :fn unit-manager-clear-empty-is-noop})
(table.insert tests {:name "SourceUnit loads and runs inline fennel"
                     :fn source-unit-loads-and-runs-inline-fennel})
(table.insert tests {:name "SourceUnit snapshot and restore"
                     :fn source-unit-snapshot-and-restore})
(table.insert tests {:name "SourceUnit reload roundtrips"
                     :fn source-unit-reload-roundtrips})
(table.insert tests {:name "SourceUnit optional snapshot/restore"
                     :fn source-unit-optional-snapshot-restore})
(table.insert tests {:name "ModuleUnit respects module-paths"
                     :fn module-unit-respects-module-paths})
(table.insert tests {:name "unit registry survives clear and reuse"
                     :fn unit-registry-survives-clear-and-reuse})
(table.insert tests {:name "unit-manager list returns insertion order"
                     :fn unit-manager-list-returns-insertion-order})

(fn user-code-directory-scanner-loads-top-level-and-subdir-init-fnl []
  (with-temp-dir
    (fn [dir]
      (local old-fennel-path (. (require :fennel) :path))
      (fs.create-dirs (fs.join-path dir "beta"))
      (fs.write-file (fs.join-path dir "alpha.fnl")
                     (.. "(fn init [] (set app.__alpha-loaded true) true)\n"
                         "(fn drop [] (set app.__alpha-loaded false) true)\n"
                         "{:init init :drop drop}"))
      (fs.write-file (fs.join-path dir "beta" "init.fnl")
                     (.. "(fn init [] (set app.__beta-init-loaded true) true)\n"
                         "(fn drop [] (set app.__beta-init-loaded false) true)\n"
                         "{:init init :drop drop}"))
      ;; File inside subdir that is NOT init.fnl — should not be a separate unit
      (fs.write-file (fs.join-path dir "beta" "helper.fnl")
                     "(fn init [] (set app.__beta-helper-loaded true) true) {:init init}")
      ;; Dotted filename — should be skipped
      (fs.write-file (fs.join-path dir "bad.name.fnl")
                     "(fn init [] (set app.__bad-loaded true) true) {:init init}")
      (set app.__alpha-loaded nil)
      (set app.__beta-init-loaded nil)
      (set app.__beta-helper-loaded nil)
      (set app.__bad-loaded nil)
      (local (ok err)
        (pcall
          (fn []
            (set app.unit-manager (or app.unit-manager (UnitManager {})))
            (local original-code-dir app.code-dir)
            (set app.code-dir dir)
            (Main.ensure-user-code-units!)
            (set app.code-dir original-code-dir)
            (assert app.__alpha-loaded "top-level alpha.fnl should be loaded")
            (assert app.__beta-init-loaded "subdir beta/init.fnl should be loaded")
            (assert (not app.__beta-helper-loaded) "subdir helper.fnl should not be a separate unit")
            (assert (not app.__bad-loaded) "dotted filename should be skipped")
            (assert (= (app.unit-manager:count) 2) "should register exactly 2 user units")
            (app.unit-manager:clear)
            (assert (not app.__alpha-loaded) "alpha should be unloaded on clear")
            (assert (not app.__beta-init-loaded) "beta-init should be unloaded on clear")
            (assert (= (app.unit-manager:count) 0) "manager should be empty after clear")
            (app.unit-manager:clear))))
      (tset (require :fennel) :path old-fennel-path)
      (set app.__alpha-loaded nil)
      (set app.__beta-init-loaded nil)
      (set app.__beta-helper-loaded nil)
      (set app.__bad-loaded nil)
      (when (not ok)
        (error err)))))

(table.insert tests {:name "scanner loads top-level fnl and subdir init.fnl"
                     :fn user-code-directory-scanner-loads-top-level-and-subdir-init-fnl})

(fn user-code-unit-replaces-app-state-and-survives-clear []
  (with-temp-dir
    (fn [dir]
      (local old-fennel-path (. (require :fennel) :path))
      (fs.write-file (fs.join-path dir "replace-hud.fnl")
                     (.. "(fn init []\n"
                         "  (set app.__old-hud app.hud)\n"
                         "  (set app.hud \"replaced-by-user-code\")\n"
                         "  true)\n"
                         "(fn drop []\n"
                         "  (set app.hud app.__old-hud)\n"
                         "  (set app.__old-hud nil)\n"
                         "  true)\n"
                         "{:init init :drop drop}"))
      (set app.hud "original-hud")
      (set app.__old-hud nil)
      (local (ok err)
        (pcall
          (fn []
            (set app.unit-manager (or app.unit-manager (UnitManager {})))
            (local original-code-dir app.code-dir)
            (set app.code-dir dir)
            (Main.ensure-user-code-units!)
            (set app.code-dir original-code-dir)
            (assert (= app.hud "replaced-by-user-code")
                    "user code should replace app.hud")
            (assert (= (app.unit-manager:count) 1)
                    "should register exactly 1 user unit")
            (app.unit-manager:clear)
            (assert (= app.hud "original-hud")
                    "drop should restore original hud")
            (assert (= (app.unit-manager:count) 0)
                    "manager should be empty after clear")
            (app.unit-manager:clear))))
      (tset (require :fennel) :path old-fennel-path)
      (set app.hud nil)
      (when (not ok)
        (error err)))))

(table.insert tests {:name "user code unit replaces app state and survives clear"
                     :fn user-code-unit-replaces-app-state-and-survives-clear})

(fn scanner-prefers-directory-init-when-flat-collides []
  (with-temp-dir
    (fn [dir]
      (local old-fennel-path (. (require :fennel) :path))
      (fs.write-file (fs.join-path dir "collide.fnl")
                     (.. "(fn init [] (set app.__collide-loaded :flat) true)\n"
                         "(fn drop [] (set app.__collide-loaded nil) true)\n"
                         "{:init init :drop drop}"))
      (fs.create-dirs (fs.join-path dir "collide"))
      (fs.write-file (fs.join-path dir "collide" "init.fnl")
                     (.. "(fn init [] (set app.__collide-loaded :dir) true)\n"
                         "(fn drop [] (set app.__collide-loaded nil) true)\n"
                         "{:init init :drop drop}"))
       (set app.__collide-loaded nil)
       (local original-code-dir app.code-dir)
       (local original-unit-manager app.unit-manager)
       (local (ok err)
         (pcall
           (fn []
             (set app.unit-manager (UnitManager {}))
             (set app.code-dir dir)
             (Main.ensure-user-code-units!)
             (assert (= app.__collide-loaded :dir)
                     (.. "should load directory init when both shapes exist, got "
                         (tostring app.__collide-loaded)))
             (assert (= (app.unit-manager:count) 1)
                     "should register exactly 1 unit for colliding name")
             (app.unit-manager:clear))))
       (set app.code-dir original-code-dir)
       (set app.unit-manager original-unit-manager)
      (tset (require :fennel) :path old-fennel-path)
      (set app.__collide-loaded nil)
      (when (not ok)
        (error err)))))

(table.insert tests {:name "scanner prefers directory init when flat collides"
                     :fn scanner-prefers-directory-init-when-flat-collides})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "unit-manager"
                       :tests tests})))

{:name "unit-manager"
 :tests tests
 :main main}
