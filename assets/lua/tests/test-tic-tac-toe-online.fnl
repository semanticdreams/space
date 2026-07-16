;; Live acceptance test: internal Space agent builds tic-tac-toe from scratch.
;; The agent receives only a general game description and a hint to follow
;; the patterns used by the existing Tetris game. It must explore the codebase
;; independently to discover architecture, rendering, input, and state patterns.
;;
;; Run:
;; SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-tic-tac-toe-online:main

(local OpencodeSdk (require :llm/providers/opencode))
(local callbacks (require :callbacks))
(local fs (require :fs))
(local sysinfo (require :sysinfo))
(local process (require :process))
(local ToolRegistry (require :mcp/tool-registry))
(local PresetRegistryMod (require :llm/presets/registry))
(local PresetManagerMod (require :llm/presets/init))
(local ToolAdapterRegistryMod (require :llm/presets/tool-adapters))
(local AgentRegistryMod (require :llm/agent/registry))
(local AgentRunnerMod (require :llm/agent/runner))
(local AgentToolSurfaceMod (require :llm/agent/tool-surface))
(local AgentApprovalsMod (require :llm/agent/approvals))
(local AgentMcpSyncMod (require :llm/agent/mcp-sync))
(local AgentOpencodeMcpBridgeMod (require :llm/agent/opencode-mcp-bridge))
(local SpaceAgentMod (require :llm/agent/builtins/space-agent))
(local SessionMod (require :llm/agent/session))
(local UnitManager (require :unit-manager))
(local BuiltinUnits (require :llm/presets/builtins/units))
(local BuiltinGeneral (require :llm/presets/builtins/general))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))
(local Launcher (require :launcher))
(local Signal (require :signal))
(local tempfile (require :tempfile))
(local BuildContext (require :build-context))
(local {: LayoutRoot} (require :layout))
(local glm (require :glm))

;; This is a generic agent/unit/launcher readiness test using tic-tac-toe as
;; the scenario workload. Do not assert generated game internals such as file
;; names beyond the unit entrypoint, function names, board shape, or game state.

(local TEST_CONFIG
  {:opencode-path "opencode"
    :provider-id "opencode"
    :model-id "big-pickle"
    :root-prefix "/tmp/space/tests/tic-tac-toe-online"
    :turn-timeout-ms 900000})

(var passed 0)
(var failed 0)
(var failures [])

(fn now-ms [] (sysinfo.now-ms))

(fn poll-all []
  (callbacks.run-loop {:poll-http true :poll-process true :sleep-ms 10 :timeout-ms 50}))

(fn wait-for [pred timeout-ms]
  (local deadline (+ (now-ms) (or timeout-ms 10000)))
  (var result nil)
  (while (and (not result) (< (now-ms) deadline))
    (poll-all)
    (local (ok val) (pcall pred))
    (when ok (set result val)))
  (assert result (.. "timeout after " (or timeout-ms 10000) "ms")))

(fn assert-response-ok [result label]
  (assert result (.. label " should return a response"))
  (assert result.ok
          (.. label " failed: "
              (or result.raw (and (= (type result.data) "table") result.data.error)
                  result.error "unknown error"))))

(fn fresh-root []
  (local root (.. TEST_CONFIG.root-prefix "-" (tostring (os.time)) "-" (math.random 0 99999)))
  (when (fs.exists root) (fs.remove-all root))
  (fs.create-dirs root)
  root)

(fn fresh-temp-dir [prefix]
  (local handle (tempfile.TemporaryDirectory {:prefix (or prefix "tic-tac-toe-online")}))
  {:path handle.path :handle handle})

(fn make-test-theme []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -0.25 :lineHeight 1.25}
                          :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph}
               :advance 1})
  {:font font
   :italic-font font
   :bold-font font
   :bold-italic-font font
   :text {:foreground (glm.vec4 0.92 0.94 0.98 1)
          :scale 1.6}
   :card {:background (glm.vec4 0.12 0.13 0.18 1)
          :foreground (glm.vec4 0.92 0.94 0.98 1)}})

(fn make-mock-app [code-dir unit-manager assets-path]
  (local states (States))
  (local launcher (Launcher {}))
  (local scene-children [])
  (local layout-root (LayoutRoot))
  (local theme (make-test-theme))
  (launcher:clear-runtime)
  (local fennel (require :fennel))
  (set fennel.macro-path (.. assets-path "/lua/?.fnl;" assets-path "/lua/?/init.fnl"))
  (var build-context nil)
  (local scene
    {:children scene-children
     :layout-root layout-root
     :add-panel-child (fn [self child]
                         (local opts (or child self))
                         (local builder (assert opts.builder "mock scene add-panel-child requires :builder"))
                         (local builder-options (or opts.builder-options {}))
                         (local element (builder build-context builder-options))
                         (table.insert scene-children {:element element :opts opts})
                         element)})
  (local mock-app
    {:engine {:get-asset-path (fn [path]
                                 (if (= path "lua/launchables")
                                     (.. assets-path "/lua/tests/data/launchables/basic")
                                    (.. assets-path "/" path)))}
      :unit-manager unit-manager
      :code-dir code-dir
      :assets-path assets-path
      :states states
      :themes {:get-active-theme (fn [] theme)}
      :launcher launcher
      :launchables {:add-launchable (fn []
                                      (error "Use app.launcher:register for runtime launchables"))}
      :scene scene
      :layout-root layout-root
      :canvas-visible? false
      :active-canvas-mode nil
      :active-interaction-surface nil
      :clickables {:register (fn [_] true) :unregister (fn [_] true)
                  :register-left-click-void-callback (fn [_ _cb] true)
                  :unregister-left-click-void-callback (fn [_ _cb] true)
                  :register-right-click (fn [_] true)
                  :unregister-right-click (fn [_] true)
                  :register-double-click (fn [_] true)
                  :unregister-double-click (fn [_] true)}
     :hoverables {:register (fn [_] true) :unregister (fn [_] true)}
     :intersectables {:register (fn [_] true) :unregister (fn [_] true)}
     :movables {:register (fn [_] true) :unregister (fn [_] true)}
     :resizables {:register (fn [_] true) :unregister (fn [_] true)}
      :focus {:clear-focus (fn [_] true)}
       :canvas-shell-changed (Signal)
       :test-app true})
   (set mock-app.set-canvas-visible
        (fn [visible?]
          (assert (or (= visible? nil) (not= (type visible?) :table))
                  "set-canvas-visible expects boolean, not table (use dot-call)")
          (set mock-app.canvas-visible? (not (= visible? false)))
          true))
   (set mock-app.set-active-canvas-mode
        (fn [mode-id]
          (assert (or (= mode-id nil) (= (type mode-id) :string))
                  "set-active-canvas-mode expects string mode-id (use dot-call)")
          (set mock-app.active-canvas-mode mode-id)
          true))
   (set mock-app.set-active-interaction-surface
        (fn [surface opts]
          (assert (or (= surface nil) (= (type surface) :string))
                  "set-active-interaction-surface expects string surface (use dot-call)")
          (set mock-app.active-interaction-surface surface)
          (when (and (not= opts nil) opts.sync-canvas-visibility (= surface :canvas))
            (set mock-app.canvas-visible? true))
          true))
   (local mock-icons {:get (fn [_self _name] 4242)
                      :resolve (fn [self name] {:type :font :codepoint (self:get name) :font theme.font})})
   (set build-context
        (BuildContext {:layout-root layout-root
                       :pointer-target scene
                       :panel-target scene
                       :clickables mock-app.clickables
                       :hoverables mock-app.hoverables
                       :movables mock-app.movables
                       :resizables mock-app.resizables
                       :intersectables mock-app.intersectables
                       :theme theme
                       :icons mock-icons
                       :states states}))
  (set scene.build-context build-context)
  (states:add-state :normal {})
  (states:set-state :normal)
  (StateSystemBindings.bind-states-host states)
  mock-app)

(fn setup-full-pipeline [app]
  (local preset-registry (PresetRegistryMod.PresetRegistry {}))
  (local adapter-registry (ToolAdapterRegistryMod.ToolAdapterRegistry {}))
  (local tool-registry (ToolRegistry {:namespace-prefix "space_"}))

  (fn remove-tools-from-preset! [name blocked]
    (local preset (preset-registry:get name))
    (local filtered [])
    (each [_ tool-id (ipairs preset.tool-ids)]
      (when (not (. blocked tool-id))
        (table.insert filtered tool-id)))
    (set preset.tool-ids filtered)
    (preset-registry:unregister name)
    (preset-registry:register preset))

  (local preset-manager
    (PresetManagerMod.PresetManager
      {:registry preset-registry
       :tool-adapters adapter-registry
       :app app
       :context {:surface :any :canvas-visible? false}}))

  (BuiltinUnits.register preset-manager)
  (BuiltinGeneral.register preset-manager)
  (remove-tools-from-preset! "units-discover-tools" {"unit.read-log" true})
  (remove-tools-from-preset! "units-runtime-tools" {"unit.run-tests" true})
  (preset-manager:set-override "units-edit-tools" :off)
  (preset-manager:set-override "general-world-tools" :off)
  (preset-manager:set-override "general-file-write-tools" :off)
  (preset-manager:set-override "general-shell-tools" :off)

  (local approvals (AgentApprovalsMod.AgentApprovals {:policy {:normal :auto
                                                               :filesystem-read :auto
                                                               :filesystem-write :auto
                                                               :destructive :auto
                                                               :shell :auto}}))
  (local surface (AgentToolSurfaceMod.AgentToolSurface
                   {:presets preset-manager :mcp-tools tool-registry :approvals approvals}))
  (local mcp-sync (AgentMcpSyncMod.AgentMcpSync
                    {:surface surface :tool-registry tool-registry
                     :change-source preset-manager :owner "test-tic-tac-toe-online"}))
  (mcp-sync:start)

  {:preset-registry preset-registry :adapter-registry adapter-registry
   :preset-manager preset-manager :tool-registry tool-registry
   :approvals approvals :surface surface :mcp-sync mcp-sync :app app
   :cleanup (fn [] (mcp-sync:stop))})

(fn start-opencode [bridge]
  (local check (process.run {:args [TEST_CONFIG.opencode-path "--version"] :timeout 5}))
  (assert (= check.exit-code 0) (.. "opencode not available: " (or check.stderr "")))
  (local server (OpencodeSdk.Opencode {:opencode-path TEST_CONFIG.opencode-path :port 0 :env (bridge:opencode-env)}))
  (print (.. "  opencode: " (server.server.url)))
  (var health nil)
  (server.global.health (fn [r] (set health r)))
  (wait-for #(not= health nil) 5000)
  (assert-response-ok health "health")
  (local model {:providerID TEST_CONFIG.provider-id :modelID TEST_CONFIG.model-id})
  {:server server :model model :config-dir (. (bridge:opencode-env) "XDG_CONFIG_HOME")})

(fn start-bridge [root tool-registry]
  (local bridge (AgentOpencodeMcpBridgeMod.AgentOpencodeMcpBridge
                  {:tools tool-registry :data-dir (fs.join-path root "agent-opencode")}))
  (bridge:start)
  (print (.. "  MCP port: " (. (bridge:status) "port")))
  bridge)

(fn setup-runner [root server model preset-manager surface approvals app]
  (local session-dir (fs.join-path root "agent-sessions"))
  (fs.create-dirs session-dir)
  (local registry (AgentRegistryMod.AgentRegistry {:deps {:app app}}))
  (SpaceAgentMod.register registry
    {:app app :presets preset-manager :tools surface :approvals approvals
     :model model :providers {:opencode server}})
  (local runner (AgentRunnerMod.AgentRunner
                  {:data-dir session-dir :registry registry
                   :deps {:app app :presets preset-manager :tools surface
                          :approvals approvals :agents registry :providers {:opencode server}}}))
  {:registry registry :runner runner :session-dir session-dir})

(fn cleanup-test [handles]
   (var errs [])
   (fn safe [label f]
     (local (ok err) (pcall f))
     (when (not ok) (table.insert errs (.. label ": " (tostring err)))))
   (when handles.runner (safe "runner" #(handles.runner:drop)))
   (when handles.server (safe "server" #(handles.server.close)))
   (when handles.bridge (safe "bridge" #(handles.bridge:stop)))
   (when handles.pipeline (safe "pipeline" #(handles.pipeline:cleanup)))
   (when handles.config-dir (safe "config" #(when (fs.exists handles.config-dir) (fs.remove-all handles.config-dir))))
   (when handles.mgr (safe "mgr-clear" #(handles.mgr:clear)))
   (when handles.app (safe "launcher-runtime" #(handles.app.launcher:clear-runtime)))
   (when handles.root (safe "root" #(when (fs.exists handles.root) (fs.remove-all handles.root))))
   (when handles.temp-handle (safe "temp" #(handles.temp-handle:drop)))
   (when handles.restore-app (handles.restore-app))
   (when (> (length errs) 0) (print "  cleanup: " (table.concat errs "; "))))

(fn with-cleanup [handles f]
  (local (ok result) (pcall f))
  (cleanup-test handles)
  (when (not ok) (error result)) result)

(fn run-test [name f]
  (io.write (.. "  " name " ... "))
  (io.flush)
  (local (ok result) (pcall f))
  (if ok
      (do (set passed (+ passed 1)) (print "PASS"))
      (do (set failed (+ failed 1))
          (table.insert failures {:name name :error (tostring result)})
          (print (.. "FAIL: " (tostring result))))))

(fn run-turn [runner session-id prompt]
  (var completed nil)
  (var items-log [])
  (local handle (runner:run-turn session-id prompt
    {:on-complete (fn [r] (set completed r))
     :on-item (fn [item] (table.insert items-log item))}))
  (print "  waiting...")
  (local status (handle:wait TEST_CONFIG.turn-timeout-ms))
  (print (.. "  status: " status))
  (SessionMod.invalidate-cache session-id)
  (local reloaded (runner:get-session session-id))
  {:handle handle :status status :completed completed
   :items (or reloaded.items []) :items-log items-log})

(fn log-items [items label]
  (print (.. "  --- " label " ---"))
  (var n 0)
  (each [_ item (ipairs items)]
    (if (= item.type "tool-call")
        (do (set n (+ n 1))
            (print (.. "  [" n "] TOOL " item.name))
            (when item.arguments
              (local s (tostring item.arguments))
              (print (.. "      args: " (string.sub s 1 400)))))
        (= item.type "tool-result")
        (print (.. "      result: " (string.sub (or item.output "") 1 400)))
        (and (= item.type "message") (= item.role "assistant"))
        (print (.. "      [assistant] " (string.sub (or item.content "") 1 400)))
        (= item.type "error")
        (print (.. "      [ERROR] " (string.sub (or item.error "") 1 400)))))
  (print "  --- end ---"))

(fn check-launcher-smoke-eval [items]
   (var found false)
   (local smoke-call-ids {})
   (each [_ item (ipairs items)]
     (when (and (= item.type "tool-call")
                (or (= item.name "unit_eval") (string.find (or item.name "") "unit_eval" 1 true)))
       (local args-str (tostring (or item.arguments "")))
       (when (or (string.find args-str "launcher:get" 1 true)
                 (string.find args-str "entry%.run" 1 true)
                 (string.find args-str "launchable" 1 true))
         (local call-id (or item.call-id item.call_id))
         (when call-id
           (tset smoke-call-ids call-id true)))))
   (each [_ item (ipairs items)]
     (when (and (= item.type "tool-result")
                (not item.is-error)
                (or (= item.name "unit_eval") (string.find (or item.name "") "unit_eval" 1 true))
                (. smoke-call-ids (or item.call-id item.call_id)))
       (set found true)))
   found)

(fn check-tool-succeeded [items tool-name]
  (var found false)
  (each [_ item (ipairs items)]
    (when (and (= item.type "tool-result")
               (not item.is-error)
               (or (= item.name tool-name) (string.find (or item.name "") tool-name 1 true)))
      (set found true)))
  found)

(fn tool-name-matches? [item tool-name]
  (or (= item.name tool-name) (string.find (or item.name "") tool-name 1 true)))

(fn target-arg? [args]
  (local text (tostring (or args "")))
  (or (string.find text "tic-tac-toe" 1 true)
      (string.find text "user-tic-tac-toe" 1 true)))

(fn check-target-tool-succeeded [items tool-name]
  (local target-call-ids {})
  (each [_ item (ipairs items)]
    (when (and (= item.type "tool-call")
               (tool-name-matches? item tool-name)
               (target-arg? item.arguments))
      (local call-id (or item.call-id item.call_id))
      (when call-id
        (tset target-call-ids call-id true))))
  (var found false)
  (each [_ item (ipairs items)]
    (when (and (= item.type "tool-result")
               (not item.is-error)
               (. target-call-ids (or item.call-id item.call_id)))
      (set found true)))
  found)

(fn review-dir-safe? [review-dir]
  (local root (fs.absolute "/tmp/space"))
  (local path (fs.absolute review-dir))
  (and (> (# path) (+ (# root) 1))
       (= (string.sub path 1 (# root)) root)
       (= (string.sub path (+ (# root) 1) (+ (# root) 1)) "/")))

;; ═══════════════════════════════════════
;; Artifact preservation
;; ═══════════════════════════════════════

(fn copy-generated-artifacts [code-dir review-dir]
  (assert (review-dir-safe? review-dir)
          (.. "SPACE_TICTACTOE_REVIEW_DIR must be a child of /tmp/space: " review-dir))
  (print (.. "  [review] copying artifacts to " review-dir))
  (when (fs.exists review-dir)
    (fs.remove-all review-dir))
  (fs.create-dirs review-dir)
  (local ttt-dir (fs.join-path code-dir "tic-tac-toe"))
  (var copied 0)
  (fn copy-tree [src dst]
    (when (fs.exists src)
      (local entries (fs.list-dir src))
      (each [_ entry (ipairs (or entries []))]
        (local src-path entry.path)
        (local dst-path (fs.join-path dst entry.name))
        (if entry.is-dir
            (do
              (fs.create-dirs dst-path)
              (copy-tree src-path dst-path))
            (do
              (fs.write-file dst-path (fs.read-file src-path))
              (set copied (+ copied 1)))))))
  (when (fs.exists ttt-dir)
    (fs.create-dirs (fs.join-path review-dir "tic-tac-toe"))
    (copy-tree ttt-dir (fs.join-path review-dir "tic-tac-toe")))
  (local flat-file (fs.join-path code-dir "tic-tac-toe.fnl"))
  (when (fs.exists flat-file)
    (fs.write-file (fs.join-path review-dir "tic-tac-toe.fnl") (fs.read-file flat-file))
    (set copied (+ copied 1)))
  (print (.. "  [review] copied " copied " artifact(s) to " review-dir))
  copied)

;; ═══════════════════════════════════════
;; Unit verification
;; ═══════════════════════════════════════

(fn verify-unit-registered! [mgr]
  (local existing (mgr:get "user-tic-tac-toe"))
  (assert existing "agent must register user-tic-tac-toe before finishing")
  (assert (existing:loaded?) "agent-registered unit user-tic-tac-toe should be loaded")
  (print "  [verify] agent-registered unit found and loaded: OK")
  existing)

;; ═══════════════════════════════════════
;; Launchable verification
;; ═══════════════════════════════════════

(fn find-launched-game [app]
  (var found nil)
  (each [_ launchable (ipairs (app.launcher:list))]
    (when (or (string.find (string.lower launchable.name) "tic")
              (string.find (string.lower launchable.name) "tac")
              (string.find (string.lower launchable.name) "toe"))
      (set found launchable)))
  (assert found "no tic-tac-toe launchable found in launcher after unit init")
  (print (.. "  [verify] launchable registered: " found.name))
  found)

;; ═══════════════════════════════════════
;; Test: Agent builds tic-tac-toe game
;; ═══════════════════════════════════════

(fn test-tic-tac-toe-game []
  (local root (fresh-root))
  (var handles {})
  (set handles.root root)
  (local saved-app _G.app)
  (set handles.restore-app
       #(do
          (set _G.app saved-app)
          (StateSystemBindings.bind-states-host (and saved-app saved-app.states))))

  (with-cleanup handles
    (fn []
      (local assets-path (os.getenv "SPACE_ASSETS_PATH"))
      (assert assets-path "SPACE_ASSETS_PATH must be set")

      (local persist-code-dir (os.getenv "SPACE_TICTACTOE_CODE_DIR"))
      (local review-dir (or (os.getenv "SPACE_TICTACTOE_REVIEW_DIR")
                            "/tmp/space/tic-tac-toe-review"))
      (var code-dir nil)
      (local mgr (UnitManager {}))
      (if persist-code-dir
          (do
            (set code-dir persist-code-dir)
            (set handles.temp-handle nil))
          (do
            (local temp (fresh-temp-dir "tic-tac-toe-"))
            (set handles.temp-handle temp.handle)
            (set code-dir temp.path)
            (set handles.mgr mgr)))

      (when (not persist-code-dir)
        (local ttt-dir (fs.join-path code-dir "tic-tac-toe"))
        (when (fs.exists ttt-dir)
          (fs.remove-all ttt-dir))
        (local ttt-flat (fs.join-path code-dir "tic-tac-toe.fnl"))
        (when (fs.exists ttt-flat)
          (fs.remove-all ttt-flat)))

      (local mock-app (make-mock-app code-dir mgr assets-path))
      (set handles.app mock-app)
      (set _G.app mock-app)

      ;; 1. Set up agent pipeline
      (local pipeline (setup-full-pipeline mock-app))
      (set handles.pipeline pipeline)

      (local bridge (start-bridge root pipeline.tool-registry))
      (set handles.bridge bridge)

      (local {: server : config-dir : model} (start-opencode bridge))
      (set handles.server server)
      (set handles.config-dir config-dir)

      (local {: runner} (setup-runner root server model
                         pipeline.preset-manager pipeline.surface pipeline.approvals mock-app))
      (set handles.runner runner)

      ;; 2. Run turn: agent builds tic-tac-toe
      (local session (runner:create-session "space-agent"))

      (local prompt
        (.. "Create a playable tic-tac-toe game for this application.\n"
            "\n"
            "Game rules:\n"
            "- Two players (X and O) take turns marking cells on a 3x3 grid.\n"
            "- First player to get three in a row, column, or diagonal wins.\n"
            "- If all nine cells are filled with no winner, the game is a draw.\n"
            "- Players should be able to start a new game at any time.\n"
            "\n"
            "Before you start building, explore how the existing Tetris game\n"
            "is implemented. Study its architecture, patterns, and how it\n"
            "connects game logic, input, state management, and rendering.\n"
            "Then build tic-tac-toe following the same patterns.\n"
            "\n"
             "Build it as a user unit named tic-tac-toe in the code directory.\n"
             "Use the space_unit_* tools for generated source files; do not\n"
             "write or modify files under assets/lua or the repository tree.\n"
             "For a multi-file unit, first create a directory unit with a\n"
             "minimal init/drop stub that does not require submodules. Then\n"
             "add submodule files with space_unit_edit_file {create? true}.\n"
             "After submodules exist, replace init.fnl with the final code.\n"
             "The game should be launchable from the launcher. Register the\n"
             "runtime launchable with app.launcher:register in init and\n"
             "unregister it with app.launcher:unregister in drop; do not use\n"
             "a separate app.launchables table.\n"
            "\n"
              "After building, register and load the unit. Then verify it\n"
              "loaded successfully with space_unit_list. Launch the registered\n"
              "launcher entry exactly once through the runtime, fixing any\n"
              "launch/build error before you finish. Use only this generic\n"
              "launch smoke pattern as the space_unit_eval :expression, adapted\n"
              "only for the exact launchable name:\n"
              "  (do (local entry (assert (app.launcher:get \"Tic-Tac-Toe\") \"launchable missing\")) (entry.run) true)\n"
              "Do not create or run generated test files; this harness performs\n"
              "generic verification after you finish.\n"
              "Do not run unit_eval against generated game modules or game\n"
              "internals; unit_eval is only for the launcher smoke above.\n"
              "Do not inspect logs or perform extra manual review after the\n"
              "unit list and launch smoke succeed; stop using tools immediately.\n"
             "\n"
             "Reply with exactly DONE when finished."))

      ;; Agent execution and post-agent verification are wrapped so artifacts are
      ;; copied even when the turn or any generic harness assertion fails.
      (local (verify-ok verify-err)
        (pcall
          (fn []
            (print "\n  == Agent: build tic-tac-toe game ==")
            (local result (run-turn runner session.id prompt))
            (log-items result.items "tic-tac-toe build")

            ;; 3. Assert agent completion
            (assert result.completed "agent turn should produce a completed response")
            (assert (= result.status "completed")
                    (.. "agent turn should reach completed status, got: " (tostring result.status)))
            (print "  [verify] agent completed: OK")

            ;; 4. Verify agent behavior — code exploration
            (assert (or (check-tool-succeeded result.items "search")
                        (check-tool-succeeded result.items "read_file"))
                    "agent should successfully use search or read_file to explore the codebase")
            (print "  [verify] agent successfully used search/read_file for exploration: OK")

            ;; 5. Verify agent behavior — unit lifecycle
            ;; MCP tool names have the "space_" prefix; substring-match on the suffix.
            (assert (or (check-target-tool-succeeded result.items "unit_create")
                        (check-target-tool-succeeded result.items "unit_edit_file")
                        (check-target-tool-succeeded result.items "unit_register"))
                    "agent should successfully use unit_create, unit_edit_file, or unit_register for tic-tac-toe")
            (print "  [verify] agent successfully used tic-tac-toe unit lifecycle tools: OK")

            ;; 6. Check generated unit entrypoint exists. Do not require any game-specific
            ;; submodule names; tic-tac-toe is only the scenario workload.
            (local dir-init-file (fs.join-path code-dir "tic-tac-toe" "init.fnl"))
            (local flat-file (fs.join-path code-dir "tic-tac-toe.fnl"))
            (var init-file dir-init-file)
            (var has-init? (fs.exists init-file))
            (when (and (not has-init?) (fs.exists flat-file))
              (print "  [verify] flat unit file found: tic-tac-toe.fnl")
              (set init-file flat-file)
              (set has-init? true))
            (assert has-init? "agent must generate tic-tac-toe/init.fnl or tic-tac-toe.fnl")
            (print "  [verify] unit entrypoint exists: OK")

            ;; 7. Print generated source for manual review without constraining internals.
            (local ttt-dir (fs.join-path code-dir "tic-tac-toe"))
            (local ttt-stat (fs.stat ttt-dir))
            (var ttt-entries nil)
            (when (and ttt-stat ttt-stat.exists ttt-stat.is-dir)
              (set ttt-entries (fs.list-dir ttt-dir)))

            (print "\n  ===== GENERATED SOURCE REVIEW =====")
            (when (and has-init? (not= init-file flat-file))
              (print (.. "  --- tic-tac-toe/init.fnl (" (# (fs.read-file init-file)) " bytes) ---"))
              (each [line (string.gmatch (fs.read-file init-file) "[^\n]+")] (print (.. "  | " line)))
              (print "  --- end ---\n"))
            (when (= flat-file init-file)
              (print (.. "  --- tic-tac-toe.fnl (" (# (fs.read-file flat-file)) " bytes) ---"))
              (each [line (string.gmatch (fs.read-file flat-file) "[^\n]+")] (print (.. "  | " line)))
              (print "  --- end ---\n"))

            (each [_ entry (ipairs (or ttt-entries []))]
              (when (and entry.is-file
                         (string.match entry.name "%.fnl$")
                         (not= entry.path init-file))
                (print (.. "  --- tic-tac-toe/" entry.name " (" (# (fs.read-file entry.path)) " bytes) ---"))
                (each [line (string.gmatch (fs.read-file entry.path) "[^\n]+")] (print (.. "  | " line)))
                (print "  --- end ---\n")))
            (print "  ===== END GENERATED SOURCE =====")

            ;; 8. Verify unit is registered and loaded
            (verify-unit-registered! mgr)

            ;; 9. Verify agent ran launcher smoke via unit_eval
            (assert (check-launcher-smoke-eval result.items)
                    "agent should use unit_eval to run launcher smoke against registered launchable")
            (print "  [verify] agent ran launcher smoke via unit_eval: OK")

            ;; 10. Verify launchable registration
            (local launchable (find-launched-game app))

            ;; 11. Launchable smoke test: run against the mock scene/app.
            (local before-children (# app.scene.children))
            (local before-state (app.states:active-name))
            (local before-canvas-visible app.canvas-visible?)
            (local before-canvas-mode app.active-canvas-mode)
            (local before-interaction-surface app.active-interaction-surface)
            (local (run-ok run-err) (pcall #(launchable.run)))
            (assert run-ok (.. "launchable run failed in mock app: " (tostring run-err)))
            (local after-children (# app.scene.children))
            (local after-state (app.states:active-name))
            (local after-canvas-visible app.canvas-visible?)
            (local after-canvas-mode app.active-canvas-mode)
            (local after-interaction-surface app.active-interaction-surface)
            (assert (or (> after-children before-children)
                        (not= after-state before-state)
                        (not= after-canvas-visible before-canvas-visible)
                        (not= after-canvas-mode before-canvas-mode)
                         (not= after-interaction-surface before-interaction-surface))
                     "launchable run should produce an observable app effect")
            (print "  [verify] launchable run: OK")

            (when (not persist-code-dir)
              (mgr:clear)))))
      ;; Always copy artifacts, even on verification failure
      (copy-generated-artifacts code-dir review-dir)
      (when (not verify-ok)
        (error verify-err)))))

;; ═══════════════════════════════════════
;; Main
;; ═══════════════════════════════════════

(fn main []
  (print "Agent Online: Tic-Tac-Toe Game")
  (print "==============================")
  (math.randomseed (math.floor (now-ms)))
  (run-test "build tic-tac-toe game" test-tic-tac-toe-game)
  (print "")
  (print "==========================")
  (print (.. "Results: " passed " passed, " failed " failed"))
  (when (> (# failures) 0)
    (print "Failures:")
    (each [_ f (ipairs failures)] (print (.. "  " f.name ": " f.error))))
  (when (> failed 0) (os.exit 1)))

{:main main}
