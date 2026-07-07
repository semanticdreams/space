(local Launcher (require :launcher))

(local tests [])

(fn with-launchables-dir [dir-name f]
  (local original-engine app.engine)
  (local assets-root (or (os.getenv "SPACE_ASSETS_PATH") "."))
  (local dir (.. assets-root "/lua/tests/data/launchables/" dir-name))
  (set app.engine {:get-asset-path (fn [path]
                                    (if (= path "lua/launchables")
                                        dir
                                        path))})
  (f)
  (set app.engine original-engine))

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
(table.insert tests {:name "Repository Workbench launchable interface" :fn repo-workbench-launchable-has-interface})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "launchables"
                       :tests tests})))

{:name "launchables"
 :tests tests
 :main main}
