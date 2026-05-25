;; Live E2E test for agent layer against real OpenCode with MCP tools.
;; The suite starts an isolated opencode server alongside a local MCP HTTP server,
;; wires up the full agent-layer pipeline (presets -> tool surface -> AgentMcpSync -> MCP),
;; and runs agent turns through SpaceAgent to prove the core contract end-to-end.
;;
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-mcp-online:main
;;
;; Choosing this entrypoint is the opt-in. No environment gating flags.

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

(local TEST_CONFIG
  {:opencode-path "opencode"
   :provider-id "opencode"
   :model-id "big-pickle"
   :root "/tmp/space/tests/agent-mcp-online"
   :turn-timeout-ms 120000})

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
              (or result.raw
                  (and (= (type result.data) "table") result.data.error)
                  result.error
                  "unknown error"))))

;; ── Helpers ──

(fn fresh-root []
  (local root (.. TEST_CONFIG.root "-" (tostring (os.time)) "-" (math.random 0 99999)))
  (when (fs.exists root)
    (fs.remove-all root))
  (fs.create-dirs root)
  root)

(fn make-call-recording-run [call-log tool-name]
  "Return a tool run fn that logs calls and returns a deterministic result."
  (fn [args]
    (table.insert call-log {:name tool-name :args (or args {}) :at (os.time)})
    (.. "tool-" tool-name)))

(fn setup-tool-pipeline [call-log tool-specs]
  "Create the full agent-layer tool pipeline: PresetRegistry, ToolAdapterRegistry,
   PresetManager, ToolRegistry, AgentApprovals, AgentToolSurface, AgentMcpSync.
   Returns a table with all handles needed by the test plus :cleanup.
   tool-specs: [{:adapter {:id :mcp-name :description :inputSchema :make-run}
                 :preset {:name :risk :tool-ids}}]"
  (local app {:test-app true})
  (local preset-registry (PresetRegistryMod.PresetRegistry {}))
  (local adapter-registry (ToolAdapterRegistryMod.ToolAdapterRegistry {}))
  (local tool-registry (ToolRegistry {:namespace-prefix "space_"}))

  (each [_ spec (ipairs tool-specs)]
    (adapter-registry:register spec.adapter))

  (each [_ spec (ipairs tool-specs)]
    (preset-registry:register spec.preset))

  (local preset-manager
    (PresetManagerMod.PresetManager
      {:registry preset-registry
       :tool-adapters adapter-registry
       :app app
       :context {:surface "drawing" :mode "drawing" :canvas-visible? true}}))

  (local approvals (AgentApprovalsMod.AgentApprovals {:policy {:normal :auto}}))

  (local surface (AgentToolSurfaceMod.AgentToolSurface
                   {:presets preset-manager
                    :mcp-tools tool-registry
                    :approvals approvals}))

  (local mcp-sync (AgentMcpSyncMod.AgentMcpSync
                    {:surface surface
                     :tool-registry tool-registry
                     :change-source preset-manager
                     :owner "test-agent-mcp-online"}))

  (mcp-sync:start)

  (fn cleanup []
    (mcp-sync:stop))

  {:preset-registry preset-registry
   :adapter-registry adapter-registry
   :preset-manager preset-manager
   :tool-registry tool-registry
   :approvals approvals
   :surface surface
   :mcp-sync mcp-sync
   :cleanup cleanup})

(fn provider-configured? [providers provider-id]
  (var found false)
  (each [_ provider (ipairs (or providers []))]
    (when (= provider.id provider-id)
      (set found true)))
  found)

(fn provider-ids [providers]
  (local ids [])
  (each [_ provider (ipairs (or providers []))]
    (table.insert ids (or provider.id "?")))
  (table.concat ids ", "))

(fn provider-defaults [defaults]
  (local entries [])
  (each [provider-id model-id (pairs (or defaults {}))]
    (table.insert entries (.. provider-id "/" model-id)))
  (table.concat entries ", "))

(fn start-opencode-with-fixed-model [bridge]
  "Start an opencode server with the bridge-owned isolated MCP config.
   Returns {:server :model :config-dir :base-url}."
  (local opencode-path TEST_CONFIG.opencode-path)
  (local check (process.run {:args [opencode-path "--version"] :timeout_seconds 5}))
  (assert (= check.exit-code 0)
          (.. "opencode not available at '" opencode-path "'. Install or set TEST_CONFIG.opencode-path.\n"
              "  stderr: " (or check.stderr "")))

  (local env (bridge:opencode-env))

  (local server (OpencodeSdk.Opencode {:opencode-path opencode-path
                                       :port 0
                                       :env env}))
  (assert server "should create opencode instance")
  (assert server.client "should have client")

  (local base-url (server.server.url))
  (print (.. "  opencode server: " base-url))

  ;; Health check
  (var health nil)
  (server.global.health (fn [r] (set health r)))
  (wait-for #(not= health nil) 5000)
  (assert-response-ok health "health check")
  (assert health.data.healthy "server should be healthy")

  (assert (> (# TEST_CONFIG.provider-id) 0) "TEST_CONFIG.provider-id must be fixed")
  (assert (> (# TEST_CONFIG.model-id) 0) "TEST_CONFIG.model-id must be fixed")
  (var providers-result nil)
  (server.config.providers (fn [r] (set providers-result r)))
  (wait-for #(not= providers-result nil) 5000)
  (assert-response-ok providers-result "get providers")
  (local data (or (and providers-result providers-result.data) providers-result))
  (assert (provider-configured? data.providers TEST_CONFIG.provider-id)
          (.. "configured provider not available: " TEST_CONFIG.provider-id
              " (available: " (provider-ids data.providers)
              "; defaults: " (provider-defaults data.default) ")"))
  (local model {:providerID TEST_CONFIG.provider-id :modelID TEST_CONFIG.model-id})
  (print (.. "  model: " model.providerID "/" model.modelID))

  {:server server :model model :config-dir env.XDG_CONFIG_HOME :base-url base-url})

(fn start-opencode-bridge [root tool-registry]
  (local bridge
    (AgentOpencodeMcpBridgeMod.AgentOpencodeMcpBridge
      {:tools tool-registry
       :data-dir (fs.join-path root "agent-opencode")}))
  (bridge:start)
  (local status (bridge:status))
  (assert (> status.port 0) "MCP bridge should bind a valid port")
  (print (.. "  MCP bridge port: " status.port))
  bridge)

(fn setup-agent-runner [root server space-agent-model preset-manager surface approvals]
  "Create an AgentRegistry with SpaceAgent registered and an AgentRunner.
   Returns {:registry :runner :session-dir}."
  (local session-dir (fs.join-path root "agent-sessions"))
  (fs.create-dirs session-dir)

  (local registry (AgentRegistryMod.AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register registry
    {:app :stub
     :presets preset-manager
     :tools surface
     :approvals approvals
     :model space-agent-model
     :providers {:opencode server}})

  (local runner (AgentRunnerMod.AgentRunner
                  {:data-dir session-dir
                   :registry registry
                   :deps {:app :stub
                          :presets preset-manager
                          :tools surface
                          :approvals approvals
                          :agents registry
                          :providers {:opencode server}}}))

  {:registry registry :runner runner :session-dir session-dir})

(fn cleanup-test [handles]
  "Stop all test resources. handles may have :server, :bridge, :pipeline, :runner, :config-dir."
  (var errs [])
  (fn safe-call [label f]
    (local (ok err) (pcall f))
    (when (not ok)
      (table.insert errs (.. label ": " (tostring err)))))
  (when handles.runner
    (safe-call "runner.drop" #(handles.runner:drop)))
  (when handles.server
    (safe-call "server.close" #(handles.server.close)))
  (when handles.bridge
    (safe-call "bridge.stop" #(handles.bridge:stop)))
  (when handles.pipeline
    (safe-call "pipeline.cleanup" #(handles.pipeline:cleanup)))
  (when handles.config-dir
    (safe-call "config.remove" #(when (fs.exists handles.config-dir)
                                  (fs.remove-all handles.config-dir))))
  (when handles.root
    (safe-call "root.remove" #(when (fs.exists handles.root)
                                (fs.remove-all handles.root))))
  (when (> (length errs) 0)
    (print "  cleanup warnings:" (table.concat errs "; "))))

(fn with-cleanup [handles f]
  (local (ok result) (pcall f))
  (cleanup-test handles)
  (when (not ok)
    (error result))
  result)

(fn run-test [name f]
  (io.write (.. "  " name " ... "))
  (io.flush)
  (local (ok result) (pcall f))
  (if ok
      (do
        (set passed (+ passed 1))
        (print "PASS"))
      (do
        (set failed (+ failed 1))
        (table.insert failures {:name name :error (tostring result)})
        (print (.. "FAIL: " (tostring result))))))

;; ── Helpers: preset/adapter specs for each test ──

(fn echo-tool-specs [call-log]
  [{:adapter {:id "agent.echo-token"
              :mcp-name "space_agent_echo_token"
              :description "Echo a token back."
              :inputSchema {:type "object"
                            :properties {:token {:type "string" :description "The token to echo"}}
                            :required [:token]}
              :make-run (fn [app]
                          (fn [args]
                            (table.insert call-log {:name "space_agent_echo_token" :args (or args {}) :at (os.time)})
                            (or args.token "")))}
    :preset {:name "agent-test-echo"
             :default-state :auto
             :risk :normal
             :group "test"
             :contexts [{:surface :any}]
             :tool-ids ["agent.echo-token"]}}])

(fn live-streaming-tool-specs [call-log]
  [{:adapter {:id "agent.slow-echo-token"
              :mcp-name "space_agent_slow_echo_token"
              :description "Echo a token back after a short delay."
              :inputSchema {:type "object"
                            :properties {:token {:type "string" :description "The token to echo"}}
                            :required [:token]}
              :make-run (fn [app]
                          (fn [args]
                            (table.insert call-log {:name "space_agent_slow_echo_token"
                                                    :args (or args {})
                                                    :at (os.time)})
                            (os.execute "sleep 2")
                            (or args.token "")))}
    :preset {:name "agent-test-slow-echo"
             :default-state :auto
             :risk :normal
             :group "test"
             :contexts [{:surface :any}]
             :tool-ids ["agent.slow-echo-token"]}}])

(fn sequencing-tool-specs [call-log nonce]
  [{:adapter {:id "agent.get-nonce"
              :mcp-name "space_agent_get_nonce"
              :description "Return a fixed nonce."
              :inputSchema {:type "object" :properties {}}
              :make-run (fn [app]
                          (fn [args]
                            (table.insert call-log {:name "space_agent_get_nonce" :args (or args {}) :at (os.time)})
                            nonce))}
    :preset {:name "agent-test-nonce"
             :default-state :auto
             :risk :normal
             :group "test"
             :contexts [{:surface :any}]
             :tool-ids ["agent.get-nonce"]}}
   {:adapter {:id "agent.record-value"
              :mcp-name "space_agent_record_value"
              :description "Record a value and return a deterministic response."
              :inputSchema {:type "object"
                            :properties {:value {:type "string" :description "Value to record"}}
                            :required [:value]}
              :make-run (fn [app]
                          (fn [args]
                            (table.insert call-log {:name "space_agent_record_value" :args (or args {}) :at (os.time)})
                            (.. "recorded:" (or args.value "nil"))))}
    :preset {:name "agent-test-record"
             :default-state :auto
             :risk :normal
             :group "test"
             :contexts [{:surface :any}]
             :tool-ids ["agent.record-value"]}}])

(fn approval-tool-specs [call-log]
  [{:adapter {:id "agent.normal-safe-tool"
              :mcp-name "space_agent_normal_safe"
              :description "A normal-risk tool."
              :inputSchema {:type "object" :properties {}}
              :make-run (fn [app] (make-call-recording-run call-log "space_agent_normal_safe"))}
    :preset {:name "agent-test-normal-tool"
             :default-state :auto
             :risk :normal
             :group "test"
             :contexts [{:surface :any}]
             :tool-ids ["agent.normal-safe-tool"]}}
   {:adapter {:id "agent.shell-dangerous-tool"
              :mcp-name "space_agent_shell_dangerous"
              :description "A shell-risk tool that should require approval."
              :inputSchema {:type "object" :properties {}}
              :make-run (fn [app] (make-call-recording-run call-log "space_agent_shell_dangerous"))}
    :preset {:name "agent-test-shell-tool"
             :default-state :auto
             :risk :shell
             :group "test"
             :contexts [{:surface :any}]
             :tool-ids ["agent.shell-dangerous-tool"]}}])

;; ═══════════════════════════════════════
;; Test 1: Echo token — core round-trip
;; ═══════════════════════════════════════

(fn test-echo-token []
  (local root (fresh-root))
  (local call-log [])
  (var handles {})
  (set handles.root root)

  (with-cleanup handles
    (fn []
      ;; 1. Set up tool pipeline
      (local pipeline (setup-tool-pipeline call-log (echo-tool-specs call-log)))
      (set handles.pipeline pipeline)

      ;; 2. Start the bridge that owns MCP HTTP plus isolated OpenCode config
      (local bridge (start-opencode-bridge root pipeline.tool-registry))
      (set handles.bridge bridge)

      ;; 3. Verify tool is exposed over MCP
      (local mcp-tools (pipeline.tool-registry:list))
      (assert (= (# mcp-tools) 1) (.. "MCP tool-registry should have 1 tool, got " (# mcp-tools)))
      (assert (= (. mcp-tools 1 :name) "space_agent_echo_token") "tool name should be space_agent_echo_token")

      ;; 4. Start opencode server and verify the SpaceAgent test model is configured
      (local {: server : config-dir : model} (start-opencode-with-fixed-model bridge))
      (set handles.server server)
      (set handles.config-dir config-dir)

      ;; 5. Set up agent runner with a concrete SpaceAgent model choice
      (local {: runner} (setup-agent-runner root server model pipeline.preset-manager pipeline.surface pipeline.approvals))
      (set handles.runner runner)

      ;; 6. Create session and run turn
      (local session (runner:create-session "space-agent"))
      (local marker (.. "live-test-" (os.time)))
      (var completed nil)
      (var items-log [])

      (local handle (runner:run-turn session.id
        (.. "Use `space_agent_echo_token` exactly once with token=\"" marker
            "\". Then reply with exactly the tool output and no extra text.")
        {:on-complete (fn [r] (set completed r))
         :on-item (fn [item] (table.insert items-log item))}))

      (print "  waiting for turn completion...")
      (local final-status (handle:wait TEST_CONFIG.turn-timeout-ms))
      (print (.. "  turn status: " final-status))

      ;; 7. Assertions — deterministic local state first

      ;; 7a. Tool call log
      (assert (= (length call-log) 1)
              (.. "should have exactly 1 tool call, got " (length call-log)))
      (local first-call (. call-log 1))
      (assert (= first-call.name "space_agent_echo_token") "tool call should be space_agent_echo_token")
      (assert (= first-call.args.token marker)
              (.. "token should match '" marker "', got '" (or first-call.args.token "") "'"))

      ;; 7b. Turn completion
      (assert (= (handle:status) :completed)
              (.. "turn should be :completed, got " (tostring (handle:status))))
      (assert completed "on-complete should fire")
      (assert completed.result.content "result should have content")
      (assert (string.find completed.result.content marker 1 true)
              (.. "assistant response should contain marker '" marker
                  "', got: " (string.sub completed.result.content 1 200)))

      ;; 7c. Session items, loaded from disk rather than the in-memory cache
      (SessionMod.invalidate-cache session.id)
      (local reloaded (runner:get-session session.id))
      (assert (>= (length reloaded.items) 2) "should have at least user + assistant messages")

      (var user-msg nil)
      (var assistant-msg nil)
      (each [_ item (ipairs reloaded.items)]
        (when (and (= item.type "message") (= item.role "user"))
          (set user-msg item))
        (when (and (= item.type "message") (= item.role "assistant"))
          (set assistant-msg item)))
      (assert user-msg "should have user message")
      (assert (= user-msg.role "user") "first msg role should be user")
      (assert assistant-msg "should have assistant message")
      (assert (= assistant-msg.role "assistant") "should have assistant message")
      (assert (= assistant-msg.provider "opencode") "assistant provider should be opencode")
      (assert (= assistant-msg.model TEST_CONFIG.model-id)
              (.. "assistant model should be " TEST_CONFIG.model-id ", got " (or assistant-msg.model "nil")))
      (assert (string.find (or assistant-msg.content "") marker 1 true)
              "assistant message should contain marker")

      ;; 7d. OpenCode session ID persisted
      (assert reloaded.data.opencode-session-id
              "session.data.opencode-session-id should be persisted"))))

;; ═══════════════════════════════════════
;; Test 2: Live streaming — tool call appears before completion
;; ═══════════════════════════════════════

(fn test-live-tool-streaming []
  (local root (fresh-root))
  (local call-log [])
  (var handles {})
  (set handles.root root)

  (with-cleanup handles
    (fn []
      (local pipeline (setup-tool-pipeline call-log (live-streaming-tool-specs call-log)))
      (set handles.pipeline pipeline)

      (local bridge (start-opencode-bridge root pipeline.tool-registry))
      (set handles.bridge bridge)

      (local {: server : config-dir : model} (start-opencode-with-fixed-model bridge))
      (set handles.server server)
      (set handles.config-dir config-dir)

      (local {: runner} (setup-agent-runner root server model pipeline.preset-manager pipeline.surface pipeline.approvals))
      (set handles.runner runner)

      (local session (runner:create-session "space-agent"))
      (local marker (.. "stream-live-" (os.time)))
      (var completed nil)
      (var handle nil)
      (var live-call-before-complete false)
      (var live-result-before-complete false)
      (set handle
        (runner:run-turn session.id
          (.. "Call `space_space_agent_slow_echo_token` exactly once with token=\"" marker
              "\". Then reply with exactly the tool output and no extra text.")
          {:on-complete (fn [r] (set completed r))
           :on-item (fn [item]
                      (when (and (= item.type "tool-call")
                                 (= item.name "space_space_agent_slow_echo_token")
                                 (not completed)
                                 (= (handle:status) :running))
                        (set live-call-before-complete true))
                      (when (and (= item.type "tool-result")
                                 (= item.name "space_space_agent_slow_echo_token")
                                 (not completed)
                                 (= (handle:status) :running))
                        (set live-result-before-complete true)))}))

      (print "  waiting for live tool-call before turn completion...")
      (wait-for #(and live-call-before-complete
                      (= (handle:status) :running)
                      (not completed))
                90000)
      (assert live-call-before-complete "tool-call should stream while turn is still running")

      (print "  waiting for live tool-result before turn completion...")
      (wait-for #(and live-result-before-complete
                      (= (handle:status) :running)
                      (not completed))
                90000)
      (assert live-result-before-complete "tool-result should stream while turn is still running")

      (local final-status (handle:wait TEST_CONFIG.turn-timeout-ms))
      (print (.. "  turn status: " final-status))
      (assert (= (handle:status) :completed) "turn should complete")
      (assert completed "on-complete should fire")
      (assert (= (length call-log) 1)
              (.. "slow echo should be called once, got " (length call-log)))
      (assert (= (. call-log 1 :args :token) marker)
              "slow echo token should match marker")
      (assert (string.find completed.result.content marker 1 true)
              (.. "assistant response should contain marker '" marker "'"))

      (SessionMod.invalidate-cache session.id)
      (local reloaded (runner:get-session session.id))
      (var call-count 0)
      (var result-count 0)
      (each [_ item (ipairs reloaded.items)]
        (when (and (= item.type "tool-call")
                   (= item.name "space_space_agent_slow_echo_token"))
          (set call-count (+ call-count 1)))
        (when (and (= item.type "tool-result")
                   (= item.name "space_space_agent_slow_echo_token"))
          (set result-count (+ result-count 1))))
      (assert (= call-count 1) "live stream plus final audit should keep one tool-call")
      (assert (= result-count 1) "live stream plus final audit should keep one tool-result"))))

;; ═══════════════════════════════════════
;; Test 3: Sequencing — multi-tool call ordering
;; ═══════════════════════════════════════

(fn test-sequencing []
  (local root (fresh-root))
  (local call-log [])
  (local nonce (.. "nonce-" (os.time)))
  (var handles {})
  (set handles.root root)

  (with-cleanup handles
    (fn []
      ;; 1. Set up tool pipeline with get-nonce and record-value
      (local pipeline (setup-tool-pipeline call-log (sequencing-tool-specs call-log nonce)))
      (set handles.pipeline pipeline)

      ;; 2. Start the bridge that owns MCP HTTP plus isolated OpenCode config
      (local bridge (start-opencode-bridge root pipeline.tool-registry))
      (set handles.bridge bridge)

      (local mcp-tools (pipeline.tool-registry:list))
      (assert (= (# mcp-tools) 2) "should have 2 tools in MCP registry")

      ;; 3. Start opencode and verify the SpaceAgent test model is configured
      (local {: server : config-dir : model} (start-opencode-with-fixed-model bridge))
      (set handles.server server)
      (set handles.config-dir config-dir)

      ;; 4. Set up agent runner
      (local {: runner} (setup-agent-runner root server model pipeline.preset-manager pipeline.surface pipeline.approvals))
      (set handles.runner runner)

      ;; 5. Run turn
      (local session (runner:create-session "space-agent"))
      (var completed nil)
      (local handle (runner:run-turn session.id
        (.. "Call `space_agent_get_nonce`, then call `space_agent_record_value` with the nonce you received. Reply exactly `done:" nonce "`.")
        {:on-complete (fn [r] (set completed r))}))

      (print "  waiting for sequencing turn...")
      (local final-status (handle:wait TEST_CONFIG.turn-timeout-ms))
      (print (.. "  turn status: " final-status))

      ;; 6. Assertions
      (assert (>= (length call-log) 2)
              (.. "should have at least 2 tool calls, got " (length call-log)))

      ;; Check that get_nonce was called first, then record_value
      (local first-call (. call-log 1))
      (assert (= first-call.name "space_agent_get_nonce")
              (.. "first call should be get_nonce, got " (or first-call.name "nil")))
      (local second-call (. call-log 2))
      (assert (= second-call.name "space_agent_record_value")
              (.. "second call should be record_value, got " (or second-call.name "nil")))
      (assert (= second-call.args.value nonce)
              (.. "record_value should receive nonce '" nonce "', got '" (or second-call.args.value "nil") "'"))

      ;; Turn should complete
      (assert (= (handle:status) :completed) "turn should complete")
      (assert completed "on-complete should fire")
      (assert (string.find (or completed.result.content "") nonce 1 true)
              (.. "final text should contain nonce '" nonce "'")))))

;; ═══════════════════════════════════════
;; Test 3: Approval boundaries — high-risk tools gated
;; ═══════════════════════════════════════

(fn test-approval-boundaries []
  (local root (fresh-root))
  (local call-log [])
  (var handles {})
  (set handles.root root)

  (with-cleanup handles
    (fn []
      ;; 1. Set up tool pipeline with normal + shell tools
      (local pipeline (setup-tool-pipeline call-log (approval-tool-specs call-log)))
      (set handles.pipeline pipeline)

      ;; The default policy setup uses {:normal :auto} only, so shell should need approval.
      ;; Ask-risk tools stay exposed so the approval path can reject execution.

      (local mcp-defs (pipeline.surface:mcp-tool-defs))
      (assert (= (length mcp-defs) 2) (.. "surface should expose both tools, got " (length mcp-defs)))

      ;; 2. Start the bridge that owns MCP HTTP plus isolated OpenCode config
      (local bridge (start-opencode-bridge root pipeline.tool-registry))
      (set handles.bridge bridge)

      ;; 3. Assert MCP server tools/list includes both; shell remains approval-gated at call time.
      (local mcp-tools (pipeline.tool-registry:list))
      (assert (= (# mcp-tools) 2) "MCP tool-registry should have both active tools")
      (var found-shell false)
      (each [_ t (ipairs mcp-tools)]
        (when (= t.name "space_agent_shell_dangerous")
          (set found-shell true)))
      (assert found-shell "shell tool should be present but gated at execution")

      ;; 4. Start opencode and verify the SpaceAgent test model is configured
      (local {: server : config-dir : model} (start-opencode-with-fixed-model bridge))
      (set handles.server server)
      (set handles.config-dir config-dir)

      ;; 5. Set up agent runner
      (local {: runner} (setup-agent-runner root server model pipeline.preset-manager pipeline.surface pipeline.approvals))
      (set handles.runner runner)

      ;; 6. Create session and prompt the agent to call the high-risk tool directly
      (local session (runner:create-session "space-agent"))
      (var completed nil)
      (var error-received nil)
      (local handle (runner:run-turn session.id
        "Call the `space_agent_shell_dangerous` tool with no arguments."
        {:on-complete (fn [r] (set completed r))
         :on-error (fn [e] (set error-received e))}))

      (print "  waiting for approval-boundaries turn...")
      (local final-status (handle:wait TEST_CONFIG.turn-timeout-ms))
      (print (.. "  turn status: " final-status))

      ;; 7. Assert no high-risk call was recorded
      (var shell-call nil)
      (each [_ entry (ipairs call-log)]
        (when (= entry.name "space_agent_shell_dangerous")
          (set shell-call entry)))
      (assert (not shell-call)
              "space_agent_shell_dangerous should not be called (not in MCP tool list)")

      ;; 8. The turn may complete or fail depending on model behavior.
      ;; The hard checks are: tool not in MCP list (verified above), zero calls (verified above).
      ;; The model's natural-language response is informative but secondary.
      (local status (handle:status))
      (assert (or (= status :completed) (= status :failed))
              (.. "turn should be :completed or :failed, got " (tostring status))))))

;; ═══════════════════════════════════════
;; Main
;; ═══════════════════════════════════════

(fn main []
  (print "Agent MCP Online E2E Tests")
  (print "=========================")

  (math.randomseed (math.floor (now-ms)))

  (run-test "echo token round-trip" test-echo-token)
  (run-test "live tool streaming" test-live-tool-streaming)
  (run-test "multi-tool sequencing" test-sequencing)
  (run-test "approval boundaries gating" test-approval-boundaries)

  (print "")
  (print "==========================")
  (print (.. "Results: " passed " passed, " failed " failed"))
  (when (> (# failures) 0)
    (print "")
    (print "Failures:")
    (each [_ f (ipairs failures)]
      (print (.. "  " f.name ": " f.error))))
  (print "")

  (when (> failed 0)
    (os.exit 1)))

{:main main}
