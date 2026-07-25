;; Live E2E test: agent adds thorough tests to the real bubbles unit and fixes any issues.
;; Verifies the agent can read logs to debug, self-correct code, and create/run unit tests.
;;
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-units-bubbles:main

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
(local glm (require :glm))
(local VectorBufferMod (require :vector-buffer))
(local Activities (require :activities))

(local TEST_CONFIG
  {:opencode-path "opencode"
   :provider-id "opencode"
   :model-id "big-pickle"
   :root-prefix "/tmp/space/tests/agent-units-bubbles"
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

(fn make-mock-app [code-dir unit-manager assets-path]
  (local tri-vec (VectorBufferMod.VectorBuffer 1024))
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
  (local app
    {:unit-manager unit-manager
     :code-dir code-dir
     :assets-path assets-path
     :canvas fake-canvas
     :clickables {:register-left-click-void-callback (fn [_self _cb] true)
                  :unregister-left-click-void-callback (fn [_self _cb] true)}
     :hoverables {:register (fn [_] true)}
     :intersectables {:register (fn [_] true)}
     :active-activity-id nil
     :workspace-shell-changed (Signal)
     :activities-changed (Signal)
     :activity-root-actions nil
     :activity-selection-actions nil
     :activity-update nil
     :activity-input-handlers nil
     :activity-left-dock-builder nil
     :activity-command-hints-provider nil
     :activity-delete-selection nil
     :activity-activate-focused nil
     :activity-drawing-enabled? true
     :activity-context-enricher nil
     :activity-target-enabled? nil
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
                     :change-source preset-manager :owner "test-agent-units-bubbles"}))
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

;; ═══════════════════════════════════════
;; Test: Agent tests and fixes bubbles unit
;; ═══════════════════════════════════════

(fn test-bubbles-tests-and-fixes []
  (local root (fresh-root))
  (var handles {})
  (set handles.root root)
  (local saved-app _G.app)
  (set handles.restore-app #(set _G.app saved-app))

  (with-cleanup handles
    (fn []
      (local assets-path (os.getenv "SPACE_ASSETS_PATH"))
      (assert assets-path "SPACE_ASSETS_PATH must be set")

      ;; This test mutates the bubbles unit source directory. Always require an
      ;; explicit env var pointing to the test directory — never fall back to the
      ;; real user code directory.
      (local code-dir (os.getenv "SPACE_BUBBLES_CODE_DIR"))
      (assert code-dir "SPACE_BUBBLES_CODE_DIR must be set to a test code directory")
      (print (.. "  code-dir: " code-dir))
      (assert (fs.exists code-dir) (.. "code-dir must exist: " code-dir))
      (assert (fs.exists (fs.join-path code-dir "bubbles"))
              (.. "bubbles unit not found in " code-dir))

      (local mgr (UnitManager {}))
      (local app (make-mock-app code-dir mgr assets-path))
      (set _G.app app)

      ;; Register the existing bubbles unit so the agent sees it
      (local module-paths (.. code-dir "/?.fnl;" code-dir "/?/init.fnl"))
      (local init-path (fs.join-path code-dir "bubbles" "init.fnl"))
      (local unit (Units.ModuleUnit {:id "bubbles"
                                     :module-name "bubbles"
                                     :module-paths module-paths
                                     :source :user
                                     :owned-paths [(fs.join-path code-dir "bubbles") init-path]}))
      (mgr:register unit)
      (unit:load {})

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

      ;; 2. Run turn: agent adds tests and fixes bugs
      (local session (runner:create-session "space-agent"))

      (local prompt
        (.. "The bubbles activity unit is registered in " code-dir "/bubbles/.\n"
            "It currently has NO tests. Your job:\n"
            "\n"
            "1. Inspect the unit: call space_unit_inspect for id \"bubbles\" to see what files exist.\n"
            "2. Read each source file (init.fnl, controller.fnl, render.fnl, input.fnl) to\n"
            "   understand how the unit works.\n"
            "3. Check the log with space_unit_read_log for any runtime errors from this unit.\n"
            "4. Create thorough test modules using space_unit_create_test for each component.\n"
            "   Follow the test conventions: each test module requires :tests.runner,\n"
            "   exports {:main main :tests [...]}, and runs via space_unit_run_tests.\n"
            "5. Run the tests with space_unit_run_tests. If any fail, debug by reading\n"
            "   the log and source files, fix whatever is wrong (in tests or unit code),\n"
            "   and re-run until everything passes.\n"
            "6. Make sure the unit works correctly end-to-end: no runtime errors, no\n"
            "   test failures.\n"
            "\n"
            "The tests should cover:\n"
            "- Controller logic (spawning, updates, hit testing, pop, snapshot/restore)\n"
            "- Renderer triangle buffer lifecycle and circle vertex generation\n"
            "- Init/drop lifecycle and mode registration\n"
            "- Input handler structure\n"
            "\n"
            "Reply DONE when all tests pass."))

      (print "\n  == Agent: test and fix bubbles ==")
      (local result (run-turn runner session.id prompt))
      (log-items result.items "bubbles test and fix")

      ;; Verify agent created test files
      (local test-files [{:name "test-init" :module "test-init" :path (fs.join-path code-dir "bubbles" "test-init.fnl")}
                         {:name "test-controller" :module "test-controller" :path (fs.join-path code-dir "bubbles" "test-controller.fnl")}
                         {:name "test-render" :module "test-render" :path (fs.join-path code-dir "bubbles" "test-render.fnl")}
                         {:name "test-input" :module "test-input" :path (fs.join-path code-dir "bubbles" "test-input.fnl")}])

      (var test-files-created 0)
      (each [_ tf (ipairs test-files)]
        (when (fs.exists tf.path)
          (set test-files-created (+ test-files-created 1))
          (local src (fs.read-file tf.path))
          (print (.. "  [verify] " tf.name ".fnl exists (" (# src) " bytes)"))
          ;; Verify test file has correct structure
          (assert (or (string.find src "runner" 1 true)
                      (string.find src "run-tests" 1 true)
                      (string.find src "tests" 1 true))
                  (.. tf.name " should contain test infrastructure"))))

      (print (.. "  [verify] test files created: " test-files-created " / " (length test-files)))
      (assert (>= test-files-created 2) "agent should create at least 2 test modules")

      ;; Check agent used the read-log tool for debugging
      (assert (check-tool-called result.items "read_log") "agent should read the log to find errors")
      (print "  [verify] agent read log: OK")

      ;; Check agent ran tests
      (assert (check-tool-called result.items "run_tests") "agent should run unit tests")
      (print "  [verify] agent ran tests: OK")

      ;; Check agent read source files
      (assert (check-tool-called result.items "read_file") "agent should read source files")
      (print "  [verify] agent read source files: OK")

      ;; Verify the controller.fnl fix (should have self param in update!)
      (local controller-src (fs.read-file (fs.join-path code-dir "bubbles" "controller.fnl")))
      (assert (string.find controller-src "update! %[self dt%]" 1 false)
              "controller.fnl update! should have [self dt] parameters")
      (print "  [verify] controller update! signature fixed: OK")

      ;; Run all tests ourselves to verify they pass
      (print "  [verify] running tests...")
      (local space-bin (or (os.getenv "SPACE_BIN") (fs.join-path (fs.cwd) "build" "space")))
      (local fennel-path (.. code-dir "/?.fnl;" code-dir "/?/init.fnl"))
      (var all-tests-passed true)

      (each [_ tf (ipairs test-files)]
        (when (fs.exists tf.path)
          (local module-name (.. "bubbles." tf.module))
          (local result (process.run {:args [space-bin "-m" (.. module-name ":main")]
                                     :env {:FENNEL_PATH fennel-path
                                           :FENNEL_MACRO_PATH fennel-path
                                           :SPACE_ASSETS_PATH assets-path
                                           :SPACE_DISABLE_AUDIO "1"}
                                     :timeout 30}))
          (if (= result.exit-code 0)
              (print (.. "  [verify] " tf.name " tests: PASS"))
              (do
                (print (.. "  [verify] " tf.name " tests: FAIL (exit " result.exit-code ")"))
                (print (or result.stdout ""))
                (print (or result.stderr ""))
                (set all-tests-passed false)))))

      (assert all-tests-passed "all test modules should pass")

      ;; Clean up unit manager but leave the source directory as-is (caller owns the dir).
      (mgr:clear))))

;; ═══════════════════════════════════════
;; Main
;; ═══════════════════════════════════════

(fn main []
  (print "Agent Units Online: Bubbles Tests and Fixes")
  (print "==========================================")
  (math.randomseed (math.floor (now-ms)))
  (run-test "add tests and fix bubbles bugs" test-bubbles-tests-and-fixes)
  (print "")
  (print "==========================")
  (print (.. "Results: " passed " passed, " failed " failed"))
  (when (> (# failures) 0)
    (print "Failures:")
    (each [_ f (ipairs failures)] (print (.. "  " f.name ": " f.error))))
  (when (> failed 0) (os.exit 1)))

{:main main}
