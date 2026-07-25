(fn process-output-or-error! [tool-name result]
  (assert result (.. tool-name " did not return a process result"))
  (when result.timed-out
    (error (.. tool-name " timed out")))
  (when result.signal
    (error (.. tool-name " exited from signal " (tostring result.signal) ": " (or result.stderr ""))))
  (when (not (= result.exit-code 0))
    (local detail (if (> (# (or result.stderr "")) 0)
                      result.stderr
                      result.stdout))
    (error (.. tool-name " exited with code " (tostring result.exit-code) ": " (or detail ""))))
  result.stdout)

(fn path-under-root? [path root]
  (local path-utils (require :path-utils))
  (local fs (require :fs))
  (local normalized (fs.absolute path))
  (local normalized-root (fs.absolute root))
  (local root-len (# normalized-root))
  (and (>= (# normalized) root-len)
       (= (string.sub normalized 1 root-len) normalized-root)
       (or (= (# normalized) root-len)
           (path-utils.path-separator? (string.sub normalized (+ root-len 1) (+ root-len 1))))))

(fn path-has-symlink? [path root]
  (local fs (require :fs))
  (local normalized-root (fs.absolute root))
  (var current (fs.absolute path))
  (var found? false)
  (while (and (not found?) (path-under-root? current normalized-root))
    (local stat (fs.stat current))
    (when (and stat.exists stat.is-symlink)
      (set found? true))
    (local parent (fs.parent current))
    (if (or (not parent) (= parent current))
        (set current "")
        (set current parent)))
  found?)

(fn default-search-root [app]
  (local fs (require :fs))
  (local cwd (fs.cwd))
  (local assets-root (and app app.engine app.engine.get-asset-path
                         (app.engine.get-asset-path "")))
  (local root (and assets-root (fs.parent assets-root)))
  (if (fs.exists (fs.join-path cwd "assets" "lua"))
      cwd
      (and root (fs.exists root))
      root
      cwd))

(fn search-result-with-limit [stdout limit]
  (local max-lines (math.max 1 (math.floor (or limit 200))))
  (local lines [])
  (var total 0)
  (each [line (string.gmatch (or stdout "") "([^\n]*)\n?")]
    (when (> (# line) 0)
      (set total (+ total 1))
      (when (< (# lines) max-lines)
        (table.insert lines line))))
  (when (> total max-lines)
    (table.insert lines (.. "[truncated: showing " max-lines " of " total " matching lines]")))
  (table.concat lines "\n"))

(fn register-general-presets [mgr]
  (mgr:register
    {:name "general-theme-tools"
     :group "general"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :any}]
     :tool-ids ["app.set-theme"]})

  (mgr:register
    {:name "general-canvas-tools"
     :group "general"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :any}]
     :tool-ids ["app.set-canvas-visible" "app.set-activity" "app.switch-surface"]
     :system-prompt "Use canvas control tools to manage canvas visibility, activity, and surface switching."})

  (mgr:register
    {:name "general-world-tools"
     :group "general"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :any}]
     :tool-ids ["app.create-world" "app.switch-world" "app.delete-world"]
     :system-prompt "World management operations are available but destructive actions require approval."})

  (mgr:register
    {:name "general-file-read-tools"
     :group "general"
     :default-state :auto
     :risk :filesystem-read
     :contexts [{:surface :any}]
      :tool-ids ["app.read-file" "app.list-files" "app.search"]
      :system-prompt "File read and search tools allow reading and searching the filesystem and may require approval."})

  (mgr:register
    {:name "general-file-write-tools"
     :group "general"
     :default-state :auto
     :risk :filesystem-write
     :contexts [{:surface :any}]
     :tool-ids ["app.write-file"]
     :system-prompt "File write tools allow writing to the filesystem and require approval."})

  (mgr:register
    {:name "general-shell-tools"
     :group "general"
     :default-state :auto
     :risk :shell
     :contexts [{:surface :any}]
     :tool-ids ["app.run-bash"]
     :system-prompt "Shell tools allow executing arbitrary commands and require approval."}))

(fn register-general-adapters [adapters]
  (local empty-schema {:type "object" :properties {}})

  (fn find-world-index [world-manager world-id]
    (var found nil)
    (each [_ tab (ipairs (world-manager:list-tabs))]
      (when (and (not found) (= tab.id world-id))
        (set found tab.index)))
    found)

  (adapters:register
    {:id "app.set-theme"
     :mcp-name "space_app_set_theme"
     :description "Set the application theme."
     :inputSchema {:type "object" :properties {:theme {:type "string" :description "Theme name"}} :required ["theme"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert (= (type args.theme) "string") "space_app_set_theme requires a theme string")
                   (local ThemeActions (require :theme-actions))
                   (ThemeActions.apply-theme args.theme)
                   (.. "theme set to " args.theme)))})

  (adapters:register
    {:id "app.set-canvas-visible"
     :mcp-name "space_app_set_canvas_visible"
     :description "Show or hide the canvas."
     :inputSchema {:type "object" :properties {:visible {:type "boolean" :description "Canvas visibility"}} :required ["visible"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.set-canvas-visible "space_app_set_canvas_visible requires app.set-canvas-visible")
                   (app.set-canvas-visible args.visible)
                   (.. "canvas visible: " (tostring args.visible))))})

  (adapters:register
    {:id "app.set-activity"
     :mcp-name "space_app_set_activity"
     :description "Set the active activity."
     :inputSchema {:type "object" :properties {:activity {:type "string" :description "Activity name (drawing, graph, etc.)"}} :required ["activity"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.set-active-activity "space_app_set_activity requires app.set-active-activity")
                   (app.set-active-activity args.activity)
                   (.. "activity: " args.activity)))})

  (adapters:register
    {:id "app.switch-surface"
     :mcp-name "space_app_switch_surface"
     :description "Switch the active interaction surface."
     :inputSchema {:type "object" :properties {:surface {:type "string" :description "Surface name (scene or canvas)"}} :required ["surface"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.set-active-interaction-surface "space_app_switch_surface requires app.set-active-interaction-surface")
                   (app.set-active-interaction-surface args.surface)
                   (.. "surface: " args.surface)))})

  (adapters:register
    {:id "app.create-world"
     :mcp-name "space_app_create_world"
     :description "Create a new world. This is a significant operation."
     :inputSchema {:type "object" :properties {:name {:type "string" :description "World name"}} :required ["name"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.world-manager "space_app_create_world requires app.world-manager")
                   (local entry (app.world-manager:create-home-world {:name args.name}))
                   (tostring entry.id)))})

  (adapters:register
    {:id "app.switch-world"
     :mcp-name "space_app_switch_world"
     :description "Switch to a different world."
     :inputSchema {:type "object" :properties {:id {:type "string" :description "World ID to switch to"}} :required ["id"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.world-manager "space_app_switch_world requires app.world-manager")
                   (app.world-manager:activate-world-id args.id)
                   (.. "switched to world " args.id)))})

  (adapters:register
    {:id "app.delete-world"
     :mcp-name "space_app_delete_world"
     :description "Delete a world. This is destructive and cannot be undone."
     :inputSchema {:type "object" :properties {:id {:type "string" :description "World ID to delete"}} :required ["id"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.world-manager "space_app_delete_world requires app.world-manager")
                   (local idx (find-world-index app.world-manager args.id))
                   (assert idx (.. "world not found: " args.id))
                   (app.world-manager:close-world-index idx)
                   (.. "deleted world " args.id)))})

  (adapters:register
    {:id "app.read-file"
     :mcp-name "space_app_read_file"
     :description "Read a file from the filesystem."
     :inputSchema {:type "object" :properties {:path {:type "string" :description "File path to read"}} :required ["path"]}
     :make-run (fn [_app]
                 (fn [args]
                   (local io-utils (require :io-utils))
                   (io-utils.read-file args.path)))})

  (adapters:register
    {:id "app.list-files"
     :mcp-name "space_app_list_files"
     :description "List files in a directory."
     :inputSchema {:type "object" :properties {:path {:type "string" :description "Directory path"}} :required ["path"]}
     :make-run (fn [_app]
                  (fn [args]
                    (local fs (require :fs))
                    (local json (require :json))
                    (local entries (fs.list-dir args.path))
                    (local result [])
                    (each [_ entry (ipairs entries)]
                      (table.insert result
                        {:name entry.name
                         :path (fs.join-path args.path entry.name)
                         :is-file entry.is-file
                         :is-dir entry.is-dir}))
                    (json.dumps result)))})

  (adapters:register
    {:id "app.write-file"
     :mcp-name "space_app_write_file"
     :description "Write content to a file. This overwrites existing files."
     :inputSchema {:type "object"
                   :properties {:path {:type "string" :description "File path"}
                                :content {:type "string" :description "File content"}}
                   :required ["path" "content"]}
     :make-run (fn [_app]
                 (fn [args]
                   (local fs (require :fs))
                   (fs.write-file args.path args.content)
                   (.. "wrote " (# args.content) " bytes to " args.path)))})

  (adapters:register
    {:id "app.run-bash"
     :mcp-name "space_app_run_bash"
     :description "Execute a bash command. This allows arbitrary code execution."
     :inputSchema {:type "object" :properties {:command {:type "string" :description "Bash command to run"}} :required ["command"]}
     :make-run (fn [_app]
                 (fn [args]
                   (assert (= (type args.command) "string") "space_app_run_bash requires a command string")
                   (assert (> (# args.command) 0) "space_app_run_bash command must not be empty")
                   (local Process (require :process))
                   (local result (Process.run {:args ["bash" "-c" args.command]}))
                    (process-output-or-error! "space_app_run_bash" result)))})

  (adapters:register
    {:id "app.search"
     :mcp-name "space_app_search"
     :description "Search project source files for a regex pattern using ripgrep. Returns matching file paths with line numbers and content. Use this to discover API patterns, widget usage, function signatures, and code conventions across the codebase."
     :inputSchema {:type "object"
                   :properties {:pattern {:type "string" :description "Regex pattern to search for (rg syntax)"}
                                :path {:type "string" :description "Directory to search, absolute or project-root relative (defaults to project root)"}
                                :include {:type "string" :description "File glob filter (e.g. *.fnl, *.cpp, *.h)"}
                                :limit {:type "number" :description "Maximum matching lines to return (default 200)"}}
                   :required ["pattern"]}
     :make-run (fn [app]
                 (fn [args]
                   (local Process (require :process))
                   (local fs (require :fs))
                   (assert (= (type args.pattern) "string") "space_app_search requires a string :pattern")
                   (assert (> (# args.pattern) 0) "space_app_search :pattern must not be empty")
                   (local project-root (default-search-root app))
                   (local search-root
                     (if args.path
                         (if (or (= (string.sub args.path 1 1) "/")
                                 (string.match args.path "^%a:[\\/]"))
                             args.path
                             (fs.join-path project-root args.path))
                         project-root))
                   (assert (fs.exists search-root)
                           (.. "search path not found: " search-root))
                   (assert (path-under-root? search-root project-root)
                           (.. "search path escapes project root: " search-root))
                   (assert (not (path-has-symlink? search-root project-root))
                           (.. "search path contains a symlink component: " search-root))
                    (var rg-args ["rg" "--no-config" "--no-heading" "--line-number"
                                  "--color" "never" "--no-messages" "--max-columns" "500"])
                    (when args.include
                      (table.insert rg-args "--glob")
                      (table.insert rg-args args.include))
                    (table.insert rg-args "--")
                    (table.insert rg-args args.pattern)
                    (table.insert rg-args search-root)
                   (local result (Process.run {:args rg-args :timeout 30 :merge-stderr true}))
                   (if (or (= result.exit-code 0) (= result.exit-code 1))
                       (do
                         (local stdout (or result.stdout ""))
                         (if (= stdout "")
                             (.. "no matches found for pattern: " args.pattern)
                             (search-result-with-limit stdout args.limit)))
                       (error (.. "search failed (exit " result.exit-code "): "
                                  (or result.stderr result.stdout))))))})

  true)

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-general-adapters adapters))
  (when (and (= (type mgr) :table) (. mgr :register))
    (register-general-presets mgr))
  true)

{:register register}
