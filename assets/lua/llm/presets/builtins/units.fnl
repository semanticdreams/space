(local path-utils (require :path-utils))
(local path-separator? path-utils.path-separator?)
(local windows? (= (string.sub (or package.config "") 1 1) "\\"))
(local sep-cc (if windows? "\\\\/" "/"))   ;; regex character class for path separator

(fn require-unit-manager [app tool-name]
  (assert app.unit-manager (.. tool-name " requires app.unit-manager"))
  app.unit-manager)

(fn unit-source-file [app unit]
  (var file nil)
  (each [_ path (ipairs (or unit.owned-paths []))]
    (when (and (not file) (string.match (or path "") "%.fnl$"))
      (set file path)))
  file)

(fn path-basename [path]
  (string.match path (.. "[^" sep-cc "]+$")))

(fn assert-user-unit [app unit-id tool-name]
  (local unit (app.unit-manager:get unit-id))
  (assert unit (.. tool-name ": unit not found: " unit-id))
  (assert (not (= unit.source :builtin))
          (.. tool-name ": cannot modify built-in unit: " unit-id))
  unit)


(fn path-under? [path parent-dir]
  (local fs (require :fs))
  (if (not (and path parent-dir))
      false
      (let [normalized (fs.absolute path)
            normalized-parent (fs.absolute parent-dir)
            parent-len (# normalized-parent)]
        (when (and (>= (# normalized) parent-len)
                   (= (string.sub normalized 1 parent-len) normalized-parent)
                   (or (= (# normalized) parent-len)
                       (path-separator? (string.sub normalized (+ parent-len 1) (+ parent-len 1)))))
          (var current normalized)
          (var ok true)
          (while (and ok (>= (# current) (# normalized-parent)))
            (local stat (fs.stat current))
            (when (and stat.exists stat.is-symlink)
              (set ok false))
            (when ok
              (set current (fs.parent current))))
          ok))))

(fn unit-root-dir [app unit tool-name]
  (local fs (require :fs))
  (local file (unit-source-file app unit))
  (assert file (.. tool-name ": unit " unit.id " has no source file"))
  (local parent (fs.parent file))
  (local name (path-basename file))
  (if (and (= name "init.fnl")
           parent
           (not= (fs.absolute parent) (fs.absolute app.code-dir)))
      parent
      (fs.parent file)))

(fn resolve-unit-file [app unit relative-path tool-name allow-create?]
  (local fs (require :fs))
  (assert (= (type relative-path) "string")
          (.. tool-name " requires a relative string :path"))
  (assert (> (# relative-path) 0) (.. tool-name " :path must not be empty"))
  (assert (not (or (string.match relative-path "^/")
                  (string.match relative-path "^%a:[\\/]")))
          (.. tool-name " :path must be relative to the unit directory"))
  (assert (not (string.find relative-path "\0" 1 true))
          (.. tool-name " :path contains a NUL byte"))
  (local root (unit-root-dir app unit tool-name))
  (local file (fs.join-path root relative-path))
  (assert (path-under? file root)
          (.. tool-name " :path escapes the unit directory"))
  (assert (path-under? file app.code-dir)
          (.. tool-name " :path escapes the user code directory"))
  (local source-file (unit-source-file app unit))
  (when (= (fs.absolute root) (fs.absolute app.code-dir))
    (assert (= (fs.absolute file) (fs.absolute source-file))
            (.. tool-name " cannot edit sibling unit files")))
  (if (not allow-create?)
      (assert (fs.exists file) (.. tool-name " file not found: " file)))
  file)

(fn resolve-readable-unit-file [app unit relative-path tool-name]
  (local fs (require :fs))
  (assert (= (type relative-path) "string")
          (.. tool-name " requires a relative string :path"))
  (assert (> (# relative-path) 0) (.. tool-name " :path must not be empty"))
  (assert (not (or (string.match relative-path "^/")
                  (string.match relative-path "^%a:[\\/]")))
          (.. tool-name " :path must be relative to the unit directory"))
  (assert (not (string.find relative-path "\0" 1 true))
          (.. tool-name " :path contains a NUL byte"))
  (local root (unit-root-dir app unit tool-name))
  (local file (fs.join-path root relative-path))
  (assert (path-under? file app.code-dir)
          (.. tool-name " :path escapes the user code directory"))
  (local source-file (unit-source-file app unit))
  (if (= (fs.absolute root) (fs.absolute app.code-dir))
      (do
        (local module-dir (fs.join-path app.code-dir (or unit.module-name unit.id)))
        (assert (or (= (fs.absolute file) (fs.absolute source-file))
                    (path-under? file module-dir))
                (.. tool-name " cannot read sibling unit files")))
      (assert (path-under? file root)
              (.. tool-name " :path escapes the unit directory")))
  (assert (fs.exists file) (.. tool-name " file not found: " file))
  file)

(fn validate-fennel-source [file source tool-name]
  (when (string.match file "%.fnl$")
    (local fennel (require :fennel))
    (local (compile-ok compile-err) (pcall fennel.compile-string source
                                           {:filename file}))
    (assert compile-ok (.. tool-name " source does not compile: " (tostring compile-err)))))

(fn validate-unit-exports [unit]
  (local load-key (or unit.load-export "init"))
  (local unload-key (or unit.unload-export "drop"))
  (local mod (. package.loaded unit.module-name))
  (if (and mod
           (= (type (. mod load-key)) :function)
           (= (type (. mod unload-key)) :function))
      nil
      (if (or (not mod) (not= (type (. mod load-key)) :function))
          load-key
          unload-key)))

(fn reload-unit-with-rollback! [app unit file old-source tool-name]
  (local fs (require :fs))
  (local json (require :json))
  (local source (fs.read-file file))
  (local (ok err)
    (pcall
      (fn []
        (validate-fennel-source file source tool-name)
        (app.unit-manager:reload-unit unit.id {:source :agent-edit}))))
  (if ok
      (do
        (local missing (validate-unit-exports unit))
        (if (not missing)
            (json.dumps {:id unit.id :file file :reloaded true})
            (do
              (local (purge-ok purge-err) (pcall #(unit:force-purge-module-cache!)))
              (fs.write-file file old-source)
              (local (recover-ok recover-err) (pcall #(unit:reload {})))
              (error (.. tool-name " failed, module exports invalid: missing " missing
                         (if (not purge-ok) (.. " (purge also failed: " (tostring purge-err) ")") "")
                         (if (not recover-ok) (.. " (recovery reload also failed: " (tostring recover-err) ")") ""))))))
      (do
        (local (unload-ok unload-err)
          (if (not (unit:loaded?))
              (pcall #(unit:unload {}))
              (values true nil)))
        (local (purge-ok purge-err) (pcall #(unit:force-purge-module-cache!)))
        (fs.write-file file old-source)
        (local (recover-ok recover-err)
          (pcall #(if (unit:loaded?)
                      (app.unit-manager:reload-unit unit.id {:source :agent-edit-recover})
                      (unit:load {}))))
        (error (.. tool-name " failed, source restored: " (tostring err)
                   (if (not unload-ok) (.. " (unload also failed: " (tostring unload-err) ")") "")
                   (if (not purge-ok) (.. " (purge also failed: " (tostring purge-err) ")") "")
                   (if (not recover-ok) (.. " (recovery also failed: " (tostring recover-err) ")") ""))))))

(fn write-unit-file-and-reload! [app unit file source tool-name]
  (local fs (require :fs))
  (validate-fennel-source file source tool-name)
  (local old-source (fs.read-file file))
  (fs.write-file file source)
  (reload-unit-with-rollback! app unit file old-source tool-name))

(fn write-new-unit-file-and-reload! [app unit file source tool-name]
  (local fs (require :fs))
  (local json (require :json))
  (assert (not (fs.exists file)) (.. tool-name " file already exists: " file))
  (validate-fennel-source file source tool-name)
  (local unit-root (unit-root-dir app unit tool-name))
  (var created-dirs [])
  (fn collect-missing-dirs! [target-file]
    (local target-parent (fs.parent target-file))
    (when target-parent
      (var current target-parent)
      (while (and current
                  (path-under? current unit-root)
                  (not= (fs.absolute current) (fs.absolute unit-root)))
        (when (not (fs.exists current))
          (table.insert created-dirs current))
        (set current (fs.parent current)))))
  (collect-missing-dirs! file)
  (fn rollback-new-file []
    (fs.remove-all file)
    (each [_ dir (ipairs created-dirs)]
      (pcall #(fs.remove dir))))
  (local (write-ok write-err)
    (pcall
      (fn []
        (when (> (length created-dirs) 0)
          (fs.create-dirs (fs.parent file)))
        (fs.write-file file source))))
  (when (not write-ok)
    (rollback-new-file)
    (error (.. tool-name " failed to write file: " (tostring write-err))))
  (local (reload-ok reload-err)
    (pcall #(app.unit-manager:reload-unit unit.id {:source :agent-edit})))
  (if reload-ok
      (do
        (local missing (validate-unit-exports unit))
        (if (not missing)
            (json.dumps {:id unit.id :file file :created true :reloaded true})
            (do
              (local (purge-ok purge-err) (pcall #(unit:force-purge-module-cache!)))
              (rollback-new-file)
              (local (recover-ok recover-err) (pcall #(unit:reload {})))
              (error (.. tool-name " failed, module exports invalid: missing " missing
                         (if (not purge-ok) (.. " (purge also failed: " (tostring purge-err) ")") "")
                         (if (not recover-ok) (.. " (recovery reload also failed: " (tostring recover-err) ")") ""))))))
      (do
        (local (unload-ok unload-err)
          (if (not (unit:loaded?))
              (pcall #(unit:unload {}))
              (values true nil)))
        (local (purge-ok purge-err) (pcall #(unit:force-purge-module-cache!)))
        (rollback-new-file)
        (local (recover-ok recover-err)
          (pcall #(if (unit:loaded?)
                      (app.unit-manager:reload-unit unit.id {:source :agent-edit-recover})
                      (unit:load {}))))
        (error (.. tool-name " failed, new file removed: " (tostring reload-err)
                   (if (not unload-ok) (.. " (unload also failed: " (tostring unload-err) ")") "")
                   (if (not purge-ok) (.. " (purge also failed: " (tostring purge-err) ")") "")
                   (if (not recover-ok) (.. " (recovery also failed: " (tostring recover-err) ")") ""))))))

(fn replace-exact-text [source old new]
  (assert (= (type old) "string") "space_unit_apply_patch requires string :old")
  (assert (= (type new) "string") "space_unit_apply_patch requires string :new")
  (assert (> (# old) 0) "space_unit_apply_patch :old must not be empty")
  (local (start-pos end-pos) (string.find source old 1 true))
  (assert start-pos "space_unit_apply_patch :old text was not found")
  (local (next-pos) (string.find source old (+ end-pos 1) true))
  (assert (not next-pos) "space_unit_apply_patch :old text matched more than once")
  (.. (string.sub source 1 (- start-pos 1))
      new
      (string.sub source (+ end-pos 1))))

(fn patch-mode [args]
  (local has-patch (not= args.patch nil))
  (local has-old (not= args.old nil))
  (local has-new (not= args.new nil))
  (assert (not (and has-patch (or has-old has-new)))
          "space_unit_apply_patch requires either :patch or :old/:new, not both")
  (assert (or has-patch (and has-old has-new))
          "space_unit_apply_patch requires either :patch or both :old and :new")
  (assert (or has-patch (= has-old has-new))
          "space_unit_apply_patch requires both :old and :new for exact replacement")
  (if has-patch :patch :replace))

(fn handle-unit-create-test [app args]
   (local unit (assert-user-unit app args.id "space_unit_create_test"))
   (assert (string.match args.test-name "^[%w_-]+$")
           "test-name must be alphanumeric with underscores and hyphens")
   (local fs (require :fs))
   (local test-dir (fs.join-path app.code-dir (or unit.module-name unit.id)))
   (assert (path-under? test-dir app.code-dir)
           (.. "test directory outside code directory: " test-dir))
   (when (not (fs.exists test-dir))
     (fs.create-dirs test-dir))
   (local test-path (fs.join-path test-dir (.. "test-" args.test-name ".fnl")))
   (assert (path-under? test-path app.code-dir)
           (.. "test path outside code directory: " test-path))
   (fs.write-file test-path args.source)
   (.. "created test " test-path " (run with space_unit_run_tests "
       "{id \"" args.id "\" test-name \"" args.test-name "\"})"))

 (fn handle-unit-read-file [app args]
   (local unit (assert-user-unit app args.id "space_unit_read_file"))
   (local file (resolve-readable-unit-file app unit args.path "space_unit_read_file"))
   (local fs (require :fs))
   (fs.read-file file))

 (fn handle-unit-run-tests [app args]
   (local unit (app.unit-manager:get args.id))
   (assert unit (.. "unit not found: " args.id))
   (assert (not (= unit.source :builtin))
           "space_unit_run_tests: cannot run tests for built-in unit")
   (assert app.code-dir "space_unit_run_tests requires app.code-dir")
   (local test-name (or args.test-name "init"))
   (local name (or unit.module-name unit.id))
   (local test-module (.. name ".test-" test-name))
   (local Process (require :process))
   (local runtime (require :runtime))
   (local fs (require :fs))
   (local assets-path (or (os.getenv "SPACE_ASSETS_PATH") runtime.assets-path))
   (fn resolve-space-bin []
     (if (os.getenv "SPACE_BIN")
         (os.getenv "SPACE_BIN")
          (do
            (local cwd (fs.cwd))
            (local base-candidates [(fs.join-path cwd "build" "space")
                                    (fs.join-path cwd "build" "dist" "windows" "space")
                                    (fs.join-path cwd "space")
                                    (fs.join-path cwd ".." "build" "space")])
            (local candidates [])
            (each [_ c (ipairs base-candidates)]
              (table.insert candidates c)
              (table.insert candidates (.. c ".exe")))
            (var resolved nil)
            (each [_ candidate (ipairs candidates) &until resolved]
              (when (fs.exists candidate)
                (set resolved candidate)))
            (assert resolved
                    (.. "space_unit_run_tests could not locate space binary from cwd " cwd))
           resolved)))
   (local space-bin (resolve-space-bin))
    (local unit-fennel-path (.. (fs.join-path app.code-dir "?" "init.fnl")
                                ";" (fs.join-path app.code-dir "?.fnl")))
   (local fennel-path (.. unit-fennel-path ";" runtime.fennel-path))
   (local result (Process.run
                   {:args [space-bin "-m" (.. test-module ":main")]
                     :env {:FENNEL_PATH fennel-path
                           :FENNEL_MACRO_PATH fennel-path
                          :SPACE_ASSETS_PATH assets-path
                          :SPACE_DISABLE_AUDIO "1"}
                    :timeout 30}))
    (if (not (= result.exit-code 0))
        (.. "TESTS FAILED (exit " result.exit-code ")\n"
            (or result.stdout "") (or result.stderr ""))
        (.. "TESTS PASSED\n" (or result.stdout ""))))

 (fn register-units-adapters [adapters]
   (local json (require :json))
   (local fs (require :fs))
   (local Units (require :units))

   (adapters:register
    {:id "unit.list"
     :mcp-name "space_unit_list"
     :description "List all registered units with ID, source, loaded status, and owned paths."
     :inputSchema {:type "object" :properties {}}
     :make-run (fn [app]
                 (fn [_args]
                   (require-unit-manager app "space_unit_list")
                   (local result [])
                   (each [_ unit (ipairs (app.unit-manager:list))]
                      (table.insert result
                        {:id unit.id
                         :module-name unit.module-name
                         :parent-id unit.parent-id
                         :source unit.source
                         :loaded (unit:loaded?)
                         :owned-paths unit.owned-paths}))
                   (json.dumps result)))})

   (adapters:register
     {:id "unit.inspect"
      :mcp-name "space_unit_inspect"
      :description "Inspect a unit by ID. Returns metadata and source code if available."
      :inputSchema {:type "object"
                    :properties {:id {:type "string" :description "Unit ID"}}
                    :required ["id"]}
      :make-run (fn [app]
                  (fn [args]
                    (require-unit-manager app "space_unit_inspect")
                    (local unit (app.unit-manager:get args.id))
                    (assert unit (.. "unit not found: " args.id))
                     (local file (unit-source-file app unit))
                     (var source nil)
                     (when (and file (fs.exists file))
                       (local (ok content) (pcall fs.read-file file))
                       (when ok
                         (set source content)))
                     (local submodules [])
                     (when file
                       (local parent-dir (fs.parent file))
                       (when (and parent-dir
                                  (not= (fs.absolute parent-dir) (fs.absolute (or app.code-dir "")))
                                  (fs.exists parent-dir))
                         (local entries (fs.list-dir parent-dir))
                         (when entries
                           (each [_ entry (ipairs entries)]
                             (when (and (not= entry.name "init.fnl")
                                        entry.is-file
                                        (string.match entry.name "%.fnl$"))
                               (table.insert submodules
                                             {:name entry.name
                                              :path entry.path}))))))
                    (json.dumps
                      {:id unit.id
                       :module-name unit.module-name
                       :parent-id unit.parent-id
                       :source unit.source
                       :loaded (unit:loaded?)
                       :owned-paths unit.owned-paths
                       :source-file file
                       :source-code source
                       :load-export (or unit.load-export "init")
                       :unload-export (or unit.unload-export "drop")
                       :snapshot-export (or unit.snapshot-export "snapshot")
                       :restore-export (or unit.restore-export "restore")
                       :submodules submodules})))})


   (adapters:register
     {:id "unit.read-file"
      :mcp-name "space_unit_read_file"
      :description (.. "Read one existing file inside a user unit directory. "
                       "The path must be relative to the unit directory; use this instead of "
                       "space_app_read_file for unit source and test files.")
      :inputSchema {:type "object"
                    :properties {:id {:type "string" :description "Unit ID to read from"}
                                 :path {:type "string" :description "Relative path inside the unit directory"}}
                    :required ["id" "path"]}
      :make-run (fn [app] (fn [args] (handle-unit-read-file app args)))})

  (adapters:register
    {:id "unit.create"
     :mcp-name "space_unit_create"
     :description (.. "Create a new user unit from Fennel source code. The source must be a "
                      "Fennel module returning a table with init/drop (and optionally snapshot/restore) "
                       "functions. The unit is written to the user code directory and immediately loaded. "
                       "Set :directory true to create a multi-file directory unit (init.fnl inside a "
                       "subdirectory).")
     :inputSchema {:type "object"
                    :properties {:id {:type "string" :description "Unit ID (also used as filename)"}
                                 :source {:type "string" :description "Fennel source code for the module"}
                                  :directory {:type "boolean"
                                              :description "Create as a directory unit (default false)"}}
                   :required ["id" "source"]}
     :make-run (fn [app]
                 (fn [args]
                   (require-unit-manager app "space_unit_create")
                   (assert app.code-dir "space_unit_create requires app.code-dir")
                    (assert (string.match args.id "^[%w_-]+$")
                            "unit id must be alphanumeric with underscores and hyphens")
                    (local flat-file (fs.join-path app.code-dir (.. args.id ".fnl")))
                    (local dir-path (fs.join-path app.code-dir args.id))
                    (when (fs.exists flat-file)
                      (error (.. "unit file already exists: " flat-file)))
                    (when (fs.exists dir-path)
                      (error (.. "unit directory already exists: " dir-path)))
                     (local flat-first-module-paths (.. app.code-dir "/?.fnl;" app.code-dir "/?/init.fnl"))
                     (local dir-first-module-paths (.. app.code-dir "/?/init.fnl;" app.code-dir "/?.fnl"))
                      (local (file-path cleanup-path response-fields)
                         (if args.directory
                           (do
                             (local init-path (fs.join-path dir-path "init.fnl"))
                             (fs.create-dirs dir-path)
                             (local (write-ok write-err)
                               (pcall fs.write-file init-path args.source))
                             (when (not write-ok)
                               (fs.remove-all dir-path)
                               (error (.. "create failed to write init.fnl: " (tostring write-err))))
                               (local unit
                                 (Units.ModuleUnit {:id (.. "user-" args.id)
                                                    :module-name args.id
                                                    :module-paths dir-first-module-paths
                                                    :source :user
                                                    :owned-paths [dir-path init-path]}))
                              (values init-path dir-path
                                       {:directory true :files [init-path] :unit unit}))
                           (do
                             (local (write-ok write-err)
                               (pcall fs.write-file flat-file args.source))
                             (when (not write-ok)
                               (error (.. "create failed to write file: " (tostring write-err))))
                              (local unit
                                (Units.ModuleUnit {:id (.. "user-" args.id)
                                                   :module-name args.id
                                                   :module-paths flat-first-module-paths
                                                   :source :user
                                                   :owned-paths [flat-file]}))
                              (values flat-file flat-file
                                      {:file flat-file :unit unit}))))
                     (local unit response-fields.unit)
                     (set response-fields.unit nil)
                     (local (reg-ok reg-err) (pcall #(app.unit-manager:register unit)))
                     (when (not reg-ok)
                       (fs.remove-all cleanup-path)
                       (error (.. "create failed, register error: " (tostring reg-err))))
                     (local (load-ok load-err) (pcall #(unit:load)))
                     (when (not load-ok)
                       (local (unload-ok unload-err) (pcall #(unit:unload {})))
                       (local (purge-ok purge-err) (pcall #(unit:force-purge-module-cache!)))
                       (app.unit-manager:unregister unit.id)
                       (fs.remove-all cleanup-path)
                       (error
                         (..
                           "create failed: " (tostring load-err)
                           (if (not unload-ok) (.. " (cleanup also failed: " (tostring unload-err) ")") "")
                           (if (not purge-ok) (.. " (purge also failed: " (tostring purge-err) ")") ""))))
                     (local response {:id unit.id
                                      :module-name unit.module-name
                                      :loaded (unit:loaded?)})
                     (each [k v (pairs response-fields)]
                       (tset response k v))
                     (json.dumps response)))})

  (adapters:register
    {:id "unit.register"
     :mcp-name "space_unit_register"
     :description (.. "Register a directory-style unit that already exists on disk. "
                      "The unit must have an init.fnl in its subdirectory under the code dir. "
                       "Use this after the unit directory and init.fnl already exist.")
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit module name (subdirectory name under code-dir)"}}
                   :required ["id"]}
      :make-run (fn [app]
                  (fn [args]
                    (require-unit-manager app "space_unit_register")
                    (assert app.code-dir "space_unit_register requires app.code-dir")
                    (assert (string.match args.id "^[%w_-]+$")
                            "unit id must be alphanumeric with underscores and hyphens")
                    (local has-user-prefix (string.match args.id "^user%-"))
                    (local unit-id (if has-user-prefix args.id (.. "user-" args.id)))
                    (local source-dir-name (if has-user-prefix (string.sub args.id 6) args.id))
                    (assert (not= source-dir-name "") "unit id must provide a source directory name")
                    (local existing (app.unit-manager:get unit-id))
                    (if existing
                        (if (not (existing:loaded?))
                            (do
                              (existing:load {})
                              (json.dumps {:id existing.id :module-name existing.module-name
                                           :loaded (existing:loaded?) :reloaded true}))
                            (json.dumps {:id existing.id :module-name existing.module-name
                                         :loaded true :already-registered true}))
                         (do
                           (local flat-file (fs.join-path app.code-dir (.. source-dir-name ".fnl")))
                           (assert (not (fs.exists flat-file))
                                   (.. "a flat unit file conflicts with this module name: " flat-file))
                           (local init-path (fs.join-path app.code-dir source-dir-name "init.fnl"))
                          (assert (fs.exists init-path)
                                  (.. "init.fnl not found at " init-path
                                      ". Create the directory and init.fnl first."))
                           (local module-paths (.. app.code-dir "/?/init.fnl;" app.code-dir "/?.fnl"))
                          (local unit
                            (Units.ModuleUnit {:id unit-id
                                               :module-name source-dir-name
                                               :module-paths module-paths
                                               :source :user
                                                :owned-paths [(fs.join-path app.code-dir source-dir-name) init-path]}))
                          (app.unit-manager:register unit)
                          (local (load-ok load-err) (pcall #(unit:load)))
                          (when (not load-ok)
                            (local (unload-ok unload-err) (pcall #(unit:unload {})))
                            (local (purge-ok purge-err) (pcall #(unit:force-purge-module-cache!)))
                            (app.unit-manager:unregister unit.id)
                            (error
                              (..
                                "register failed: " (tostring load-err)
                                (if (not unload-ok) (.. " (cleanup also failed: " (tostring unload-err) ")") "")
                                (if (not purge-ok) (.. " (purge also failed: " (tostring purge-err) ")") ""))))
                          (json.dumps {:id unit.id :module-name unit.module-name
                                       :loaded (unit:loaded?)})))))})

  (adapters:register
    {:id "unit.edit"
     :mcp-name "space_unit_edit"
     :description "Edit a user unit's primary source file and trigger a hot reload. Cannot modify built-in units."
     :inputSchema {:type "object"
                    :properties {:id {:type "string" :description "Unit ID to edit"}
                                 :source {:type "string" :description "New Fennel source code"}}
                    :required ["id" "source"]}
         :make-run (fn [app]
                     (fn [args]
                       (assert app.code-dir "space_unit_edit requires app.code-dir")
                       (local unit (assert-user-unit app args.id "space_unit_edit"))
                       (local file (unit-source-file app unit))
                       (assert file (.. "unit " args.id " has no source file to edit"))
                       (assert (path-under? file app.code-dir)
                               (.. "unit " args.id " source file outside code directory"))
                       (write-unit-file-and-reload! app unit file args.source "space_unit_edit")))})

  (adapters:register
    {:id "unit.edit-file"
     :mcp-name "space_unit_edit_file"
      :description (.. "Edit one file inside a user unit directory and hot reload the unit. "
                       "Set :create? true to create a new file. The path must be relative "
                       "to the unit directory; use this for multi-file units.")
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID to edit"}
                                 :path {:type "string" :description "Relative path inside the unit directory"}
                                 :source {:type "string" :description "New file content"}
                                 :create? {:type "boolean" :description "Create the file if it does not exist"}}
                   :required ["id" "path" "source"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.code-dir "space_unit_edit_file requires app.code-dir")
                   (local unit (assert-user-unit app args.id "space_unit_edit_file"))
                    (local file (resolve-unit-file app unit args.path "space_unit_edit_file" args.create?))
                    (if (fs.exists file)
                        (write-unit-file-and-reload! app unit file args.source "space_unit_edit_file")
                        (write-new-unit-file-and-reload! app unit file args.source "space_unit_edit_file"))))})

  (adapters:register
    {:id "unit.apply-patch"
     :mcp-name "space_unit_apply_patch"
     :description (.. "Apply a unified diff patch, or one exact old/new text replacement, to an "
                      "existing file inside a user unit directory; then hot reload the unit. "
                      "Pass exactly one mode: patch, or old plus new.")
     :inputSchema {:type "object"
                    :properties {:id {:type "string" :description "Unit ID to edit"}
                                 :path {:type "string" :description "Relative path inside the unit directory"}
                                 :patch {:type "string" :description "Unified diff patch targeting path; do not combine with old/new"}
                                 :old {:type "string" :description "Exact old text to replace; requires new and no patch"}
                                 :new {:type "string" :description "Replacement text; requires old and no patch"}}
                   :required ["id" "path"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.code-dir "space_unit_apply_patch requires app.code-dir")
                   (local unit (assert-user-unit app args.id "space_unit_apply_patch"))
                   (local file (resolve-unit-file app unit args.path "space_unit_apply_patch"))
                   (local root (unit-root-dir app unit "space_unit_apply_patch"))
                   (local old-source (fs.read-file file))
                   (if (= (patch-mode args) :patch)
                       (do
                          (assert (= (type args.patch) "string")
                                  "space_unit_apply_patch :patch must be a string")
                          (local ApplyPatch (require :llm/tools/apply-patch))
                          (local (patch-ok patch-err)
                            (pcall ApplyPatch.call
                                   {:path args.path :patch args.patch :allow_create false}
                                   {:cwd root}))
                          (when (not patch-ok)
                            (local (restore-ok restore-err)
                              (pcall fs.write-file file old-source))
                            (error (.. "space_unit_apply_patch failed, source restored: "
                                       (tostring patch-err)
                                       (if (not restore-ok)
                                           (.. " (restore also failed: " (tostring restore-err) ")")
                                           ""))))
                          (reload-unit-with-rollback! app unit file old-source "space_unit_apply_patch"))
                       (do
                         (local current-source old-source)
                         (local next-source (replace-exact-text current-source args.old args.new))
                         (write-unit-file-and-reload! app unit file next-source "space_unit_apply_patch")))))})

(adapters:register
    {:id "unit.reload"
     :mcp-name "space_unit_reload"
     :description "Trigger a hot reload of a specific unit."
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID to reload"}}
                   :required ["id"]}
     :make-run (fn [app]
                 (fn [args]
                   (require-unit-manager app "space_unit_reload")
                   (app.unit-manager:reload-unit args.id {:source :agent-reload})
                   (.. "reloaded unit " args.id)))})

  (adapters:register
    {:id "unit.delete"
     :mcp-name "space_unit_delete"
     :description "Delete a user unit: unregister from the unit manager and remove its source file. Cannot delete built-in units."
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID to delete"}}
                   :required ["id"]}
        :make-run (fn [app]
                    (fn [args]
                      (assert app.code-dir "space_unit_delete requires app.code-dir")
                      (local unit (assert-user-unit app args.id "space_unit_delete"))
                      (local file (unit-source-file app unit))
                       (when file
                         (assert (path-under? file app.code-dir)
                                 (.. "unit " args.id " source file outside code directory"))
                        (local unit-name (string.match file (.. "[" sep-cc "]([^" sep-cc "]+)$")))
                        (local unit-dir (fs.parent file))
                        (when (and (= unit-name "init.fnl")
                                   unit-dir
                                   (not= (fs.absolute unit-dir) (fs.absolute app.code-dir)))
                          (assert (path-under? unit-dir app.code-dir)
                                  (.. "unit " args.id " directory outside code directory"))))
                      (app.unit-manager:unregister args.id)
                      (when file
                         (local unit-name (string.match file (.. "[" sep-cc "]([^" sep-cc "]+)$")))
                          (local unit-dir (fs.parent file))
                          (if (and (= unit-name "init.fnl")
                                   unit-dir
                                   (not= (fs.absolute unit-dir) (fs.absolute app.code-dir)))
                              ;; Directory unit: remove the whole subdirectory
                              (when (fs.exists unit-dir)
                                (fs.remove-all unit-dir))
                              ;; Flat unit (or init.fnl directly in code-dir): remove just the source file
                              (when (fs.exists file)
                                (fs.remove-all file))))
                      (.. "deleted unit " args.id)))})


  (adapters:register
    {:id "unit.eval"
     :mcp-name "space_unit_eval"
     :description (.. "Evaluate a Fennel expression in the live runtime. "
                      "The expression has access to the global 'app' table. "
                      "Returns the result as a string.")
     :inputSchema {:type "object"
                   :properties {:expression {:type "string"
                                            :description "Fennel expression to evaluate"}}
                   :required ["expression"]}
     :make-run (fn [_app]
                 (fn [args]
                   (local fennel (require :fennel))
                   (local (ok lua-source) (pcall fennel.compile-string args.expression
                                                 {:filename "agent-eval"}))
                   (when (not ok)
                     (error (.. "compile error: " lua-source)))
                   (local (chunk err) (load lua-source "agent-eval" :t))
                   (when (not chunk)
                     (error (.. "eval error: " (or err "unknown"))))
                   (local (eval-ok result) (pcall chunk))
                   (when (not eval-ok)
                     (error (.. "runtime error: " result)))
                   (json.dumps (if (= result nil) true result))))})

  (adapters:register
    {:id "unit.snapshot"
     :mcp-name "space_unit_snapshot"
     :description "Capture the current state of a unit."
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID"}}
                   :required ["id"]}
     :make-run (fn [app]
                 (fn [args]
                   (require-unit-manager app "space_unit_snapshot")
                   (local unit (app.unit-manager:get args.id))
                   (assert unit (.. "unit not found: " args.id))
                   (local state (unit:snapshot {}))
                   (json.dumps state)))})

  (adapters:register
    {:id "unit.restore"
     :mcp-name "space_unit_restore"
     :description "Restore previously captured state into a unit."
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID"}
                                :state {:type "string" :description "JSON-encoded state to restore"}}
                   :required ["id" "state"]}
     :make-run (fn [app]
                 (fn [args]
                   (require-unit-manager app "space_unit_restore")
                   (local unit (app.unit-manager:get args.id))
                   (assert unit (.. "unit not found: " args.id))
                   (local state (json.loads args.state))
                   (unit:restore state {})
                   (.. "restored state for unit " args.id)))})

  (adapters:register
    {:id "unit.connect-signal"
     :mcp-name "space_unit_connect_signal"
     :description (.. "Evaluate a Fennel expression to produce a handler function, "
                      "then connect it to a named signal on the app. "
                      "The connection is tracked by the unit and auto-disconnected on unload/reload. "
                      "The expression should evaluate to a function that receives one payload argument.")
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID"}
                                :signal-name {:type "string"
                                              :description "Signal name on app (e.g. 'workspace-shell-changed')"}
                                :handler-expr {:type "string"
                                               :description (.. "Fennel expression that evaluates to a "
                                                                "handler function (fn [payload] ...)")}}
                   :required ["id" "signal-name" "handler-expr"]}
      :make-run (fn [app]
                  (fn [args]
                    (require-unit-manager app "space_unit_connect_signal")
                    (local unit (assert-user-unit app args.id "space_unit_connect_signal"))
                    (local signal (. app args.signal-name))
                   (assert signal (.. "signal not found on app: " args.signal-name))
                    (local fennel (require :fennel))
                    (local (ok lua-source) (pcall fennel.compile-string
                                                   args.handler-expr
                                                   {:filename "agent-signal-handler"}))
                    (when (not ok)
                      (error (.. "handler compile error: " lua-source)))
                    (local (chunk err) (load lua-source "agent-signal-handler" :t))
                    (when (not chunk)
                      (error (.. "handler eval error: " (or err "unknown"))))
                    (local handler (chunk))
                    (assert (= (type handler) "function")
                            "handler expression did not evaluate to a function")
                   (unit:connect-signal args.signal-name signal handler)
                   (.. "connected " args.signal-name " to unit " args.id)))})

  (adapters:register
    {:id "unit.disconnect-signal"
     :mcp-name "space_unit_disconnect_signal"
     :description "Disconnect a previously connected signal handler from a unit."
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID"}
                                :signal-name {:type "string"
                                              :description "Signal name that was connected"}}
                   :required ["id" "signal-name"]}
      :make-run (fn [app]
                  (fn [args]
                    (require-unit-manager app "space_unit_disconnect_signal")
                    (local unit (assert-user-unit app args.id "space_unit_disconnect_signal"))
                    (unit:disconnect-signal args.signal-name)
                   (.. "disconnected " args.signal-name " from unit " args.id)))})

(fn handle-unit-read-log [args]
  (local logging (require :logging))
  (local log-path (logging.get-output-path))
  (local fs (require :fs))
  (when (not (fs.exists log-path))
    (error (.. "log file not found: " log-path)))
  (var content (fs.read-file log-path))
  (when (or (not content) (= content ""))
    (error "log file is empty"))
  (var lines [])
  (each [line (_G.string.gmatch content "([^\n]*)\n?")]
    (table.insert lines line))
  (when (= (# lines) 0)
    (error "log file is empty"))
  ;; Drop trailing empty string from final \n
  (when (and (> (# lines) 0) (= (. lines (# lines)) ""))
    (table.remove lines))
  (local grep (and args.grep (> (# args.grep) 0) args.grep))
  (var result-lines [])
  (var i (or args.offset 1))
  (var remaining (or args.limit (or (and args.offset 200) (or args.lines 100))))
  (when (< i 1) (set i 1))
  (when args.lines
    (set i (math.max 1 (- (# lines) args.lines -1))))
  (while (and (<= i (# lines)) (> remaining 0))
    (local line (. lines i))
    (when (or (not grep) (string.find line grep 1 true))
      (table.insert result-lines (.. i ": " line))
      (set remaining (- remaining 1)))
    (set i (+ i 1)))
  (local total (# lines))
  (local matched (# result-lines))
  (if (= matched 0)
      (.. "no matching lines in log (" total " total lines, path: " log-path ")")
      (.. "--- space log (" matched " lines, path: " log-path ") ---\n"
          (table.concat result-lines "\n"))))

  (adapters:register
    {:id "unit.read-log"
     :mcp-name "space_unit_read_log"
     :description (.. "Read the space application log file to find error messages "
                      "from unit activation, signal handlers, or other runtime failures. "
                      "Call this after creating/editing/reloading units to verify they work.")
     :inputSchema {:type "object"
                   :properties {:lines {:type "number"
                                        :description "Number of lines to return from the end of the log (default 100)"}
                                :offset {:type "number"
                                         :description "Line number to start reading from (1-indexed, overrides lines)"}
                                :limit {:type "number"
                                         :description "Max lines when using offset (default 200)"}
                                :grep {:type "string"
                                       :description "Filter: only return lines containing this text"}}}
     :make-run (fn [_app] (fn [args] (handle-unit-read-log args)))})

  (adapters:register
    {:id "unit.create-test"
     :mcp-name "space_unit_create_test"
     :description (.. "Create a test module for a user unit. The test module must export "
                      "{:main main :tests tests}; main should usually call tests/runner. "
                      "Tests run in a headless engine with mock OpenGL. The global `app` is available.")
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID to create a test for"}
                                :test-name {:type "string"
                                            :description "Short name for the test aspect (e.g. init, render, integration)"}
                                :source {:type "string"
                                         :description "Fennel source code for the test module. Must return {:main main :tests tests}."}}
                   :required ["id" "test-name" "source"]}
     :make-run (fn [app] (fn [args] (handle-unit-create-test app args)))})

  (adapters:register
    {:id "unit.run-tests"
     :mcp-name "space_unit_run_tests"
     :description (.. "Run tests for a user unit. Executes the test module(s) in a subprocess "
                      "with a headless engine. Returns test output and pass/fail status.")
     :inputSchema {:type "object"
                   :properties {:id {:type "string" :description "Unit ID to run tests for"}
                                :test-name {:type "string"
                                            :description "Test aspect name (e.g. init). Defaults to init"}}
                   :required ["id"]}
     :make-run (fn [app] (fn [args] (handle-unit-run-tests app args)))}))

(fn register-units-presets [mgr]
  (mgr:register
    {:name "units-discover-tools"
     :group "units"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :any}]
      :tool-ids ["unit.list" "unit.inspect" "unit.read-file" "unit.read-log"]
     :system-prompt
     (.. "{:: Unit Tools ::}\n"
         "You can create, edit, reload, and wire Fennel runtime modules called \"units\".\n"
         "Each unit is a file in the user code directory exporting a table with these functions:\n"
         "  (fn init [] ...)       -- called on load, sets up state/callbacks/signals\n"
         "  (fn drop [] ...)       -- called on unload, teardown everything\n"
         "  (fn snapshot [] ...)   -- optional: return current state for hot reload\n"
         "  (fn restore [state] ...) -- optional: reapply state after hot reload\n"
         "  {:init init :drop drop :snapshot snapshot :restore restore}\n"
         "\n{:: Available libraries ::}\n"
         "fs       -- filesystem: read-file, write-file, list-dir, exists, create-dirs, join-path\n"
         "json     -- JSON: dumps (encode), loads (decode)\n"
         "signal   -- Signal() creates pub/sub: :emit payload, :connect fn, :disconnect fn\n"
         "glm      -- vector math: vec3, vec4, mat4, length, normalize, +, -, *, /\n"
         "process  -- Process.run for subprocesses\n"
         "fennel   -- compile-string, eval for runtime Fennel\n"
         "\n{:: Global app table ::}\n"
         "The global `app` holds all runtime state. Key fields:\n"
         "  app.canvas-visible?        -- bool\n"
         "  app.active-activity-id     -- current activity id or nil\n"
          "  app.active-interaction-surface -- \"scene\" or \"canvas\"\n"
          "  app.code-dir               -- user code directory for user units\n"
          "  app.canvas                  -- Canvas surface object; dynamic activities must use their own activity canvas slot\n"
          "  app.clickables              -- Clickable registry for pointer input routing\n"
          "Use `space_unit_eval` with expressions like `app.canvas-visible?` to inspect.\n"
          "\n{:: Activity-owned presentation boundary ::}\nDynamic activity units must register through Activities.register-activity. Generated activities such as bubbles must create or obtain their own activity canvas slot using their own activity id, install their own camera/controls in that slot/session, activate it, and expose its render target before receiving presentation input.\n"
          "Use app.presentation-screen-pos-ray, provider rays, slot pointer-target rays, or explicit view/projection matrices for pointer math. Unsafe/failing in active activity contexts: bare app.canvas:screen-pos-ray, bare app.scene:screen-pos-ray, canvas.camera, scene.camera, retained surface controls, app canvas controls, or active pointer controls as camera fallbacks.\n"
          "\n{:: Code discovery workflow ::}\n"
         "Before writing non-trivial unit code, use generic code exploration tools to\n"
         "discover existing patterns instead of relying on memory or this prompt.\n"
         "Use space_app_search to find relevant modules and call sites, then\n"
         "space_app_read_file or space_unit_read_file to inspect the exact code.\n"
         "Prefer matching established contracts over inventing new integration points.\n"
         "Units may call runtime APIs directly from init/drop, but every registration,\n"
         "subscription, widget, signal handler, or global mutation must be cleaned up\n"
         "explicitly in drop.\n"
         "\n{:: Multi-file units ::}\n"
         "For complex units, use subdirectories:\n"
         "  <code-dir>/<name>/init.fnl     -- main module (exports init/drop/snapshot/restore)\n"
         "  <code-dir>/<name>/render.fnl   -- custom renderer (exports factory)\n"
         "  <code-dir>/<name>/input.fnl    -- input handlers\n"
         "  <code-dir>/<name>/controller.fnl -- business logic / state\n"
         "\n"
           "Create new multi-file units with space_unit_create {directory true}. Add new\nsubmodule files with space_unit_edit_file {create? true}. For existing files,\n"
          "edit with space_unit_apply_patch for small exact replacements or\nspace_unit_edit_file for full-file rewrites. Avoid shell/perl/sed for unit\n"
         "edits; these tools hot reload automatically. To load a directory-style unit\n"
         "that already exists on disk, call space_unit_register {id \"<name>\"}.\n"
         "Submodules use (require :name/render) (slash syntax);\n"
         "Fennel converts slashes to dots internally, matching module paths.\n"
         "\n{:: Idempotency ::}\n"
         "Before creating, call space_unit_list to check for existing units. Skip creation\n"
         "if the unit already exists and you were not asked to modify it.\n"
         "\n{:: Codebase layout ::}\n"
         "assets/lua/           -- all Fennel/Lua modules\n"
         "  main.fnl            -- app entry point, lifecycle, wiring\n"
         "  activities.fnl      -- Activities registry and activity context\n"
         "  canvas.fnl           -- Canvas surface, build-context, screen-pos-ray\n"
         "  board/              -- Board model/view/registry for arbitrary canvas widgets\n"
         "  build-context.fnl   -- BuildContext (triangle buffer, image batches)\n"
         "  units.fnl           -- Unit, ModuleUnit, SourceUnit constructors\n"
         "  signal.fnl          -- Signal pub/sub\n"
         "  drawing/            -- drawing controller, render.fnl, input.fnl, hit-test.fnl\n"
         "  graph/              -- graph core, views, nodes\n"
         "  llm/presets/builtins/ -- agent tool definitions\n"
         "  tests/              -- test modules (fast.fnl lists all)\n"
         "\n{:: Search patterns ::}\n"
         "space_app_search {pattern \"register-activity\" path \"assets/lua\" include \"*.fnl\"}\n"
         "space_app_search {pattern \"triangle-vector\" path \"assets/lua\" include \"*.fnl\"}\n"
         "space_app_search {pattern \"set-update!\" path \"assets/lua\" include \"*.fnl\"}\n"
         "space_app_read_file {path \"assets/lua/drawing/render.fnl\"}\n"
         "\n{:: Debugging runtime errors ::}\n"
         "When log tools are available and a unit fails at runtime (activation error,\n"
         "signal handler crash, etc.), the error and full traceback are written to\n"
         "the space log file. Use these tools:\n"
         "\n"
         "  1. space_unit_read_log            -- Read last 100 lines (fast overview)\n"
         "  2. space_unit_read_log {lines 200 grep \"bubbles\"}  -- Filter for your unit\n"
         "  3. space_unit_read_log {offset 200 limit 80}  -- Read a specific range\n"
         "  4. space_app_read_file <log-path> -- Read the entire log only when needed\n"
         "\n"
         "The log path is in the unit context above. Always check the log after:\n"
         "  - Creating a new unit (space_unit_create)\n"
         "  - Editing a unit's source code (space_unit_edit)\n"
         "  - Reloading a unit (space_unit_reload)\n"
         "  - Switching to an activity that uses your unit\n"
         "\n"
         "Look for the most recent ERROR entry containing your unit's id or file path.\n"
         "The error trace shows the exact file and line number of the failure.\n"
         "Use space_unit_read_log for log slicing instead of shell commands.\n"
         "\n{:: Unit testing ::}\n"
         "When test tools are available, every user unit MUST have thorough tests.\n"
         "Create tests alongside your unit code using space_unit_create_test and run\n"
         "them with space_unit_run_tests.\n"
         "\n"
         "Test file convention:\n"
         "  code-dir/<unit>/test-init.fnl        -- unit tests (export/init/drop)\n"
         "  code-dir/<unit>/test-render.fnl      -- render logic tests\n"
         "  code-dir/<unit>/test-integration.fnl  -- integration tests\n"
         "\n"
         "Test module structure:\n"
         "  ;; test-init.fnl\n"
         "  (local runner (require :tests/runner))\n"
         "  (local tests [])\n"
         "  (table.insert tests {:name \"description of what is tested\"\n"
         "                       :fn (fn []\n"
         "                             ;; setup: load the unit, init state\n"
         "                             ;; action: trigger behavior\n"
         "                             ;; assert: verify expected result\n"
         "                             (assert (= expected actual) \"failure message\"))})\n"
         "  (fn main [] (runner.run-tests {:name \"unit init\" :tests tests}))\n"
         "  {:main main :tests tests}\n"
         "\n"
         "Test environment (available without require):\n"
         "  app, app.engine          -- headless engine with mock OpenGL\n"
         "  app.engine.events        -- engine event signals (auto-cleared between tests)\n"
         "  reset-engine-events      -- global fn: clear all engine event signals\n"
         "  assert, type, pairs, ipairs -- standard Lua globals\n"
         "\n"
         "Available with require:\n"
         "  (require :fs)            -- filesystem ops\n"
         "  (require :json)          -- JSON encode/decode\n"
         "  (require :signal)        -- Signal() pub/sub\n"
         "  (require :fennel)        -- compile-string, eval\n"
         "  (require :logging)       -- logging.debug/info/warn/error\n"
         "  (require :glm)           -- vec3, vec4, mat4, +, -, *, /, length, normalize\n"
         "\n"
         "Required test patterns (cover all of these):\n"
         "  1. init/drop: Load the unit, call init, verify state exists. Call drop, verify\n"
         "     cleanup. Load again, verify fresh state.\n"
         "  2. Idempotency: Call init twice without drop — should be safe or error clearly.\n"
         "  3. snap/restore (if unit exports them): Capture state, modify, restore, verify.\n"
         "  4. Signal wiring: Connect handlers, emit signals, verify handlers receive payload.\n"
         "     Disconnect, emit again, verify handler not called.\n"
         "  5. Error handling: Feed bad inputs, verify the unit errors with clear messages.\n"
         "  6. State isolation: Verify the unit does not leak values to the global scope.\n"
         "\n"
         "Integration test patterns (in test-integration.fnl):\n"
         "  For activity units, test the full activate/deactivate cycle:\n"
         "  - Create a mock app with needed fields (canvas, signals, clickables)\n"
         "  - Register the activity via Activities.register-activity\n"
         "  - Call activate, verify the returned session has expected structure\n"
         "  - Simulate update calls, verify state updates correctly\n"
         "  - Call deactivate, verify cleanup\n"
         "  See test-agent-units-online.fnl for a full mock-app blueprint.\n"
         "\n"
         "For controller units, test business logic in isolation:\n"
         "  - Import the controller module, call its functions with test inputs\n"
         "  - Verify return values and state mutations\n"
         "  - Test edge cases: empty state, max values, nil inputs\n"
         "\n"
         "Workflow after creating/editing a unit:\n"
         "  1. Create test: space_unit_create_test {id \"user-bubbles\" test-name \"init\" source \"...\"}\n"
         "  2. Run tests:  space_unit_run_tests {id \"user-bubbles\" test-name \"init\"}\n"
         "  3. Check log:  space_unit_read_log {grep \"bubbles\"}  -- if tests failed\n"
         "  4. Read source/test files with space_unit_read_file when needed.\n"
         "  5. Fix source: space_unit_apply_patch {id \"user-bubbles\" path \"controller.fnl\" old \"...\" new \"...\"}\n"
         "  6. Re-run:     space_unit_run_tests {id \"user-bubbles\" test-name \"init\"}\n"
         "  7. Repeat 3-6 until all tests pass\n"
         "\n{:: Unit code style (from AGENTS.md) ::}\n"
         "- Four-space indentation, no trailing whitespace\n"
         "- Declare locals at top: (local fs (require :fs))\n"
         "- Use (var val) for mutables, (local val) for immutables\n"
         "- Module returns a table literal, not mutated with set\n"
         "- Clean up in drop: disconnect signals, nil app references\n"
         "- User units in code-dir can require standard modules (fs, json, signal, glm, etc.)")})

  (mgr:register
    {:name "units-create-tools"
     :group "units"
     :default-state :auto
     :risk :shell
     :contexts [{:surface :any}]
     :tool-ids ["unit.create" "unit.eval"]})

  (mgr:register
    {:name "units-runtime-tools"
     :group "units"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :any}]
       :tool-ids ["unit.edit" "unit.edit-file" "unit.apply-patch" "unit.register" "unit.reload"
                  "unit.disconnect-signal" "unit.run-tests" "unit.snapshot"]})

  (mgr:register
    {:name "units-signal-tools"
     :group "units"
     :default-state :auto
     :risk :shell
     :contexts [{:surface :any}]
     :tool-ids ["unit.connect-signal"]})

   (mgr:register
     {:name "units-edit-tools"
      :group "units"
      :default-state :auto
      :risk :filesystem-write
      :contexts [{:surface :any}]
      :tool-ids ["unit.create-test"]})

  (mgr:register
    {:name "units-destructive-tools"
     :group "units"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :any}]
     :tool-ids ["unit.delete" "unit.restore"]})

  true)

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-units-adapters adapters))
  (when (and (= (type mgr) :table) (. mgr :register))
    (register-units-presets mgr))
  true)

{:register register}
