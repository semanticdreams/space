(local Launcher (require :launcher))
(local fs (require :fs))
(local tempfile (require :tempfile))
(local Units (require :units))

(local tests [])

(fn with-launchables-dir [dir-name f]
  (local original-engine app.engine)
  (local registry (Launcher {}))
  (local runtime-snap (registry:snapshot-runtime))
  (local assets-root (or (os.getenv "SPACE_ASSETS_PATH") "."))
  (local dir (.. assets-root "/lua/tests/data/launchables/" dir-name))
  (registry:clear-runtime)
  (set app.engine {:get-asset-path (fn [path]
                                      (if (= path "lua/launchables")
                                          dir
                                          path))})
  (local (ok result) (pcall f))
  (set app.engine original-engine)
  (registry:restore-runtime runtime-snap)
  (if ok result (error result)))

(fn launchables-register-list-search []
  (with-launchables-dir
    "basic"
    (fn []
      (local registry (Launcher {}))
      (local items (registry:list))
      (assert (= (length items) 2))
      (assert (= (. (. items 1) :name) "Alpha"))
      (assert (= (. (. items 2) :name) "beta"))
      (local filtered (registry:search "alp"))
      (assert (= (length filtered) 1))
      (assert (= (. (. filtered 1) :name) "Alpha")))))

(fn launchables-duplicate-register-errors []
  (with-launchables-dir
    "duplicates"
    (fn []
      (local registry (Launcher {}))
      (local (ok _err)
        (pcall (fn []
                 (registry:list))))
      (assert (not ok) "Duplicate register should error"))))

(fn launcher-run-dispatches-entry []
  (with-launchables-dir
    "run"
    (fn []
      (local registry (Launcher {}))
      (set app.test-launcher-ran nil)
      (registry:run "Beta")
      (assert (= app.test-launcher-ran :beta))
      (registry:run "Alpha")
      (assert (= app.test-launcher-ran :alpha)))))

(fn launcher-runtime-registration-is-shared []
  (with-launchables-dir
    "basic"
    (fn []
      (local first (Launcher {}))
      (local second (Launcher {}))
      (set app.test-runtime-launchable nil)
      (first:register {:name "Runtime Game"
                       :run (fn []
                              (set app.test-runtime-launchable :ran))})
      (local entry (second:get "Runtime Game"))
      (assert entry "runtime launchable should be visible to other Launcher instances")
      (second:run "Runtime Game")
      (assert (= app.test-runtime-launchable :ran))
      (second:unregister "Runtime Game")
      (assert (= (first:get "Runtime Game") nil)))))

(fn launcher-runtime-duplicate-errors []
  (with-launchables-dir
    "basic"
    (fn []
      (local registry (Launcher {}))
      (registry:register {:name "Runtime Game" :run (fn [] nil)})
      (local (runtime-ok runtime-err)
        (pcall #(registry:register {:name "Runtime Game" :run (fn [] nil)})))
      (assert (not runtime-ok) "duplicate runtime launchable should error")
      (assert (string.find (tostring runtime-err) "already registered" 1 true))
      (local (disk-ok disk-err)
        (pcall #(registry:register {:name "Alpha" :run (fn [] nil)})))
      (assert (not disk-ok) "runtime launchable should not override disk launchable")
      (assert (string.find (tostring disk-err) "already registered" 1 true)))))

(fn launcher-runtime-registration-captures-require-context []
  (with-launchables-dir
    "basic"
    (fn []
      (local registry (Launcher {}))
      (local original-require _G.require)
      (set app.test-runtime-require nil)
      (set _G.require
           (fn [name]
             (if (= name :runtime-dep)
                 {:value :captured}
                 (original-require name))))
      (registry:register {:name "Runtime Requires"
                          :run (fn []
                                 (local dep (require :runtime-dep))
                                 (set app.test-runtime-require dep.value))})
      (set _G.require original-require)
      (registry:run "Runtime Requires")
      (assert (= app.test-runtime-require :captured)
              "runtime launchable should run with registration require context")
      (assert (= _G.require original-require)
              "launcher should restore require after runtime run"))))

(fn launcher-runtime-registration-captures-fennel-path []
  (with-launchables-dir
    "basic"
    (fn []
      (local registry (Launcher {}))
      (local temp (tempfile.TemporaryDirectory {:prefix "launcher-runtime-path-"}))
      (local fennel (require :fennel))
      (local old-path fennel.path)
      (fs.create-dirs (fs.join-path temp.path "runtime-unit"))
      (fs.write-file (fs.join-path temp.path "runtime-unit" "dep.fnl")
                     "{:value :path-captured}")
      (set fennel.path (.. temp.path "/?.fnl;" temp.path "/?/init.fnl;" old-path))
      (registry:register {:name "Runtime Path Requires"
                          :run (fn []
                                 (local dep (require :runtime-unit/dep))
                                 (set app.test-runtime-path dep.value))})
      (set fennel.path old-path)
      (registry:run "Runtime Path Requires")
      (assert (= app.test-runtime-path :path-captured)
              "runtime launchable should run with registration fennel.path")
      (assert (= fennel.path old-path)
              "launcher should restore fennel.path after runtime run")
      (temp:drop))))

(fn launcher-runtime-registration-captures-module-unit-path []
  (with-launchables-dir
    "basic"
    (fn []
      (local registry (Launcher {}))
      (local old-launcher app.launcher)
      (local temp (tempfile.TemporaryDirectory {:prefix "launcher-module-unit-path-"}))
      (local unit-dir (fs.join-path temp.path "lazy-unit"))
      (fs.create-dirs unit-dir)
      (fs.write-file
        (fs.join-path unit-dir "init.fnl")
        (.. "(fn init []\n"
            "  (app.launcher:register {:name \"Lazy Unit\"\n"
            "                          :run (fn []\n"
            "                                 (local dep (require :lazy-unit/dep))\n"
            "                                 (set app.test-lazy-unit dep.value))}))\n"
            "(fn drop []\n"
            "  (app.launcher:unregister \"Lazy Unit\"))\n"
            "{:init init :drop drop}"))
      (fs.write-file (fs.join-path unit-dir "dep.fnl") "{:value :lazy-loaded}")
      (set app.launcher registry)
      (local unit
        (Units.ModuleUnit {:id "user-lazy-unit"
                           :module-name "lazy-unit"
                           :module-paths (.. temp.path "/?.fnl;" temp.path "/?/init.fnl")
                           :source :user
                           :owned-paths [unit-dir (fs.join-path unit-dir "init.fnl")]}))
      (unit:load {})
      (registry:run "Lazy Unit")
      (assert (= app.test-lazy-unit :lazy-loaded)
              "module-unit runtime launchable should lazy-load owned submodules")
      (unit:unload {})
      (set app.launcher old-launcher)
      (temp:drop))))

(fn repo-workbench-launchable-has-interface []
  (local launchable (require :launchables/repository-workbench))
  (assert (= (type launchable.name) "string") "launchable must have :name")
  (assert (= (type launchable.run) "function") "launchable must have :run")
  (assert (= (type launchable.open-panel) "function") "launchable must have :open-panel")
  (assert (= (type launchable.restore) "function") "launchable must have :restore")
  (assert (= (type launchable.kind) "string") "launchable must have :kind")
  (assert (= (type launchable.restorer-module) "string") "launchable must have :restorer-module")
  (assert (= launchable.name "Repository Workbench")
          (.. "expected 'Repository Workbench' got " (tostring launchable.name))))

(table.insert tests {:name "Launchables registers, lists, searches" :fn launchables-register-list-search})
(table.insert tests {:name "Launchables duplicate register errors" :fn launchables-duplicate-register-errors})
(table.insert tests {:name "Launcher run dispatches entry" :fn launcher-run-dispatches-entry})
(table.insert tests {:name "Launcher runtime registrations are shared" :fn launcher-runtime-registration-is-shared})
(table.insert tests {:name "Launcher runtime duplicate registration errors" :fn launcher-runtime-duplicate-errors})
(table.insert tests {:name "Launcher runtime captures require context" :fn launcher-runtime-registration-captures-require-context})
(table.insert tests {:name "Launcher runtime captures fennel path" :fn launcher-runtime-registration-captures-fennel-path})
(table.insert tests {:name "Launcher runtime captures ModuleUnit path" :fn launcher-runtime-registration-captures-module-unit-path})
(table.insert tests {:name "Repository Workbench launchable interface" :fn repo-workbench-launchable-has-interface})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "launchables"
                       :tests tests})))

{:name "launchables"
 :tests tests
 :main main}
