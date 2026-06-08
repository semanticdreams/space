;; Agent Units tests — unit extensions, tool adapters, agent integration.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-units:main

(local tests [])
(local fs (require :fs))
(local json (require :json))
(local Units (require :units))
(local UnitManager (require :unit-manager))
(local Signal (require :signal))
(local {: ToolAdapterRegistry} (require :llm/presets/tool-adapters))
(local {: PresetRegistry} (require :llm/presets/registry))
(local {: PresetManager} (require :llm/presets/init))
(local BuiltinUnits (require :llm/presets/builtins/units))
(local BuiltinGeneral (require :llm/presets/builtins/general))
(local tempfile (require :tempfile))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "agent-units-test-"}))
  (local path handle.path)
  (local (ok result) (pcall f path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn with-test-unit-mgr [dir f]
  (local saved-mgr app.unit-manager)
  (local saved-code-dir app.code-dir)
  (set app.unit-manager (UnitManager {}))
  (set app.code-dir dir)
  (local (ok result) (pcall f))
  (pcall #(app.unit-manager:clear))
  (set app.unit-manager saved-mgr)
  (set app.code-dir saved-code-dir)
  (if ok result (error result)))

(local logging (require :logging))

(fn with-log-path [path f]
  (local saved (logging.get-output-path))
  (logging.init {:path path})
  (local (ok err) (pcall f))
  (logging.init {:path saved})
  (when (not ok) (error err)))

;; ── Unit extensions: loaded? tracking ──

(fn test-unit-loaded-tracking []
  (local unit (Units.Unit {:id "load-track"
                           :load (fn [_ctx] true)
                           :unload (fn [_ctx] true)}))
  (assert (not (unit:loaded?)) "unit should start unloaded")
  (unit:load {})
  (assert (unit:loaded?) "unit should be loaded after load")
  (unit:unload {})
  (assert (not (unit:loaded?)) "unit should be unloaded after unload"))

(table.insert tests {:name "agent-units: loaded? tracking" :fn test-unit-loaded-tracking})

(fn test-unit-loaded-tracking-module-unit []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "test-module.fnl")
                     (.. "(fn init [] (set app.__unittest-val 1) true)\n"
                         "(fn drop [] (set app.__unittest-val nil) true)\n"
                         "{:init init :drop drop}"))
      (local fennel-mod (require :fennel))
      (local old-path fennel-mod.path)
      (set fennel-mod.path (.. dir "/?.fnl;" old-path))
      (set app.__unittest-val nil)
      (local (ok err) (pcall (fn []
                                (local unit (Units.ModuleUnit {:id "mod-load-track"
                                                                :module-name "test-module"
                                                                :suppress-run-main? false}))
                                (assert (not (unit:loaded?)) "module unit should start unloaded")
                                (unit:load {})
                                (assert (unit:loaded?) "module unit should be loaded after load")
                                (assert (= app.__unittest-val 1) "load should execute module code")
                                (unit:unload {})
                                (assert (not (unit:loaded?)) "module unit should be unloaded after unload")
                                (assert (= app.__unittest-val nil) "unload should execute drop"))))
      (set fennel-mod.path old-path)
      (when (not ok) (error err)))))

(table.insert tests {:name "agent-units: loaded? tracking ModuleUnit" :fn test-unit-loaded-tracking-module-unit})

;; ── Unit extensions: source field ──

(fn test-unit-source-default []
  (local unit (Units.Unit {:id "src-default"
                           :load (fn [_] true)
                           :unload (fn [_] true)}))
  (assert (= unit.source :user) "default source should be :user"))

(table.insert tests {:name "agent-units: source field default" :fn test-unit-source-default})

(fn test-unit-source-explicit []
  (local unit (Units.Unit {:id "src-explicit"
                           :load (fn [_] true)
                           :unload (fn [_] true)
                           :source :builtin}))
  (assert (= unit.source :builtin) "explicit source should be :builtin"))

(table.insert tests {:name "agent-units: source field explicit" :fn test-unit-source-explicit})

(fn test-module-unit-source []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "src-module.fnl")
                     (.. "(fn init [] true)\n"
                         "(fn drop [] true)\n"
                         "{:init init :drop drop}"))
      (local fennel-mod2 (require :fennel))
      (local old-path fennel-mod2.path)
      (set fennel-mod2.path (.. dir "/?.fnl;" old-path))
      (local (ok err) (pcall (fn []
                                (local unit (Units.ModuleUnit {:id "src-mod"
                                                                :module-name "src-module"
                                                                :source :builtin
                                                                :suppress-run-main? false}))
                                (assert (= unit.source :builtin) "ModuleUnit should pass through source")
                                (unit:load)
                                (unit:unload))))
      (set fennel-mod2.path old-path)
      (when (not ok) (error err)))))

(table.insert tests {:name "agent-units: source field ModuleUnit" :fn test-module-unit-source})

(fn test-source-unit-source []
  (local source
    (.. "(fn init [] (set app.__origin-val :loaded) true)\n"
        "(fn drop [] (set app.__origin-val nil) true)\n"
        "{:init init :drop drop}"))
  (set app.__origin-val nil)
  (local unit (Units.SourceUnit {:id "origin-test"
                                   :source source
                                   :source-type :builtin}))
  (assert (= unit.source :builtin) "SourceUnit should accept source-type metadata")
  (unit:load)
  (assert (= app.__origin-val :loaded))
  (unit:unload)
  (assert (= app.__origin-val nil)))

(table.insert tests {:name "agent-units: source field SourceUnit" :fn test-source-unit-source})

;; ── Unit extensions: module-name field ──

(fn test-unit-module-name-default []
  (local unit (Units.Unit {:id "modname-default"
                           :load (fn [_] true)
                           :unload (fn [_] true)}))
  (assert (= unit.module-name "modname-default") "module-name should default to id"))

(table.insert tests {:name "agent-units: module-name defaults to id" :fn test-unit-module-name-default})

(fn test-unit-module-name-explicit []
  (local unit (Units.Unit {:id "modname-id"
                           :module-name "modname-explicit"
                           :load (fn [_] true)
                           :unload (fn [_] true)}))
  (assert (= unit.module-name "modname-explicit") "module-name should support explicit value"))

(table.insert tests {:name "agent-units: module-name explicit" :fn test-unit-module-name-explicit})

(fn test-module-unit-module-name []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "modname-mod.fnl")
                     (.. "(fn init [] true)\n"
                         "(fn drop [] true)\n"
                         "{:init init :drop drop}"))
      (local fennel-mod3 (require :fennel))
      (local old-path fennel-mod3.path)
      (set fennel-mod3.path (.. dir "/?.fnl;" old-path))
      (local (ok err) (pcall (fn []
                                (local unit (Units.ModuleUnit {:id "modname-id"
                                                                :module-name "modname-mod"
                                                                :suppress-run-main? false}))
                                (assert (= unit.module-name "modname-mod") "ModuleUnit should store module-name")
                                (assert (= unit.id "modname-id") "ModuleUnit id should be distinct from module-name")
                                (unit:load)
                                (unit:unload))))
      (set fennel-mod3.path old-path)
      (when (not ok) (error err)))))

(table.insert tests {:name "agent-units: module-name ModuleUnit" :fn test-module-unit-module-name})

(fn test-module-unit-unload-does-not-clear-unowned-prefix-modules []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "graph.fnl")
                     (.. "(fn init [] true)\n"
                         "(fn drop [] true)\n"
                         "{:init init :drop drop}"))
      (local sentinel {:core true})
      (local previous-graph-core (. package.loaded "graph.core"))
      (set (. package.loaded "graph.core") sentinel)
      (local (ok err) (pcall
                        (fn []
                          (local unit (Units.ModuleUnit {:id "user-graph"
                                                          :module-name "graph"
                                                          :module-paths (.. dir "/?.fnl")
                                                          :source :user
                                                          :owned-paths [(fs.join-path dir "graph.fnl")]
                                                          :suppress-run-main? false}))
                          (unit:load {})
                          (unit:unload {})
                          (assert (= (. package.loaded "graph") nil)
                                  "owned module should be cleared on unload")
                          (assert (= (. package.loaded "graph.core") sentinel)
                                  "unowned prefix module should remain loaded"))))
      (set (. package.loaded "graph.core") previous-graph-core)
      (when (not ok) (error err)))))

(table.insert tests {:name "agent-units: ModuleUnit unload scopes package cache"
                     :fn test-module-unit-unload-does-not-clear-unowned-prefix-modules})

;; ── Unit extensions: signal tracking ──

(fn test-unit-signal-connect-and-disconnect []
  (local sig (Signal))
  (var received nil)
  (local unit (Units.Unit {:id "sig-unit"
                           :load (fn [_] true)
                           :unload (fn [_] true)
                           :source :user}))
  (unit:load)
  (unit:connect-signal "test" sig (fn [payload] (set received payload)))
  (sig:emit :hello)
  (assert (= received :hello) "signal handler should receive payload")
  (unit:disconnect-signal "test")
  (sig:emit :ignored)
  (assert (= received :hello) "disconnected handler should not receive new payloads")
  (unit:unload))

(table.insert tests {:name "agent-units: signal connect and disconnect" :fn test-unit-signal-connect-and-disconnect})

(fn test-unit-signal-auto-disconnect-on-unload []
  (local sig (Signal))
  (var received nil)
  (local unit (Units.Unit {:id "auto-sig-unit"
                           :load (fn [_] true)
                           :unload (fn [_] true)}))
  (unit:load)
  (unit:connect-signal "autotest" sig (fn [payload] (set received payload)))
  (sig:emit "before unload")
  (assert (= received "before unload"))
  (unit:unload)
  (local (ok _) (pcall sig.emit sig "after unload"))
  (assert ok "emit after unload should not error (handler was removed)")
  (assert (= received "before unload") "handler should not fire after unload"))

(table.insert tests {:name "agent-units: signal auto-disconnect on unload" :fn test-unit-signal-auto-disconnect-on-unload})

(fn test-unit-signal-duplicate-connect-errors []
  (local sig (Signal))
  (local unit (Units.Unit {:id "dup-sig-unit"
                           :load (fn [_] true)
                           :unload (fn [_] true)}))
  (unit:load)
  (unit:connect-signal "duptest" sig (fn [_] nil))
  (local (ok err) (pcall unit.connect-signal unit "duptest" sig (fn [_] nil)))
  (assert (not ok) "duplicate connect should error")
  (assert (string.find (tostring err) "already connected") "error should mention already connected")
  (unit:unload))

(table.insert tests {:name "agent-units: duplicate signal connect errors" :fn test-unit-signal-duplicate-connect-errors})

(fn test-unit-signal-disconnect-missing-errors []
  (local unit (Units.Unit {:id "missing-sig-unit"
                           :load (fn [_] true)
                           :unload (fn [_] true)}))
  (unit:load)
  (local (ok err) (pcall unit.disconnect-signal unit "nonexistent"))
  (assert (not ok) "disconnecting nonexistent signal should error")
  (assert (string.find (tostring err) "not connected") "error should mention not connected")
  (unit:unload))

(table.insert tests {:name "agent-units: disconnect missing signal errors" :fn test-unit-signal-disconnect-missing-errors})

;; ── Tool adapters: registration ──

(fn test-unit-tool-adapters-register []
  (local adapters (ToolAdapterRegistry {}))
  (local (ok err) (pcall BuiltinUnits.register {:tool-adapters adapters}))
  (assert ok (.. "registration should succeed: " (tostring err)))
  (local tool-ids [:unit.list :unit.inspect :unit.create :unit.register :unit.edit
                   :unit.edit-file :unit.apply-patch :unit.reload
                   :unit.delete :unit.eval :unit.snapshot :unit.restore
                   :unit.connect-signal :unit.disconnect-signal
                   :unit.read-log :unit.create-test :unit.run-tests])
  (each [_ id (ipairs tool-ids)]
    (local adapter (adapters:get id))
    (assert adapter (.. "adapter " id " should be registered"))))

(table.insert tests {:name "agent-units: tool adapters register" :fn test-unit-tool-adapters-register})

(fn test-space-app-list-files-returns-entries []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "alpha.fnl") "{:ok true}")
      (fs.create-dirs (fs.join-path dir "subdir"))
      (local adapters (ToolAdapterRegistry {}))
      (BuiltinGeneral.register {:tool-adapters adapters})
      (local def (adapters:resolve "app.list-files" app))
      (local result (json.loads (def.run {:path dir})))
      (assert (= (length result) 2) "list-files should return entries, not just a count")
      (var alpha nil)
      (var subdir nil)
      (each [_ entry (ipairs result)]
        (when (= entry.name "alpha.fnl")
          (set alpha entry))
        (when (= entry.name "subdir")
          (set subdir entry)))
      (assert alpha "list-files should include file name")
      (assert alpha.is-file "file entry should mark is-file")
      (assert (= alpha.path (fs.join-path dir "alpha.fnl")) "file entry should include path")
      (assert subdir "list-files should include directory name")
      (assert subdir.is-dir "directory entry should mark is-dir"))))

(table.insert tests {:name "agent-units: space_app_list_files returns entries"
                     :fn test-space-app-list-files-returns-entries})

;; ── Tool adapters: unit.list ──

(fn test-space-unit-list []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.list" app))

          (local unit1 (Units.Unit {:id "list-1" :source :user
                                    :load (fn [_] true) :unload (fn [_] true)
                                    :owned-paths [(fs.join-path dir "list-1.fnl")]}))
          (local unit2 (Units.Unit {:id "list-2" :source :builtin
                                    :load (fn [_] true) :unload (fn [_] true)
                                    :owned-paths []}))
          (app.unit-manager:register unit1)
          (app.unit-manager:register unit2)
          (unit1:load {})

          (local result (json.loads (def.run {})))
          (assert (= (length result) 2) "should list 2 units")
          (var list-1 nil)
          (var list-2 nil)
          (each [_ entry (ipairs result)]
            (when (= entry.id "list-1") (set list-1 entry))
            (when (= entry.id "list-2") (set list-2 entry)))
          (assert list-1 "should contain list-1")
          (assert list-2 "should contain list-2")
          (assert (= list-1.source :user) "list-1 should be user")
          (assert (= list-2.source :builtin) "list-2 should be builtin")
          (assert (= list-1.module-name "list-1") "list-1 module-name should default to id")
          (assert list-1.loaded "list-1 should be loaded")
          (assert (not list-2.loaded) "list-2 should not be loaded")

          (unit1:unload {})
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_list" :fn test-space-unit-list})

;; ── Tool adapters: unit.inspect ──

(fn test-space-unit-inspect []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "inspect-me.fnl"))
          (fs.write-file file-path
                         (.. "(fn init [] true)\n"
                             "(fn drop [] true)\n"
                             "{:init init :drop drop}"))
          (local unit (Units.ModuleUnit {:id "inspect-me"
                                          :module-name "inspect-me"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.inspect" app))

          (local result (json.loads (def.run {:id "inspect-me"})))
          (assert (= result.id "inspect-me") "inspect should return id")
          (assert (= result.source :user) "inspect should return source")
          (assert result.loaded "inspect should show loaded")
          (assert (= result.source-file file-path) "inspect should return source file")
          (assert result.source-code "inspect should return source code")
          (assert (string.find result.source-code "init init") "source code should contain module code")

          (unit:unload {})
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_inspect" :fn test-space-unit-inspect})

(fn test-space-unit-inspect-directory-submodules []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-dir (fs.join-path dir "inspect-dir"))
          (fs.create-dirs unit-dir)
          (local init-path (fs.join-path unit-dir "init.fnl"))
          (local render-path (fs.join-path unit-dir "render.fnl"))
          (local controller-path (fs.join-path unit-dir "controller.fnl"))
          (fs.write-file init-path
                         (.. "(fn init [] true)\n"
                             "(fn drop [] true)\n"
                             "{:init init :drop drop}"))
          (fs.write-file render-path "{:value :render}")
          (fs.write-file controller-path "{:value :controller}")
          (local unit (Units.ModuleUnit {:id "user-inspect-dir"
                                          :module-name "inspect-dir"
                                          :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
                                          :source :user
                                          :owned-paths [init-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.inspect" app))
          (local result (json.loads (def.run {:id "user-inspect-dir"})))

          (assert (= result.id "user-inspect-dir") "should return id")
          (assert (= result.module-name "inspect-dir") "should return module-name")
          (assert (= result.source :user))
          (assert (= result.source-file init-path) "source-file should be init.fnl")
          (assert result.source-code "should return source code")
          (assert (= result.load-export "init") "default load-export should be init")
          (assert (= result.unload-export "drop") "default unload-export should be drop")
          (assert (string.find result.snapshot-export "snapshot") "should report snapshot-export")
          (assert (string.find result.restore-export "restore") "should report restore-export")
          (assert (= (type result.submodules) :table) "submodules should be a table")
          (assert (>= (# result.submodules) 2) "directory unit should list submodule files")
          (var found-render false)
          (var found-controller false)
          (each [_ sm (ipairs result.submodules)]
            (when (= sm.name "render.fnl") (set found-render true))
            (when (= sm.name "controller.fnl") (set found-controller true)))
          (assert found-render "submodules should include render.fnl")
          (assert found-controller "submodules should include controller.fnl")
          (assert (not (string.find result.source-code "render.fnl" 1 true))
                  "source-code should be init.fnl content, not all submodules")

          (unit:unload {})
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_inspect directory submodules"
                     :fn test-space-unit-inspect-directory-submodules})

(fn test-space-unit-inspect-custom-exports []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "custom-exp.fnl"))
          (fs.write-file file-path
                         (.. "(fn start [] true)\n"
                             "(fn stop [] true)\n"
                             "{:start start :stop stop}"))
          (local unit (Units.ModuleUnit {:id "custom-exp"
                                          :module-name "custom-exp"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :load-export "start"
                                          :unload-export "stop"
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.inspect" app))
          (local result (json.loads (def.run {:id "custom-exp"})))

          (assert (= result.load-export "start") "should report load-export")
          (assert (= result.unload-export "stop") "should report unload-export")
          (assert (= result.snapshot-export "snapshot") "default snapshot-export should be snapshot")
          (assert (= result.restore-export "restore") "default restore-export should be restore")
          (assert (= (# result.submodules) 0) "flat unit should have no submodules")

          (unit:unload {})
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_inspect custom exports"
                     :fn test-space-unit-inspect-custom-exports})

(fn test-space-unit-inspect-snapshot-restore-exports []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "snap-unit.fnl"))
          (fs.write-file file-path
                         (.. "(fn init [] true)\n"
                             "(fn drop [] true)\n"
                             "(fn snapshot [] app.__snap-state)\n"
                             "(fn restore [state] (set app.__snap-state state) true)\n"
                             "{:init init :drop drop :snapshot snapshot :restore restore}"))
          (local unit (Units.ModuleUnit {:id "snap-unit"
                                          :module-name "snap-unit"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.inspect" app))
          (local result (json.loads (def.run {:id "snap-unit"})))

          ;; Using default exports, snapshot/restore are present implicitly
          (assert (= result.load-export "init"))
          (assert (= result.unload-export "drop"))
          (assert (string.find result.snapshot-export "snapshot") "should report snapshot-export")
          (assert (string.find result.restore-export "restore") "should report restore-export")
          (assert (= result.module-name "snap-unit"))

          (unit:unload {})
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_inspect snapshot/restore exports"
                     :fn test-space-unit-inspect-snapshot-restore-exports})

;; ── Tool adapters: unit.create ──

(fn test-space-unit-create []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create" app))

          (local unit-source
            (.. "(fn init [] (set app.__create-test :created) true)\n"
                "(fn drop [] (set app.__create-test nil) true)\n"
                "{:init init :drop drop}"))
          (set app.__create-test nil)

          (local result (json.loads
                          (def.run {:id "my-unit" :source unit-source})))
          (assert (= result.id "user-my-unit") "create should prefix user- onto id")
          (assert (= result.module-name "my-unit") "create should expose module-name")
          (assert result.loaded "created unit should be loaded")
          (assert (= app.__create-test :created) "load should have set app state")
          (local file-path (fs.join-path dir "my-unit.fnl"))
          (assert (fs.exists file-path) "source file should exist")

          (local unit (app.unit-manager:get "user-my-unit"))
          (assert unit "unit should be registered")
          (assert (= unit.source :user) "created unit should be user source")
          (assert (= unit.module-name "my-unit") "unit module-name should be my-unit")
          (assert (unit:loaded?) "unit should be loaded")

          (app.unit-manager:clear)
          (assert (= app.__create-test nil) "unload should have cleared app state"))))))

(table.insert tests {:name "agent-units: space_unit_create" :fn test-space-unit-create})

(fn test-space-unit-create-duplicate []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create" app))

          (local unit-source "(fn init [] true)(fn drop [] true){:init init :drop drop}")
          (def.run {:id "dup-unit" :source unit-source})

          (local (ok err) (pcall def.run {:id "dup-unit" :source unit-source}))
          (assert (not ok) "duplicate create should fail")
          (assert (string.find (tostring err) "already exists") "error should mention already exists")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_create duplicate" :fn test-space-unit-create-duplicate})

(fn test-space-unit-create-invalid-source []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create" app))

          (local invalid-source "this is not valid fennel ( ) [ } {")
          (local file-path (fs.join-path dir "bad-unit.fnl"))
          (local suppress-before app.__suppress-main-run?)

          (local (ok err) (pcall def.run {:id "bad-unit" :source invalid-source}))
          (assert (not ok) "create with invalid source should fail")
          (assert (string.find (tostring err) "error") "error should mention error")

          (assert (= app.__suppress-main-run? suppress-before)
                  "suppress-main-run flag should be restored after failed require")

          (assert (not (fs.exists file-path))
                  "invalid-source create should not leave file on disk")
          (assert (= (app.unit-manager:get "user-bad-unit") nil)
                  "invalid-source create should not leave unit registered")

          (app.unit-manager:clear)
          (when (fs.exists file-path)
            (fs.remove-all file-path)))))))

(table.insert tests {:name "agent-units: space_unit_create invalid source cleanup" :fn test-space-unit-create-invalid-source})

(fn test-space-unit-create-partial-init-cleanup []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create" app))

          (local Signal (require :signal))
          (local signal (Signal))
          (set app.__partial-signal signal)
          (set app.__partial-val nil)
          (set app.__partial-handler-called false)

          (local leaky-source
            (.. "(var handler nil)\n"
                "(fn init []\n"
                "  (set app.__partial-val :set-during-init)\n"
                "  (set handler (fn [_] (set app.__partial-handler-called true)))\n"
                "  (app.__partial-signal:connect handler)\n"
                "  (error \"init failure halfway through\")\n"
                "  true)\n"
                "(fn drop []\n"
                "  (when handler\n"
                "    (app.__partial-signal:disconnect handler true))\n"
                "  (set app.__partial-val nil)\n"
                "  true)\n"
                "{:init init :drop drop}"))
          (local file-path (fs.join-path dir "partial-unit.fnl"))

          (local (ok err) (pcall def.run {:id "partial-unit" :source leaky-source}))
          (assert (not ok) "create should fail on init error")
          (assert (string.find (tostring err) "init failure") "error should include init message")

          (assert (not (fs.exists file-path)) "file should be removed on failure")
          (assert (= (app.unit-manager:get "user-partial-unit") nil) "unit should not be registered")

          (signal:emit "test-payload")
          (assert (not app.__partial-handler-called) "signal handler should be disconnected")

          (assert (= app.__partial-val nil) "app state should be cleaned up by drop")

          (set app.__partial-signal nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_create partial init cleanup" :fn test-space-unit-create-partial-init-cleanup})

(fn test-space-unit-create-drop-also-fails []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create" app))

          (local Signal (require :signal))
          (local signal (Signal))
          (set app.__down-signal signal)
          (set app.__down-val nil)

          (local down-source
            (.. "(fn init []\n"
                "  (set app.__down-val :set-during-init)\n"
                "  (error \"init boom\")\n"
                "  true)\n"
                "(fn drop []\n"
                "  (set app.__down-val nil)\n"
                "  (error \"drop also boom\"))\n"
                "{:init init :drop drop}"))
          (local file-path (fs.join-path dir "down-unit.fnl"))

          (local (ok err) (pcall def.run {:id "down-unit" :source down-source}))
          (assert (not ok) "create should fail")
          (local errstr (tostring err))
          (assert (string.find errstr "init boom") "error should include init message")
          (assert (string.find errstr "cleanup also failed") "error should mention cleanup failure")
          (assert (string.find errstr "drop also boom") "error should include drop message")

          (assert (not (fs.exists file-path)) "file should be removed")
          (assert (= (app.unit-manager:get "user-down-unit") nil) "unit should not be registered")
          (assert (= (. package.loaded "down-unit") nil) "stale module should be purged from cache")

          (set app.__down-signal nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_create drop also fails cleanup" :fn test-space-unit-create-drop-also-fails})

(fn test-module-unit-cache-survives-failed-unload []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local Signal (require :signal))
          (local signal (Signal))
          (set app.__retry-signal signal)
          (set app.__retry-received false)
          (set app.__retry-drop-fail-once true)

          (fs.write-file (fs.join-path dir "retry-unit.fnl")
                         (.. "(var handler nil)\n"
                             "(fn init []\n"
                             "  (set handler (fn [_] (set app.__retry-received true)))\n"
                             "  (app.__retry-signal:connect handler)\n"
                             "  true)\n"
                             "(fn drop []\n"
                             "  (when app.__retry-drop-fail-once\n"
                             "    (set app.__retry-drop-fail-once false)\n"
                             "    (error \"first drop fails before disconnect\"))\n"
                             "  (when handler\n"
                             "    (app.__retry-signal:disconnect handler true))\n"
                             "  true)\n"
                             "{:init init :drop drop}"))

          (local unit (Units.ModuleUnit {:id "retry-unit"
                                          :module-name "retry-unit"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [(fs.join-path dir "retry-unit.fnl")]
                                          :suppress-run-main? false}))
          (unit:load {})

          (signal:emit :after-load)
          (assert app.__retry-received "signal should fire after load")

          (set app.__retry-received false)
          (local (unload-ok unload-err) (pcall #(unit:unload {})))
          (assert (not unload-ok) "first unload should fail")
          (assert (string.find (tostring unload-err) "first drop fails") "error should mention first drop failure")

          (signal:emit :after-failed-unload)
          (assert app.__retry-received "signal should still fire after failed unload (handler not disconnected)")

          (set app.__retry-received false)
          (local (retry-ok retry-err) (pcall #(unit:unload {})))
          (assert retry-ok (.. "retry unload should succeed, got: " (tostring retry-err)))
          (assert (not (unit:loaded?)) "unit should not be loaded after successful retry unload")
          (assert (= (. package.loaded "retry-unit") nil) "module cache should be cleared after successful retry unload")

          (signal:emit :after-retry-unload)
          (assert (not app.__retry-received) "signal should NOT fire after successful unload (handler disconnected)")

          (set app.__retry-signal nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: cache survives failed unload for retry disconnect" :fn test-module-unit-cache-survives-failed-unload})

(fn test-unit-manager-preserves-loaded-unit-on-unload-failure []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local Signal (require :signal))
          (local signal (Signal))
          (set app.__mgr-retry-signal signal)
          (set app.__mgr-retry-received false)
          (set app.__mgr-retry-drop-fail-once true)

          (fs.write-file (fs.join-path dir "mgr-retry-unit.fnl")
                         (.. "(var handler nil)\n"
                             "(fn init []\n"
                             "  (set handler (fn [_] (set app.__mgr-retry-received true)))\n"
                             "  (app.__mgr-retry-signal:connect handler)\n"
                             "  true)\n"
                             "(fn drop []\n"
                             "  (when app.__mgr-retry-drop-fail-once\n"
                             "    (set app.__mgr-retry-drop-fail-once false)\n"
                             "    (error \"manager drop fails first time\"))\n"
                             "  (when handler\n"
                             "    (app.__mgr-retry-signal:disconnect handler true))\n"
                             "  true)\n"
                             "{:init init :drop drop}"))

          (local unit (Units.ModuleUnit {:id "mgr-retry-unit"
                                          :module-name "mgr-retry-unit"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [(fs.join-path dir "mgr-retry-unit.fnl")]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (signal:emit :after-load)
          (assert app.__mgr-retry-received "signal should fire after load")
          (set app.__mgr-retry-received false)

          (local (unreg-ok unreg-err) (pcall #(app.unit-manager:unregister "mgr-retry-unit")))
          (assert (not unreg-ok) "unregister should fail when drop throws")
          (assert (string.find (tostring unreg-err) "manager drop fails") "error should mention drop failure")
          (assert (not (= (app.unit-manager:get "mgr-retry-unit") nil)) "unit should still be registered after failed unregister")
          (assert (unit:loaded?) "unit should still be loaded after failed unregister")

          (signal:emit :after-failed-unregister)
          (assert app.__mgr-retry-received "signal should fire after failed unregister (handler intact)")

          (set app.__mgr-retry-received false)
          (local (unreg2-ok unreg2-err) (pcall #(app.unit-manager:unregister "mgr-retry-unit")))
          (assert unreg2-ok (.. "retry unregister should succeed, got: " (tostring unreg2-err)))
          (assert (= (app.unit-manager:get "mgr-retry-unit") nil) "unit should be gone after successful unregister")
          (assert (not (unit:loaded?)) "unit should not be loaded after successful unregister")

          (signal:emit :after-retry-unregister)
          (assert (not app.__mgr-retry-received) "signal should not fire after successful unregister (disconnected)")

          (set app.__mgr-retry-signal nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: manager preserves loaded unit on unload failure for retry" :fn test-unit-manager-preserves-loaded-unit-on-unload-failure})

;; ── Tool adapters: unit.edit ──

(fn test-space-unit-edit []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "editable.fnl"))
      (fs.write-file file-path
                     (.. "(fn init [] (set app.__edit-val :v1) true)\n"
                         "(fn drop [] (set app.__edit-val nil) true)\n"
                         "(fn snapshot [] app.__edit-val)\n"
                         "(fn restore [state] (set app.__edit-val state) true)\n"
                         "{:init init :drop drop :snapshot snapshot :restore restore}"))
      (local unit (Units.ModuleUnit {:id "editable"
                                      :module-name "editable"
                                      :module-paths (.. dir "/?.fnl")
                                      :source :user
                                      :owned-paths [file-path]
                                      :suppress-run-main? false}))
      (app.unit-manager:register unit)
      (unit:load {})
      (assert (= app.__edit-val :v1) "initial load should set val")

      (local adapters (ToolAdapterRegistry {}))
      (BuiltinUnits.register {:tool-adapters adapters})
      (local def (adapters:resolve "unit.edit" app))

      (local new-source
        (.. "(fn init [] (set app.__edit-val :v2) true)\n"
            "(fn drop [] (set app.__edit-val nil) true)\n"
            "(fn snapshot [] app.__edit-val)\n"
            "(fn restore [_state] (set app.__edit-val :reload-complete) true)\n"
            "{:init init :drop drop :snapshot snapshot :restore restore}"))
      (local result (json.loads
                      (def.run {:id "editable" :source new-source})))
      (assert result.reloaded "edit should trigger reload")
      (assert (= app.__edit-val :reload-complete) "restore should run from new source")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_edit" :fn test-space-unit-edit})

(fn test-space-unit-edit-file-for-directory-unit []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-dir (fs.join-path dir "multi"))
          (fs.create-dirs unit-dir)
          (local init-path (fs.join-path unit-dir "init.fnl"))
          (local controller-path (fs.join-path unit-dir "controller.fnl"))
          (fs.write-file controller-path
                         "(fn value [] :v1)\n{:value value}")
          (fs.write-file init-path
                         (.. "(local {: value} (require :multi/controller))\n"
                             "(fn init [] (set app.__multi-val (value)) true)\n"
                             "(fn drop [] (set app.__multi-val nil) true)\n"
                             "{:init init :drop drop}"))
          (local unit (Units.ModuleUnit {:id "user-multi"
                                          :module-name "multi"
                                          :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
                                          :source :user
                                          :owned-paths [init-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})
          (assert (= app.__multi-val :v1) "initial directory unit should load controller v1")

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.edit-file" app))
          (local result
            (json.loads
              (def.run {:id "user-multi"
                        :path "controller.fnl"
                        :source "(fn value [] :v2)\n{:value value}"})))
          (assert result.reloaded "edit-file should trigger reload")
          (assert (= app.__multi-val :v2) "reload should use edited controller")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_edit_file directory unit"
                     :fn test-space-unit-edit-file-for-directory-unit})

(fn test-space-unit-apply-patch-for-directory-unit []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-dir (fs.join-path dir "patchy"))
          (fs.create-dirs unit-dir)
          (local init-path (fs.join-path unit-dir "init.fnl"))
          (local controller-path (fs.join-path unit-dir "controller.fnl"))
          (fs.write-file controller-path
                         "(fn value [] :slow)\n{:value value}")
          (fs.write-file init-path
                         (.. "(local {: value} (require :patchy/controller))\n"
                             "(fn init [] (set app.__patch-val (value)) true)\n"
                             "(fn drop [] (set app.__patch-val nil) true)\n"
                             "{:init init :drop drop}"))
          (local unit (Units.ModuleUnit {:id "user-patchy"
                                          :module-name "patchy"
                                          :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
                                          :source :user
                                          :owned-paths [init-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})
          (assert (= app.__patch-val :slow) "initial directory unit should load slow value")

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.apply-patch" app))
          (local result
            (json.loads
              (def.run {:id "user-patchy"
                        :path "controller.fnl"
                        :old ":slow"
                        :new ":slower"})))
          (assert result.reloaded "apply-patch should trigger reload")
          (assert (= app.__patch-val :slower) "reload should use patched controller")
          (local patch-result
            (json.loads
              (def.run {:id "user-patchy"
                        :path "controller.fnl"
                        :patch (.. "*** Begin Patch\n"
                                   "*** Update File: controller.fnl\n"
                                   "@@ -1,2 +1,2 @@\n"
                                   "-(fn value [] :slower)\n"
                                   "+(fn value [] :slowest)\n"
                                   " {:value value}\n"
                                   "*** End Patch\n")})))
          (assert patch-result.reloaded "unified patch should trigger reload")
          (assert (= app.__patch-val :slowest) "reload should use unified-patched controller")
          (local restored-source (fs.read-file controller-path))
          (local (delegated-ok delegated-err)
            (pcall def.run {:id "user-patchy"
                            :path "controller.fnl"
                            :patch (.. "*** Begin Patch\n"
                                       "*** Update File: controller.fnl\n"
                                       "@@ -1,2 +1,2 @@\n"
                                       "-(fn value [] :missing-context)\n"
                                       "+(fn value [] :never)\n"
                                       " {:value value}\n"
                                       "*** End Patch\n")}))
          (assert (not delegated-ok) "delegated patch failure should fail")
          (assert (string.find (tostring delegated-err) "source restored")
                  "delegated patch failure should mention restore")
          (assert (= (fs.read-file controller-path) restored-source)
                  "delegated patch failure should keep previous file content")
          (assert (= app.__patch-val :slowest)
                  "delegated patch failure should keep previous runtime")
          (local (invalid-ok invalid-err)
            (pcall def.run {:id "user-patchy"
                            :path "controller.fnl"
                            :patch (.. "*** Begin Patch\n"
                                       "*** Update File: controller.fnl\n"
                                       "@@ -1,2 +1,2 @@\n"
                                       "-(fn value [] :slowest)\n"
                                       "+(fn value []\n"
                                       " {:value value}\n"
                                       "*** End Patch\n")}))
          (assert (not invalid-ok) "invalid patched Fennel should fail")
          (assert (string.find (tostring invalid-err) "source restored")
                  "invalid patch error should mention restore")
          (assert (= (fs.read-file controller-path) restored-source)
                  "invalid patch should restore previous file content")
          (assert (= app.__patch-val :slowest) "invalid patch recovery should keep previous runtime")
          (local (ambiguous-ok ambiguous-err)
            (pcall def.run {:id "user-patchy"
                            :path "controller.fnl"
                            :patch (.. "*** Begin Patch\n"
                                       "*** Update File: controller.fnl\n"
                                       "@@ -1,2 +1,2 @@\n"
                                       "-(fn value [] :slowest)\n"
                                       "+(fn value [] :fast)\n"
                                       " {:value value}\n"
                                       "*** End Patch\n")
                            :old ":slowest"
                            :new ":fast"}))
          (assert (not ambiguous-ok) "patch plus old/new should fail")
          (assert (string.find (tostring ambiguous-err) "not both")
                  "ambiguous mode error should mention not both")
          (local (missing-mode-ok missing-mode-err)
            (pcall def.run {:id "user-patchy" :path "controller.fnl"}))
          (assert (not missing-mode-ok) "missing patch mode should fail")
          (assert (string.find (tostring missing-mode-err) "requires either")
                  "missing mode error should mention required modes")
          (local (ok err)
            (pcall def.run {:id "user-patchy"
                            :path "controller.fnl"
                            :old ":missing"
                            :new ":never"}))
          (assert (not ok) "missing old text should fail")
          (assert (string.find (tostring err) "old text was not found")
                  "error should mention missing old text")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_apply_patch directory unit"
                     :fn test-space-unit-apply-patch-for-directory-unit})

(fn test-space-unit-edit-rejects-builtin []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "builtin-edit.fnl"))
          (fs.write-file file-path "(fn init [] true)(fn drop [] true){:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "builtin-edit"
                                          :module-name "builtin-edit"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :builtin
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.edit" app))

          (local (ok err) (pcall def.run {:id "builtin-edit" :source "x"}))
          (assert (not ok) "edit should reject builtin unit")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_edit rejects builtin" :fn test-space-unit-edit-rejects-builtin})

(fn test-space-unit-edit-missing-drop []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "init-drop.fnl"))
          (fs.write-file file-path
                         (.. "(fn init [] (set app.__nodrop-val :init) true)\n"
                             "(fn drop [] (set app.__nodrop-val nil) true)\n"
                             "{:init init :drop drop}"))
          (local unit (Units.ModuleUnit {:id "init-drop"
                                          :module-name "init-drop"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})
          (assert (= app.__nodrop-val :init) "initial load should set val")

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.edit" app))

          (local no-drop-source
            (.. "(fn init [] (set app.__nodrop-val :v2) true)\n"
                "{:init init}"))
          (local (ok err) (pcall def.run {:id "init-drop" :source no-drop-source}))
          (assert (not ok) "edit should fail when new source has no drop")
          (local errstr (tostring err))
          (assert (string.find errstr "module exports invalid") "error should mention exports")

          (assert (= app.__nodrop-val :init) "old source restored, init re-ran during recovery")
          (assert (unit:loaded?) "unit should still be loaded after recovery")
          (unit:unload {})
          (assert (not (unit:loaded?)) "unload should succeed with old drop")
          (assert (= app.__nodrop-val nil) "drop should have cleared val")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_edit missing drop" :fn test-space-unit-edit-missing-drop})

(fn test-space-unit-edit-custom-exports []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "custom-exp.fnl"))
          (fs.write-file file-path
                         (.. "(fn start [] (set app.__cust-val :boot) true)\n"
                             "(fn stop [] (set app.__cust-val nil) true)\n"
                             "{:start start :stop stop}"))
          (local unit (Units.ModuleUnit {:id "custom-exp"
                                          :module-name "custom-exp"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :load-export "start"
                                          :unload-export "stop"
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})
          (assert (= app.__cust-val :boot) "custom load should set val")

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.edit" app))

          (local v2-source
            (.. "(fn start [] (set app.__cust-val :v2) true)\n"
                "(fn stop [] (set app.__cust-val :cleaned) true)\n"
                "{:start start :stop stop}"))
          (local result (json.loads (def.run {:id "custom-exp" :source v2-source})))
          (assert result.reloaded "edit with custom exports should succeed")
          (assert (= app.__cust-val :v2) "custom load export should have run")

          (local no-stop-source
            (.. "(fn start [] (set app.__cust-val :bad) true)\n"
                "{:start start}"))
          (local (ok err) (pcall def.run {:id "custom-exp" :source no-stop-source}))
          (assert (not ok) "edit should fail when new source missing custom unload export")
          (local errstr (tostring err))
          (assert (string.find errstr "module exports invalid") "error should mention exports")
          (assert (string.find errstr "stop") "error should name the missing export")
          (assert (= app.__cust-val :v2) "old source restored, v2 init re-ran during recovery")
          (assert (unit:loaded?) "unit should still be loaded after recovery")
          (unit:unload {})
          (assert (= app.__cust-val :cleaned) "old stop export should have run")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_edit custom exports" :fn test-space-unit-edit-custom-exports})

;; ── Tool adapters: unit.reload ──

(fn test-space-unit-reload []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "reload-me.fnl"))
      (fs.write-file file-path
                     (.. "(fn init [] (set app.__reload-val :first) true)\n"
                         "(fn drop [] (set app.__reload-val nil) true)\n"
                         "(fn snapshot [] app.__reload-val)\n"
                         "(fn restore [state] (set app.__reload-val state) true)\n"
                         "{:init init :drop drop :snapshot snapshot :restore restore}"))
      (local unit (Units.ModuleUnit {:id "reload-me"
                                      :module-name "reload-me"
                                      :module-paths (.. dir "/?.fnl")
                                      :source :user
                                      :owned-paths [file-path]
                                      :suppress-run-main? false}))
      (app.unit-manager:register unit)
      (unit:load {})
      (assert (= app.__reload-val :first) "initial load")

      (local adapters (ToolAdapterRegistry {}))
      (BuiltinUnits.register {:tool-adapters adapters})
      (local def (adapters:resolve "unit.reload" app))

      (fs.write-file file-path
                     (.. "(fn init [] (set app.__reload-val :second) true)\n"
                         "(fn drop [] (set app.__reload-val nil) true)\n"
                         "(fn snapshot [] app.__reload-val)\n"
                         "(fn restore [_state] (set app.__reload-val :from-new-restore) true)\n"
                         "{:init init :drop drop :snapshot snapshot :restore restore}"))
      (def.run {:id "reload-me"})
      (assert (= app.__reload-val :from-new-restore) "reload should run new restore")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_reload" :fn test-space-unit-reload})

;; ── Tool adapters: unit.delete ──

(fn test-space-unit-delete []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "delete-me.fnl"))
          (fs.write-file file-path "(fn init [] true)(fn drop [] true){:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "delete-me"
                                          :module-name "delete-me"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.delete" app))

          (def.run {:id "delete-me"})
          (assert (= (app.unit-manager:get "delete-me") nil) "unit should be unregistered")
          (assert (not (fs.exists file-path)) "source file should be deleted"))))))

(table.insert tests {:name "agent-units: space_unit_delete" :fn test-space-unit-delete})

(fn test-space-unit-delete-rejects-builtin []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "builtin-del.fnl"))
          (fs.write-file file-path "(fn init [] true)(fn drop [] true){:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "builtin-del"
                                          :module-name "builtin-del"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :builtin
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.delete" app))

          (local (ok err) (pcall def.run {:id "builtin-del"}))
          (assert (not ok) "delete should reject builtin unit")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_delete rejects builtin" :fn test-space-unit-delete-rejects-builtin})

;; ── Tool adapters: unit.eval ──

(fn test-space-unit-eval []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.eval" {}))
  (assert (= def.name "space_unit_eval") "mcp name should be space_unit_eval")

  (local result (json.loads (def.run {:expression "(+ 1 2)"})))
  (assert (= result 3) "eval should return sum")

  (local str-result (json.loads (def.run {:expression "\"hello\""})))
  (assert (= str-result "hello") "eval should return string")

  (set app.__eval-test :before)
  (def.run {:expression "(set app.__eval-test :after)"})
  (assert (= app.__eval-test :after) "eval should mutate app state")
  (set app.__eval-test nil))

(table.insert tests {:name "agent-units: space_unit_eval" :fn test-space-unit-eval})

(fn test-space-unit-eval-compile-error []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.eval" {}))
  (local (ok err) (pcall def.run {:expression "(((open"}))
  (assert (not ok) "eval should fail on broken syntax")
  (assert (string.find (tostring err) "compile error") "error should mention compile"))

(table.insert tests {:name "agent-units: space_unit_eval compile error" :fn test-space-unit-eval-compile-error})

;; ── Tool adapters: unit.snapshot and unit.restore ──

(fn test-space-unit-snapshot-restore []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "snap-unit.fnl"))
          (fs.write-file file-path
                         (.. "(fn init [] (set app.__snap-state {:value 0}) true)\n"
                             "(fn drop [] (set app.__snap-state nil) true)\n"
                             "(fn snapshot [] app.__snap-state)\n"
                             "(fn restore [state] (set app.__snap-state state) true)\n"
                             "{:init init :drop drop :snapshot snapshot :restore restore}"))
          (local unit (Units.ModuleUnit {:id "snap-unit"
                                          :module-name "snap-unit"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})
          (assert (= (. app.__snap-state :value) 0) "initial state")

          (set (. app.__snap-state :value) 42)
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})

          (local snap-def (adapters:resolve "unit.snapshot" app))
          (local snapshot-json (snap-def.run {:id "snap-unit"}))
          (local snapshot (json.loads snapshot-json))
          (assert (= snapshot.value 42) "snapshot should capture current state")

          (set (. app.__snap-state :value) 99)
          (local restore-def (adapters:resolve "unit.restore" app))
          (restore-def.run {:id "snap-unit" :state snapshot-json})
          (assert (= (. app.__snap-state :value) 42) "restore should bring back snapshot state")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_snapshot and restore" :fn test-space-unit-snapshot-restore})

;; ── Tool adapters: unit.connect-signal and disconnect-signal ──

(fn test-space-unit-connect-disconnect-signal []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "sig-unit.fnl"))
          (fs.write-file file-path
                         (.. "(fn init [] true)\n"
                             "(fn drop [] true)\n"
                             "{:init init :drop drop}"))
          (local unit (Units.ModuleUnit {:id "sig-unit"
                                          :module-name "sig-unit"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local sig (Signal))
          (set app.test-signal sig)

          ;; Direct signal test (bypass adapter)
          (set app.sigval nil)
          (unit:connect-signal "direct-test" sig (fn [payload] (set app.sigval payload)))
          (sig:emit :direct)
          (assert (= app.sigval :direct) "direct signal handler should be called")
          (unit:disconnect-signal "direct-test")

          ;; Adapter-based signal connect and disconnect
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local connect-def (adapters:resolve "unit.connect-signal" app))

          (set app.sigval nil)
          (connect-def.run {:id "sig-unit"
                            :signal-name "test-signal"
                            :handler-expr "(fn [payload] (set app.sigval payload))"})
          (sig:emit :foobar)
          (assert (= app.sigval :foobar) "adapter signal handler should fire")

          (local disconnect-def (adapters:resolve "unit.disconnect-signal" app))
          (disconnect-def.run {:id "sig-unit" :signal-name "test-signal"})

          ;; Verify disconnect removed the handler
          (set app.sigval nil)
          (sig:emit :shouldnt-see)
          (assert (= app.sigval nil) "disconnected handler should not fire")

          ;; Handler can use payload argument
          (set app.sigval nil)
          (connect-def.run {:id "sig-unit"
                            :signal-name "test-signal"
                            :handler-expr "(fn [payload] (set app.sigval (.. \"got:\" payload)))"})
          (sig:emit :xyz)
          (assert (= app.sigval "got:xyz") "handler should receive and use payload")
          (disconnect-def.run {:id "sig-unit" :signal-name "test-signal"})

          ;; Handler expression that evaluates to a pre-existing function
          (set app.existing-fn (fn [] (set app.sigval :from-existing)))
          (connect-def.run {:id "sig-unit"
                            :signal-name "test-signal"
                            :handler-expr "app.existing-fn"})
          (sig:emit :ignored)
          (assert (= app.sigval :from-existing) "handler should work with existing function reference")
          (disconnect-def.run {:id "sig-unit" :signal-name "test-signal"})

          ;; Handler compile error
          (local (bad-ok bad-err) (pcall connect-def.run
                                        {:id "sig-unit"
                                         :signal-name "test-signal"
                                         :handler-expr "(((not valid fennel"}))
          (assert (not bad-ok) "compile error should be caught")
          (assert (string.find (tostring bad-err) "compile error") "error should mention compile")

          (set app.test-signal nil)

          (set app.test-signal nil)
          (set app.sigval nil)
          (set app.existing-fn nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_connect_signal and disconnect"
                    :fn test-space-unit-connect-disconnect-signal})

;; ── End-to-end user unit lifecycle ──

(fn test-user-unit-lifecycle []
  "Create, inspect, edit, reload, snapshot, restore, delete a unit through adapters"
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})

          (set app.__e2e-val :phase0)

          (local create-def (adapters:resolve "unit.create" app))
          (local v1-source
            (.. "(fn init [] (set app.__e2e-val :phase1) true)\n"
                "(fn drop [] (set app.__e2e-val nil) true)\n"
                "(fn snapshot [] app.__e2e-val)\n"
                "(fn restore [state] (set app.__e2e-val state) true)\n"
                "{:init init :drop drop :snapshot snapshot :restore restore}"))
          (local created (json.loads (create-def.run {:id "e2e-unit" :source v1-source})))
          (assert created.loaded)
          (assert (= app.__e2e-val :phase1))

          (local inspect-def (adapters:resolve "unit.inspect" app))
          (local inspected (json.loads (inspect-def.run {:id "user-e2e-unit"})))
          (assert inspected.source-code)
          (assert (= inspected.source :user))

          (local snap-def (adapters:resolve "unit.snapshot" app))
          (local snapshot-json (snap-def.run {:id "user-e2e-unit"}))
          (assert (string.find snapshot-json "phase1"))

          (local edit-def (adapters:resolve "unit.edit" app))
          (local v2-source
            (.. "(fn init [] (set app.__e2e-val :phase2) true)\n"
                "(fn drop [] (set app.__e2e-val nil) true)\n"
                "(fn snapshot [] app.__e2e-val)\n"
                "(fn restore [_state] (set app.__e2e-val :reloaded) true)\n"
                "{:init init :drop drop :snapshot snapshot :restore restore}"))
          (edit-def.run {:id "user-e2e-unit" :source v2-source})
          (assert (= app.__e2e-val :reloaded) "edit reload should run new restore")

          (local reload-def (adapters:resolve "unit.reload" app))
          (reload-def.run {:id "user-e2e-unit"})
          (assert (= app.__e2e-val :reloaded) "reload should preserve state via restore")

          (local delete-def (adapters:resolve "unit.delete" app))
          (delete-def.run {:id "user-e2e-unit"})
          (assert (= (app.unit-manager:get "user-e2e-unit") nil) "unit should be gone after delete")
          (assert (= app.__e2e-val nil) "drop should have cleaned up")

          (set app.__e2e-val nil))))))

(table.insert tests {:name "agent-units: user unit lifecycle" :fn test-user-unit-lifecycle})

;; ── Tool adapters: unit.read-log ──

(fn test-space-unit-read-log-basic []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (assert (= def.name "space_unit_read_log"))

  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (fs.write-file log-path "line 1: info\nline 2: error something broke\nline 3: debug\n")
          (local result (def.run {}))
          (assert (string.find result "test.log") "result should mention log path")
          (assert (string.find result "line 1") "result should contain first line")
          (assert (string.find result "line 3") "result should contain last line"))))))

(table.insert tests {:name "agent-units: space_unit_read_log basic" :fn test-space-unit-read-log-basic})

(fn test-space-unit-read-log-lines []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (var content "")
          (for [i 1 10] (set content (.. content "line" i "\n")))
          (fs.write-file log-path content)
          (local result (def.run {:lines 3}))
          (assert (string.find result "10: line10") "lines=3 should show line 10")
          (assert (not (string.find result "\n1: ")) "lines=3 tail should not show line 1")
          (assert (not (string.find result "\n2: ")) "lines=3 should not show line 2"))))))

(table.insert tests {:name "agent-units: space_unit_read_log lines param" :fn test-space-unit-read-log-lines})

(fn test-space-unit-read-log-grep []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (fs.write-file log-path "aaa\nbbb ERROR found\nccc\n")
          (local result (def.run {:grep "ERROR"}))
          (assert (string.find result "bbb ERROR") "grep should find ERROR line")
          (assert (not (string.find result "aaa")) "grep should filter non-matching lines"))))))

(table.insert tests {:name "agent-units: space_unit_read_log grep filter" :fn test-space-unit-read-log-grep})

(fn test-space-unit-read-log-no-match []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (fs.write-file log-path "just info\nnothing here\n")
          (local result (def.run {:grep "NONEXISTENT"}))
          (assert (string.find result "no matching lines") "should report no matches"))))))

(table.insert tests {:name "agent-units: space_unit_read_log no matches" :fn test-space-unit-read-log-no-match})

(fn test-space-unit-read-log-offset-limit []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (var content "")
          (for [i 1 20] (set content (.. content "line " i "\n")))
          (fs.write-file log-path content)
          (local result (def.run {:offset 5 :limit 3}))
          (assert (string.find result "5: line 5") "offset=5 should start at line 5")
          (assert (string.find result "7: line 7") "limit=3 should include line 7")
          (assert (not (string.find result "line 8")) "limit=3 should stop before line 8"))))))

(table.insert tests {:name "agent-units: space_unit_read_log offset and limit" :fn test-space-unit-read-log-offset-limit})

(fn test-space-unit-read-log-file-not-found []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (fs.remove-all log-path)
          (local (ok err) (pcall def.run {}))
          (assert (not ok) "should error on missing file")
          (assert (string.find (tostring err) "not found") "error should mention not found"))))))

(table.insert tests {:name "agent-units: space_unit_read_log file not found" :fn test-space-unit-read-log-file-not-found})

(fn test-space-unit-read-log-empty-file []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (fs.write-file log-path "")
          (local (ok err) (pcall def.run {}))
          (assert (not ok) "should error on empty file")
          (assert (string.find (tostring err) "empty") "error should mention empty"))))))

(table.insert tests {:name "agent-units: space_unit_read_log empty file" :fn test-space-unit-read-log-empty-file})

(fn test-space-unit-read-log-no-trailing-empty []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.read-log" {}))
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "test.log"))
      (with-log-path log-path
        (fn []
          (fs.write-file log-path "one\ntwo\nthree\n")
          (local result (def.run {:lines 10}))
          ;; 3 content lines, no trailing empty line
          (assert (string.find result "1: one") "should contain line 1")
          (assert (string.find result "3: three") "should contain line 3")
          (assert (not (string.find result ": $" 1 false))
                  "should not contain a trailing empty numbered line"))))))

(table.insert tests {:name "agent-units: space_unit_read_log no trailing empty line" :fn test-space-unit-read-log-no-trailing-empty})

;; ── Tool adapters: unit.create-test ──

(fn test-space-unit-create-test []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "myunit.fnl"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "myunit"
                                          :module-name "myunit"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create-test" app))

          (local test-source "(fn main [] (print :ok)) {:main main :tests []}")
          (local result (def.run {:id "myunit"
                                  :test-name "init"
                                  :source test-source}))
          (assert (string.find result "created test") "should report test created")
          (local test-path (fs.join-path dir "myunit" "test-init.fnl"))
          (assert (fs.exists test-path) "test file should exist")
          (local content (fs.read-file test-path))
          (assert (string.find content "print :ok") "test file should contain test code")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_create_test" :fn test-space-unit-create-test})

(fn test-space-unit-create-test-rejects-builtin []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "built.fnl"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "built"
                                          :module-name "built"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :builtin
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create-test" app))

          (local (ok err) (pcall def.run {:id "built"
                                          :test-name "init"
                                          :source "..."}))
          (assert (not ok) "should reject builtin")
          (assert (string.find (tostring err) "built-in") "error should mention built-in")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_create_test rejects builtin" :fn test-space-unit-create-test-rejects-builtin})

(fn test-space-unit-create-test-invalid-name []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "m.fnl"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "m"
                                          :module-name "m"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.create-test" app))

          (local (ok err) (pcall def.run {:id "m" :test-name "bad name" :source "..."}))
          (assert (not ok) "should reject test-name with spaces")
          (assert (string.find (tostring err) "alphanumeric") "error should mention alphanumeric")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_create_test invalid test-name" :fn test-space-unit-create-test-invalid-name})

;; ── Tool adapters: unit.read-file ──

(fn test-space-unit-read-file []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-dir (fs.join-path dir "reader"))
          (fs.create-dirs unit-dir)
          (local init-path (fs.join-path unit-dir "init.fnl"))
          (local helper-path (fs.join-path unit-dir "helper.fnl"))
          (fs.write-file init-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (fs.write-file helper-path "helper-content")
          (local unit (Units.ModuleUnit {:id "user-reader"
                                          :module-name "reader"
                                          :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
                                          :source :user
                                          :owned-paths [init-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.read-file" app))

          (local result (def.run {:id "user-reader" :path "helper.fnl"}))
          (assert (= result "helper-content") "read-file should return unit file content")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_read_file" :fn test-space-unit-read-file})

(fn test-space-unit-read-file-flat-unit-test-file []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "flat.fnl"))
          (local test-dir (fs.join-path dir "flat"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (fs.create-dirs test-dir)
          (fs.write-file (fs.join-path test-dir "test-init.fnl") "flat-test-content")
          (local unit (Units.ModuleUnit {:id "user-flat"
                                          :module-name "flat"
                                          :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
                                          :source :user
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.read-file" app))

          (local source-result (def.run {:id "user-flat" :path "flat.fnl"}))
          (local test-result (def.run {:id "user-flat" :path "flat/test-init.fnl"}))
          (assert (string.find source-result "fn init" 1 true) "read-file should read flat unit source")
          (assert (= test-result "flat-test-content") "read-file should read flat unit test file")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_read_file flat unit test file" :fn test-space-unit-read-file-flat-unit-test-file})

(fn test-space-unit-read-file-rejects-escape []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-dir (fs.join-path dir "reader"))
          (fs.create-dirs unit-dir)
          (local init-path (fs.join-path unit-dir "init.fnl"))
          (fs.write-file init-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (fs.write-file (fs.join-path dir "secret.fnl") "secret")
          (local unit (Units.ModuleUnit {:id "user-reader"
                                          :module-name "reader"
                                          :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
                                          :source :user
                                          :owned-paths [init-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.read-file" app))

          (local (ok err) (pcall def.run {:id "user-reader" :path "../secret.fnl"}))
          (assert (not ok) "read-file should reject paths outside the unit directory")
          (assert (string.find (tostring err) "escapes") "error should mention escaping")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_read_file rejects escape" :fn test-space-unit-read-file-rejects-escape})

;; ── Tool adapters: unit.register ──

(fn test-space-unit-register []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local init-path (fs.join-path dir "reg-unit" "init.fnl"))
          (fs.create-dirs (fs.join-path dir "reg-unit"))
          (fs.write-file init-path (.. "(fn init [] (set app.__reg-val :registered) true)\n"
                                       "(fn drop [] (set app.__reg-val nil) true)\n"
                                       "{:init init :drop drop}"))

          (set app.__reg-val nil)
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.register" app))

          (local result (json.loads (def.run {:id "reg-unit"})))
          (assert (= result.id "user-reg-unit") "register should prefix user- onto id")
          (assert (= result.module-name "reg-unit") "register should expose module-name")
          (assert result.loaded "registered unit should be loaded")
          (assert (= app.__reg-val :registered) "load should have executed init")

          (local unit (app.unit-manager:get "user-reg-unit"))
          (assert unit "unit should be in manager")
          (assert (= unit.id "user-reg-unit"))
          (assert (= unit.module-name "reg-unit"))
          (assert (= unit.source :user))

          (unit:unload {})
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_register" :fn test-space-unit-register})

(fn test-space-unit-register-partial-init-cleanup []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local init-path (fs.join-path dir "reg-leaky" "init.fnl"))
          (fs.create-dirs (fs.join-path dir "reg-leaky"))

          (local Signal (require :signal))
          (local signal (Signal))
          (set app.__reg-partial-signal signal)
          (set app.__reg-partial-val nil)
          (set app.__reg-handler-called false)

          (fs.write-file init-path
            (.. "(var handler nil)\n"
                "(fn init []\n"
                "  (set app.__reg-partial-val :set-during-init)\n"
                "  (set handler (fn [_] (set app.__reg-handler-called true)))\n"
                "  (app.__reg-partial-signal:connect handler)\n"
                "  (error \"register init failure\")\n"
                "  true)\n"
                "(fn drop []\n"
                "  (when handler\n"
                "    (app.__reg-partial-signal:disconnect handler true))\n"
                "  (set app.__reg-partial-val nil)\n"
                "  true)\n"
                "{:init init :drop drop}"))

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.register" app))

          (local (ok err) (pcall def.run {:id "reg-leaky"}))
          (assert (not ok) "register should fail on init error")
          (assert (string.find (tostring err) "register init failure") "error should include init message")

          (assert (= (app.unit-manager:get "user-reg-leaky") nil) "unit should not be registered")

          (signal:emit "test-payload")
          (assert (not app.__reg-handler-called) "signal handler should be disconnected")

          (assert (= app.__reg-partial-val nil) "app state should be cleaned up by drop")

          (set app.__reg-partial-signal nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_register partial init cleanup" :fn test-space-unit-register-partial-init-cleanup})

(fn test-space-unit-register-submodule-cache-cleared []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-dir (fs.join-path dir "reg-sub"))
          (fs.create-dirs unit-dir)

          (fs.write-file (fs.join-path unit-dir "helper.fnl")
                         "{:value \"helper-loaded\"}")
          (fs.write-file (fs.join-path unit-dir "init.fnl")
                         (.. "(local helper (require :reg-sub.helper))\n"
                             "(fn init []\n"
                             "  (set app.__sub-helper-val helper.value)\n"
                             "  (error \"init boom after require\")\n"
                             "  true)\n"
                             "(fn drop []\n"
                             "  (set app.__sub-helper-val nil)\n"
                             "  (error \"drop also boom\"))\n"
                             "{:init init :drop drop}"))

          (set app.__sub-helper-val nil)
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.register" app))

          (local (ok err) (pcall def.run {:id "reg-sub"}))
          (assert (not ok) "register should fail")
          (local errstr (tostring err))
          (assert (string.find errstr "init boom") "error should include init message")
          (assert (string.find errstr "cleanup also failed") "error should mention cleanup failure")
          (assert (string.find errstr "drop also boom") "error should include drop message")

          (assert (= (app.unit-manager:get "user-reg-sub") nil) "unit should not be registered")
          (assert (= (. package.loaded "reg-sub") nil) "root module should be purged")
          (assert (= (. package.loaded "reg-sub.helper") nil) "submodule should be purged")

          (set app.__sub-helper-val nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_register submodule cache cleared on failure" :fn test-space-unit-register-submodule-cache-cleared})

(fn test-space-unit-register-loaded-existing []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local init-path (fs.join-path dir "re-exist" "init.fnl"))
          (fs.create-dirs (fs.join-path dir "re-exist"))
          (fs.write-file init-path (.. "(fn init [] (set app.__re-exist-val :exists) true)\n"
                                       "(fn drop [] (set app.__re-exist-val nil) true)\n"
                                       "{:init init :drop drop}"))

          (set app.__re-exist-val nil)
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.register" app))

          (local r1 (json.loads (def.run {:id "re-exist"})))
          (assert (= r1.id "user-re-exist") "first register should create user-re-exist")
          (assert r1.loaded "first register should load unit")
          (assert (= app.__re-exist-val :exists) "init should have run")

          (local r2 (json.loads (def.run {:id "user-re-exist"})))
          (assert r2.already-registered "register with user- prefix should return already-registered")
          (assert r2.loaded "loaded unit should still be loaded")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_register loaded existing user- prefix" :fn test-space-unit-register-loaded-existing})

(fn test-space-unit-register-unloaded-existing []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local init-path (fs.join-path dir "re-unload" "init.fnl"))
          (fs.create-dirs (fs.join-path dir "re-unload"))
          (fs.write-file init-path (.. "(fn init [] (set app.__re-unload-val :loaded) true)\n"
                                       "(fn drop [] (set app.__re-unload-val nil) true)\n"
                                       "{:init init :drop drop}"))

          (set app.__re-unload-val nil)
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.register" app))

          (local r1 (json.loads (def.run {:id "re-unload"})))
          (assert (= r1.id "user-re-unload"))
          (assert r1.loaded)
          (assert (= app.__re-unload-val :loaded))

          (local unit (app.unit-manager:get "user-re-unload"))
          (unit:unload {})
          (assert (not (unit:loaded?)) "unit should be unloaded")

          (set app.__re-unload-val nil)
          (local r2 (json.loads (def.run {:id "user-re-unload"})))
          (assert r2.reloaded "register with user- prefix on unloaded unit should reload")
          (assert r2.loaded "unit should be loaded after reload")
          (assert (= app.__re-unload-val :loaded) "init should have run after reload")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_register unloaded existing user- prefix" :fn test-space-unit-register-unloaded-existing})

(fn test-space-unit-register-rejects-empty-source-dir []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.register" app))
          (local (ok err) (pcall def.run {:id "user-"}))
          (assert (not ok) "id 'user-' should be rejected")
          (local errstr (tostring err))
          (assert (string.find errstr "source directory name" 1 true)
                  (.. "error should mention source directory, got: " errstr))
          (assert (= (app.unit-manager:count) 0) "no unit should be registered")
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_register rejects empty source dir" :fn test-space-unit-register-rejects-empty-source-dir})

(fn test-space-unit-delete-directory []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-dir (fs.join-path dir "del-dir"))
          (fs.create-dirs unit-dir)
          (fs.write-file (fs.join-path unit-dir "init.fnl")
                         "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (fs.write-file (fs.join-path unit-dir "render.fnl")
                         "{:render (fn [] nil)}")
          (fs.write-file (fs.join-path unit-dir "test-init.fnl")
                         "{:tests []}")

          (local unit (Units.ModuleUnit {:id "user-del-dir"
                                          :module-name "del-dir"
                                          :module-paths (.. dir "/?.fnl;" dir "/?/init.fnl")
                                          :source :user
                                          :owned-paths [(fs.join-path unit-dir "init.fnl")]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          ;; Verify files exist before delete
          (assert (fs.exists (fs.join-path unit-dir "render.fnl")) "submodule should exist")
          (assert (fs.exists (fs.join-path unit-dir "test-init.fnl")) "test file should exist")

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.delete" app))

          (def.run {:id "user-del-dir"})
          (assert (= (app.unit-manager:get "user-del-dir") nil) "unit should be gone")
          ;; Entire directory should be removed
          (assert (not (fs.exists unit-dir)) "unit directory should be removed")
          (assert (not (fs.exists (fs.join-path unit-dir "render.fnl")))
                  "submodule should be deleted too"))))))

(table.insert tests {:name "agent-units: space_unit_delete removes directory" :fn test-space-unit-delete-directory})

;; ── Tool adapters: unit.run-tests ──

(fn test-space-unit-run-tests-not-found []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.run-tests" app))
  (local (ok err) (pcall def.run {:id "nonexistent"}))
  (assert (not ok) "should error for nonexistent unit"))

(table.insert tests {:name "agent-units: space_unit_run_tests unit not found" :fn test-space-unit-run-tests-not-found})

(fn test-space-unit-run-tests-rejects-builtin []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local file-path (fs.join-path dir "builtin-run.fnl"))
          (fs.write-file file-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "builtin-run"
                                          :module-name "builtin-run"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :builtin
                                          :owned-paths [file-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.run-tests" app))

          (local (ok err) (pcall def.run {:id "builtin-run"}))
          (assert (not ok) "should reject builtin")
          (assert (string.find (tostring err) "built-in") "error should mention built-in")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_run_tests rejects builtin" :fn test-space-unit-run-tests-rejects-builtin})

(fn test-space-unit-run-tests-happy []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "htest.fnl"))
          (fs.write-file unit-path
                         "(fn init [] true)\n(fn drop [] true)\n{:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "user-htest"
                                          :module-name "htest"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local test-source
            (.. "(local runner (require :tests/runner))\n"
                "(local Flex (require :flex))\n"
                "(fn main []\n"
                "  (local fs (require :fs))\n"
                "  (assert Flex \"repo module with macros should load\")\n"
                "  (fs.write-file \"" dir "/runner-ran\" \"1\")\n"
                "  (runner.run-tests\n"
                "    {:name \"htest\"\n"
                "     :tests [{:name \"pass\" :fn (fn [] true)}]}))\n"
                "{:main main :tests [{:name \"pass\" :fn (fn [] true)}]}"))
          (local test-dir (fs.join-path dir "htest"))
          (fs.create-dirs test-dir)
          (local test-path (fs.join-path test-dir "test-init.fnl"))
          (fs.write-file test-path test-source)

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.run-tests" app))

          (local result (def.run {:id "user-htest"}))
          (assert (string.find result "TESTS PASSED") (.. "should pass, got: " result))
          ;; Prove main actually ran (not just a false positive from module require)
          (assert (fs.exists (fs.join-path dir "runner-ran")) "main should have run")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_run_tests happy-path" :fn test-space-unit-run-tests-happy})

;; ── Missing error-path tests for existing tools ──

(fn test-space-unit-inspect-not-found []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.inspect" app))
  (local (ok err) (pcall def.run {:id "nonexistent"}))
  (assert (not ok) "should error for nonexistent unit"))

(table.insert tests {:name "agent-units: space_unit_inspect not found" :fn test-space-unit-inspect-not-found})

(fn test-space-unit-reload-not-found []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.reload" app))
  (local (ok err) (pcall def.run {:id "nonexistent"}))
  (assert (not ok) "should error for nonexistent unit"))

(table.insert tests {:name "agent-units: space_unit_reload not found" :fn test-space-unit-reload-not-found})

(fn test-space-unit-snapshot-not-found []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.snapshot" app))
  (local (ok err) (pcall def.run {:id "nonexistent"}))
  (assert (not ok) "should error for nonexistent unit"))

(table.insert tests {:name "agent-units: space_unit_snapshot not found" :fn test-space-unit-snapshot-not-found})

(fn test-space-unit-restore-not-found []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.restore" app))
  (local (ok err) (pcall def.run {:id "nonexistent" :state "{}"}))
  (assert (not ok) "should error for nonexistent unit"))

(table.insert tests {:name "agent-units: space_unit_restore not found" :fn test-space-unit-restore-not-found})

(fn test-space-unit-connect-signal-not-found []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "s.fnl"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "s"
                                          :module-name "s"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.connect-signal" app))

          (local (ok err) (pcall def.run {:id "s"
                                          :signal-name "nonexistent-signal"
                                          :handler-expr "(fn [_] nil)"}))
          (assert (not ok) "should error for nonexistent signal")
          (assert (string.find (tostring err) "not found") "error should mention not found")

          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_connect_signal signal not found" :fn test-space-unit-connect-signal-not-found})

(fn test-space-unit-connect-signal-non-fn []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "sf.fnl"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "sf"
                                          :module-name "sf"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :user
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (set app.test-sig (Signal))
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.connect-signal" app))

          (local (ok err) (pcall def.run {:id "sf"
                                          :signal-name "test-sig"
                                          :handler-expr "\"not a function\""}))
          (assert (not ok) "should error for non-function handler")
          (assert (string.find (tostring err) "function") "error should mention function")

          (set app.test-sig nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_connect_signal non-function handler" :fn test-space-unit-connect-signal-non-fn})

(fn test-space-unit-connect-signal-rejects-builtin []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "bsc.fnl"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "bsc"
                                          :module-name "bsc"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :builtin
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (set app.test-sig (Signal))
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.connect-signal" app))

          (local (ok err) (pcall def.run {:id "bsc"
                                          :signal-name "test-sig"
                                          :handler-expr "(fn [_] nil)"}))
          (assert (not ok) "should reject builtin unit for signal connect")
          (assert (string.find (tostring err) "built-in") "error should mention built-in")

          (set app.test-sig nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_connect_signal rejects builtin" :fn test-space-unit-connect-signal-rejects-builtin})

(fn test-space-unit-disconnect-rejects-builtin []
  (with-temp-dir
    (fn [dir]
      (with-test-unit-mgr dir
        (fn []
          (local unit-path (fs.join-path dir "bsd.fnl"))
          (fs.write-file unit-path "(fn init [] true) (fn drop [] true) {:init init :drop drop}")
          (local unit (Units.ModuleUnit {:id "bsd"
                                          :module-name "bsd"
                                          :module-paths (.. dir "/?.fnl")
                                          :source :builtin
                                          :owned-paths [unit-path]
                                          :suppress-run-main? false}))
          (app.unit-manager:register unit)
          (unit:load {})

          (set app.test-sig (Signal))
          (local adapters (ToolAdapterRegistry {}))
          (BuiltinUnits.register {:tool-adapters adapters})
          (local def (adapters:resolve "unit.disconnect-signal" app))

          (local (ok err) (pcall def.run {:id "bsd" :signal-name "test-sig"}))
          (assert (not ok) "should reject builtin unit for signal disconnect")
          (assert (string.find (tostring err) "built-in") "error should mention built-in")

          (set app.test-sig nil)
          (app.unit-manager:clear))))))

(table.insert tests {:name "agent-units: space_unit_disconnect_signal rejects builtin" :fn test-space-unit-disconnect-rejects-builtin})

(fn test-space-unit-disconnect-not-found []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.disconnect-signal" app))
  (local (ok err) (pcall def.run {:id "nonexistent" :signal-name "anything"}))
  (assert (not ok) "should error for nonexistent unit"))

(table.insert tests {:name "agent-units: space_unit_disconnect_signal not found" :fn test-space-unit-disconnect-not-found})

(fn test-space-unit-eval-runtime-error []
  (local adapters (ToolAdapterRegistry {}))
  (BuiltinUnits.register {:tool-adapters adapters})
  (local def (adapters:resolve "unit.eval" {}))
  (local (ok err) (pcall def.run {:expression "(error \"boom\")"}))
  (assert (not ok) "should error on runtime exception")
  (assert (string.find (tostring err) "runtime error") "error should mention runtime"))

(table.insert tests {:name "agent-units: space_unit_eval runtime error" :fn test-space-unit-eval-runtime-error})

;; ── Preset manager integration ──

(fn test-preset-manager-has-unit-tools []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg
                             :tool-adapters adapters
                             :app app
                             :context {:surface :any :canvas-visible? false}}))
  (BuiltinUnits.register mgr)

  (local presets (mgr:get-active-presets))
  (var found-units-discover? false)
  (each [_ p (ipairs presets)]
    (when (= p.name "units-discover-tools")
      (set found-units-discover? true)))
  (assert found-units-discover? "units-discover-tools preset should be active")

  (local defs (mgr:get-tool-defs))
  (var found-space-unit-list? false)
  (each [_ def (ipairs defs)]
    (when (= def.name "space_unit_list")
      (set found-space-unit-list? true)))
  (assert found-space-unit-list? "space_unit_list should be in tool defs"))

(table.insert tests {:name "agent-units: preset manager integration" :fn test-preset-manager-has-unit-tools})

(fn test-unit-tool-risk-presets []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg
                             :tool-adapters adapters
                             :app app
                             :context {:surface :any :canvas-visible? false}}))
  (BuiltinUnits.register mgr)
  (local discover (reg:get "units-discover-tools"))
  (local runtime-preset (reg:get "units-runtime-tools"))
  (local signal-preset (reg:get "units-signal-tools"))
  (local edit-preset (reg:get "units-edit-tools"))
  (assert (= discover.risk :normal) "discover tools should remain normal risk")
  (assert (= runtime-preset.risk :normal) "runtime tools should not require approval")
  (assert (= signal-preset.risk :shell) "signal tools should require shell approval")
  (assert (= edit-preset.risk :filesystem-write)
          "test-file creation tools should require filesystem-write approval")
  (fn contains? [items value]
    (var found? false)
    (each [_ item (ipairs items)]
      (when (= item value)
        (set found? true)))
    found?)
  (each [_ tool-id (ipairs ["unit.edit" "unit.edit-file" "unit.apply-patch"
                            "unit.register" "unit.reload"
                            "unit.disconnect-signal" "unit.run-tests" "unit.snapshot"])]
    (assert (not (contains? discover.tool-ids tool-id))
            (.. tool-id " must not be in discover tools"))
    (assert (not (contains? edit-preset.tool-ids tool-id))
            (.. tool-id " must not be filesystem-write risk"))
    (assert (contains? runtime-preset.tool-ids tool-id)
            (.. tool-id " should be in runtime normal preset")))
  (assert (contains? signal-preset.tool-ids "unit.connect-signal")
          "unit.connect-signal should be in signal shell preset")
  (assert (not (contains? runtime-preset.tool-ids "unit.connect-signal"))
          "unit.connect-signal should not be in runtime normal preset"))

(table.insert tests {:name "agent-units: scoped runtime unit tools are normal risk"
                      :fn test-unit-tool-risk-presets})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "agent-units"
                       :tests tests})))

{:name "agent-units"
 :tests tests
 :main main}
