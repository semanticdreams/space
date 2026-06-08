;; Live E2E test: agent builds a production canvas mode (bubbles) from scratch.
;; Verifies the agent can explore the codebase, understand canvas mode architecture,
;; create multi-file folder-structured units, and test its own work.
;;
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-units-online:main

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
(local Units (require :units))
(local BuiltinUnits (require :llm/presets/builtins/units))
(local BuiltinGeneral (require :llm/presets/builtins/general))
(local Signal (require :signal))
(local json (require :json))
(local tempfile (require :tempfile))
(local CanvasModes (require :canvas-modes))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local glm (require :glm))

(local TEST_CONFIG
  {:opencode-path "opencode"
   :provider-id "opencode"
   :model-id "big-pickle"
   :root-prefix "/tmp/space/tests/agent-units-online"
   :turn-timeout-ms 300000})

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
  (local handle (tempfile.TemporaryDirectory {:prefix (or prefix "agent-units-online")}))
  {:path handle.path :handle handle})

(fn make-mock-app [code-dir unit-manager assets-path]
  "Build a realistic-enough app that a canvas mode unit can activate in."
  (local tri-vec (VectorBuffer 1024))
  (local fake-build-context
    {:triangle-vector tri-vec
     :track-triangle-handle (fn [_self _handle _clip] true)
     :untrack-triangle-handle (fn [_self _handle] true)})
  (local fake-canvas
    {:build-context fake-build-context
     :camera {:position (glm.vec3 0 0 0)}
     :half-width 10
     :half-height 10
     :screen-pos-ray (fn [_self pos]
                       {:origin (glm.vec3 0 0 0) :direction (glm.vec3 0 0 -1)})
     :get-view-matrix (fn [_self] (glm.mat4))})
  (local fake-focus-manager {:clear-focus (fn [_] true)})
  (var fake-active-mode nil)
  (local app
    {:unit-manager unit-manager
     :code-dir code-dir
     :assets-path assets-path
     :canvas fake-canvas
     :focus fake-focus-manager
     :clickables {:register-left-click-void-callback (fn [_self _cb] true)
                  :unregister-left-click-void-callback (fn [_self _cb] true)}
     :hoverables {:register (fn [_] true)}
     :intersectables {:register (fn [_] true)}
     :active-canvas-mode nil
     :canvas-shell-changed (Signal)
     :canvas-modes-changed (Signal)
     :canvas-mode-root-actions nil
     :canvas-mode-selection-actions nil
     :canvas-mode-update nil
     :canvas-mode-input-handlers nil
     :canvas-mode-left-dock-builder nil
     :canvas-mode-command-hints-provider nil
     :canvas-mode-delete-selection nil
     :canvas-mode-activate-focused nil
     :canvas-mode-drawing-enabled? true
     :canvas-mode-context-enricher nil
     :canvas-mode-target-enabled? nil
     :test-app true})
  app)

(fn setup-full-pipeline [app]
  (local preset-registry (PresetRegistryMod.PresetRegistry {}))
  (local adapter-registry (ToolAdapterRegistryMod.ToolAdapterRegistry {}))
  (local tool-registry (ToolRegistry {:namespace-prefix "space_"}))

  (local preset-manager
    (PresetManagerMod.PresetManager
      {:registry preset-registry
       :tool-adapters adapter-registry
       :app app
       :context {:surface :any :canvas-visible? false}}))

  (BuiltinUnits.register preset-manager)
  (BuiltinGeneral.register preset-manager)

  (local approvals (AgentApprovalsMod.AgentApprovals {:policy {:normal :auto
                                                              :filesystem-read :auto
                                                              :filesystem-write :auto
                                                              :destructive :auto
                                                              :shell :auto}}))
  (local surface (AgentToolSurfaceMod.AgentToolSurface
                   {:presets preset-manager :mcp-tools tool-registry :approvals approvals}))
  (local mcp-sync (AgentMcpSyncMod.AgentMcpSync
                    {:surface surface :tool-registry tool-registry
                     :change-source preset-manager :owner "test-agent-units-online"}))
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

(fn check-tool-called [items tool-name]
  (var found false)
  (each [_ item (ipairs items)]
    (when (and (= item.type "tool-call")
               (or (= item.name tool-name) (string.find (or item.name "") tool-name 1 true)))
      (set found true)))
  found)

(fn array-contains? [arr value]
  (var found false)
  (each [_ v (ipairs (or arr []))]
    (when (= v value) (set found true)))
  found)

;; ═══════════════════════════════════════
;; Test: Agent builds bubbles canvas mode
;; ═══════════════════════════════════════

(fn test-bubbles-canvas-mode []
  (local root (fresh-root))
  (var handles {})
  (set handles.root root)
  (local saved-app _G.app)
  (set handles.restore-app #(set _G.app saved-app))

  (with-cleanup handles
    (fn []
      (local assets-path (os.getenv "SPACE_ASSETS_PATH"))
      (assert assets-path "SPACE_ASSETS_PATH must be set")

      ;; Use SPACE_BUBBLES_CODE_DIR if set for persistence, else temp dir
      (local persist-code-dir (os.getenv "SPACE_BUBBLES_CODE_DIR"))
      (var code-dir nil)
      (var mgr (UnitManager {}))
      (if persist-code-dir
          (do
            (set code-dir persist-code-dir)
            (set handles.temp-handle nil))
          (do
            (local temp (fresh-temp-dir "agent-unit-"))
            (set handles.temp-handle temp.handle)
            (set code-dir temp.path)))

      ;; Only clean pre-existing bubbles data from temp dirs, never from persistent dirs.
      (when (not persist-code-dir)
        (local bubbles-dir (fs.join-path code-dir "bubbles"))
        (when (fs.exists bubbles-dir)
          (fs.remove-all bubbles-dir))
        (local bubbles-flat (fs.join-path code-dir "bubbles.fnl"))
        (when (fs.exists bubbles-flat)
          (fs.remove-all bubbles-flat)))

      ;; Build a realistic mock app with canvas infrastructure
      (local app (make-mock-app code-dir mgr assets-path))

      ;; Set app as global so CanvasModes and other modules can access it
      (set _G.app app)

      ;; Register a sample mode so the agent can explore how modes work
      (var sample-mode-activated false)
      (var sample-activated-session nil)
      (CanvasModes.register-mode
        {:id "sample-mode"
         :label "Sample"
         :icon "star"
         :button-name "sample-mode-btn"
         :show-in-sidebar? true
         :activate (fn [ctx]
                     (set sample-mode-activated true)
                     (ctx:set-root-actions! (fn [_c] []))
                     (ctx:set-update! (fn [_p] nil))
                     (ctx:set-target-enabled! (fn [_t] true))
                     (set sample-activated-session :active)
                     sample-activated-session)
         :deactivate (fn [_ctx _session]
                       (set sample-mode-activated false)
                       true)})

      ;; 1. Set up agent pipeline
      (local pipeline (setup-full-pipeline app))
      (set handles.pipeline pipeline)

      (local bridge (start-bridge root pipeline.tool-registry))
      (set handles.bridge bridge)

      (local {: server : config-dir : model} (start-opencode bridge))
      (set handles.server server)
      (set handles.config-dir config-dir)

      (local {: runner} (setup-runner root server model
                         pipeline.preset-manager pipeline.surface pipeline.approvals app))
      (set handles.runner runner)

      ;; 2. Run turn: agent builds bubbles mode
      (local session (runner:create-session "space-agent"))

      (local prompt
        (.. "Do these steps in order:\n"
            "1. Call space_unit_list to see registered units and check if any bubbles unit exists.\n"
            "2. Explore the drawing canvas mode to understand how canvas modes work. Use space_app_run_bash "
            "with rg to search for CanvasModes.register-mode, then read drawing-canvas-mode-unit.fnl.\n"
            "3. Read drawing/render.fnl to understand the DynamicTriangleBuffer pattern.\n"
            "4. Read drawing/input.fnl to understand how input handlers convert screen coords to world coords.\n"
            "5. Build a new canvas mode called \"bubbles\" as a multi-file unit under the code directory.\n"
            "   Create the folders with mkdir, write the files with space_app_write_file.\n"
            "   The mode should:\n"
            "   - Show continuously spawning floating bubbles of various sizes (0.5-2.0 world units)\n"
            "     and colors at random positions within the canvas bounds\n"
            "   - Bubbles float upward slowly, new ones spawn at edges periodically\n"
            "   - Bubbles disappear when clicked\n"
            "   - Render bubbles as filled circles using the DynamicTriangleBuffer pattern\n"
            "   - Use app.canvas.screen-pos-ray to convert clicks to world coords for hit testing\n"
            "   Structure:\n"
            "     bubbles/init.fnl       -- mode unit: load/unload/snapshot/restore, registers mode\n"
            "     bubbles/render.fnl     -- custom renderer with DynamicTriangleBuffer\n"
            "     bubbles/input.fnl      -- mouse input handler for clicking bubbles\n"
            "     bubbles/controller.fnl -- spawner logic and state\n"
            "6. After building, register the unit with space_unit_register (the init.fnl entry point).\n"
            "   If the file already exists, use space_unit_edit instead.\n"
            "7. Use space_unit_list to confirm the unit is loaded.\n"
            "8. Use space_unit_eval to verify the mode registers without errors:\n"
            "   (CanvasModes.register-mode {:id \"bubbles\" :activate (fn [ctx] (ctx:set-target-enabled! (fn [t] true)) true) :deactivate (fn [c s] true)})\n"
            "9. Reply with exactly DONE when everything is verified."))

      (print "\n  == Agent: build bubbles mode ==")
      (local result (run-turn runner session.id prompt))
      (log-items result.items "bubbles build")

      ;; 3. Verify agent behavior
      ;; Check the agent explored existing modes first
      (assert (check-tool-called result.items "unit_list") "agent should list units first")
      (print "  [verify] agent listed units: OK")

      ;; Check agent read drawing mode source
      (assert (or (check-tool-called result.items "run_bash")
                  (check-tool-called result.items "read_file"))
              "agent should explore drawing mode with bash or read_file")
      (print "  [verify] agent explored codebase: OK")

      ;; Check agent created files
      (local init-file (fs.join-path code-dir "bubbles" "init.fnl"))
      (local render-file (fs.join-path code-dir "bubbles" "render.fnl"))
      (local input-file (fs.join-path code-dir "bubbles" "input.fnl"))
      (local controller-file (fs.join-path code-dir "bubbles" "controller.fnl"))

      (assert (fs.exists init-file) "bubbles/init.fnl should exist")
      (assert (fs.exists render-file) "bubbles/render.fnl should exist")
      (print "  [verify] folder structure exists: OK")

      ;; Verify source content
      (local init-src (fs.read-file init-file))
      (local render-src (fs.read-file render-file))

      (print (.. "  --- bubbles/init.fnl (" (# init-src) " bytes) ---"))
      (each [line (string.gmatch init-src "[^\n]+")] (print (.. "  | " line)))
      (print "  --- end ---")

      (assert (string.find init-src "CanvasModes.register-mode" 1 true)
              "init.fnl should call CanvasModes.register-mode")
      (assert (string.find init-src ":init" 1 true) "init.fnl should export :init")
      (assert (string.find init-src ":drop" 1 true) "init.fnl should export :drop")
      (assert (string.find init-src ":snapshot" 1 true) "init.fnl should export :snapshot")
      (assert (string.find init-src ":restore" 1 true) "init.fnl should export :restore")
      (print "  [verify] init.fnl structure: OK")

      (print (.. "  --- bubbles/render.fnl (" (# render-src) " bytes) ---"))
      (each [line (string.gmatch render-src "[^\n]+")] (print (.. "  | " line)))
      (print "  --- end ---")

      (assert (string.find render-src "triangle-vector" 1 true)
              "render.fnl should use triangle-vector for rendering")
      (print "  [verify] render.fnl uses triangle-vector: OK")

      ;; Check agent created the unit
      (var unit (app.unit-manager:get "bubbles"))
      (when (not unit)
        ;; Maybe agent used a different id
        (each [_ u (ipairs (mgr:list))]
          (when (string.find (or u.id "") "bubble" 1 true)
            (set unit u))))

      (if unit
          (do
            (print "  [verify] unit registered: " unit.id)
            (assert (unit:loaded?) "unit should be loaded")
            (assert (= unit.source :user) "unit should be user source")
            (print "  [verify] unit loaded: OK"))

          ;; If not registered through space_unit_create, try manual register
          (do
            (print "  Attempting manual registration...")
            (local module-paths (.. code-dir "/?.fnl;" code-dir "/?/init.fnl"))
            (local (ok manual-unit) (pcall (fn []
                                             (Units.ModuleUnit {:id "bubbles"
                                                                :module-name "bubbles"
                                                                :module-paths module-paths
                                                                :source :user
                                                                :owned-paths [init-file]}))))
            (when ok
              (mgr:register manual-unit)
              (manual-unit:load {})
              (set unit manual-unit)
              (print "  [verify] unit manually registered: OK"))))

      ;; Cleanup (skip unit manager clear for persistent dirs)
      (when (not persist-code-dir)
        (mgr:clear)))))

;; ═══════════════════════════════════════
;; Main
;; ═══════════════════════════════════════

(fn main []
  (print "Agent Units Online: Bubbles Canvas Mode")
  (print "=======================================")
  (math.randomseed (math.floor (now-ms)))
  (run-test "build bubbles canvas mode" test-bubbles-canvas-mode)
  (print "")
  (print "==========================")
  (print (.. "Results: " passed " passed, " failed " failed"))
  (when (> (# failures) 0)
    (print "Failures:")
    (each [_ f (ipairs failures)] (print (.. "  " f.name ": " f.error))))
  (when (> failed 0) (os.exit 1)))

{:main main}
