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
     :tool-ids ["app.set-canvas-visible" "app.set-canvas-mode" "app.switch-surface"]
     :system-prompt "Use canvas control tools to manage the canvas visibility, mode, and surface switching."})

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
     :tool-ids ["app.read-file" "app.list-files"]
     :system-prompt "File read tools allow reading from the filesystem and may require approval."})

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
    {:id "app.set-canvas-mode"
     :mcp-name "space_app_set_canvas_mode"
     :description "Set the active canvas mode."
     :inputSchema {:type "object" :properties {:mode {:type "string" :description "Canvas mode name (drawing, graph, etc.)"}} :required ["mode"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.set-active-canvas-mode "space_app_set_canvas_mode requires app.set-active-canvas-mode")
                   (app.set-active-canvas-mode args.mode)
                   (.. "canvas mode: " args.mode)))})

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

  true)

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-general-adapters adapters))
  (when (and (= (type mgr) :table) (. mgr :register))
    (register-general-presets mgr))
  true)

{:register register}
