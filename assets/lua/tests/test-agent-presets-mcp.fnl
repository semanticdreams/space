;; Agent Presets MCP sync tests — PresetMcpSync ownership, register/unregister, collision detection.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-presets-mcp:main

(local tests [])
(local ToolRegistry (require :mcp/tool-registry))
(local {: PresetRegistry} (require :llm/presets/registry))
(local {: ToolAdapterRegistry} (require :llm/presets/tool-adapters))
(local {: PresetManager} (require :llm/presets/init))
(local {: PresetMcpSync} (require :llm/presets/mcp-sync))

(fn make-dummy-app []
  {})

(fn setup-mgr []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (values reg adapters mgr))

(fn register-preset-and-adapter [mgr adapters preset-name tool-id mcp-name]
  (adapters:register {:id tool-id
                       :mcp-name mcp-name
                       :description (.. "Adapter for " tool-id)
                       :inputSchema {:type "object" :properties {}}
                       :make-run (fn [_app] (fn [] (.. "ran " tool-id)))})
  (mgr:register {:name preset-name
                  :default-state :auto
                  :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids [tool-id]}))

;; ── Sync: registers resolved preset tools ──

(fn test-sync-registers []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_tool_a")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (sync:start)

  (local tools (tool-reg:list))
  (assert (= (# tools) 1) "should have 1 tool registered")
  (assert (= (. tools 1 :name) "space_tool_a") "tool name should match")
  (sync:stop))
(table.insert tests {:name "agent-presets-mcp: registers resolved preset tools" :fn test-sync-registers})

;; ── Sync: unregisters previously managed tools ──

(fn test-sync-unregisters []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_tool_a")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (sync:start)
  (assert (= (# (tool-reg:list)) 1) "should have 1 tool before unregister")

  (mgr:unregister "preset-a")
  (assert (= (# (tool-reg:list)) 0) "should have 0 tools after preset unregistered")
  (sync:stop))
(table.insert tests {:name "agent-presets-mcp: unregisters previously managed tools"
                     :fn test-sync-unregisters})

;; ── Sync: preserves unrelated tools ──

(fn test-sync-preserves-unrelated []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_tool_a")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (tool-reg:register {:name "space_unrelated" :description "An unrelated tool"
                       :inputSchema {:type "object" :properties {}}
                       :run (fn [] "unrelated")})

  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (sync:start)

  (local tools (tool-reg:list))
  (assert (= (# tools) 2) "should have 2 tools: managed + unrelated")

  (mgr:unregister "preset-a")
  (local tools-after (tool-reg:list))
  (assert (= (# tools-after) 1) "should have 1 tool left (unrelated)")
  (assert (= (. tools-after 1 :name) "space_unrelated") "remaining should be unrelated")

  (sync:stop))
(table.insert tests {:name "agent-presets-mcp: preserves unrelated tools"
                     :fn test-sync-preserves-unrelated})

;; ── Sync: re-registers when source tool ID changes ──

(fn test-sync-re-register-on-source-change []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.old" "space_mytool")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (sync:start)

  (local tools1 (tool-reg:list))
  (assert (= (# tools1) 1) "should have 1 tool")
  (assert (= (. tools1 1 :name) "space_mytool"))

  (mgr:unregister "preset-a")
  (assert (= (# (tool-reg:list)) 0) "should be empty after unregister")

  (register-preset-and-adapter mgr adapters "preset-b" "tool.new" "space_mytool")

  (local tools2 (tool-reg:list))
  (assert (= (# tools2) 1) "should be re-registered")
  (assert (= (. tools2 1 :name) "space_mytool") "same MCP name, different source")

  (sync:stop))
(table.insert tests {:name "agent-presets-mcp: re-registers when source tool ID changes"
                     :fn test-sync-re-register-on-source-change})

;; ── Sync: fails on unmanaged name collision ──

(fn test-sync-unmanaged-collision []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_clash")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (tool-reg:register {:name "space_clash" :description "Manual tool with same name"
                       :inputSchema {:type "object" :properties {}}
                       :run (fn [] "manual")})

  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (local (ok err) (pcall sync.start sync))
  (assert (not ok) "should fail when managed tool collides with unmanaged name")
  (assert (string.find (tostring err) "space_clash") "error should mention colliding name"))

(table.insert tests {:name "agent-presets-mcp: fails on unmanaged name collision"
                     :fn test-sync-unmanaged-collision})

;; ── Sync: failed start rolls back lifecycle state ──

(fn test-sync-start-failure-rolls-back []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_clash")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (tool-reg:register {:name "space_clash" :description "Manual tool with same name"
                       :inputSchema {:type "object" :properties {}}
                       :run (fn [] "manual")})

  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (local (ok _err) (pcall sync.start sync))
  (assert (not ok) "start should fail on collision")
  (local s (sync:status))
  (assert (not s.started?) "failed start should not leave sync marked started")
  (assert (= s.managed-tool-count 0) "failed start should not claim managed tools")
  (local before-count (# (tool-reg:list)))
  (mgr:set-context {:surface :canvas :mode "drawing" :canvas-visible? true})
  (assert (= (# (tool-reg:list)) before-count)
          "failed start should remove manager change listener"))

(table.insert tests {:name "agent-presets-mcp: failed start rolls back lifecycle state"
                     :fn test-sync-start-failure-rolls-back})

;; ── Sync: emits tool-registry on-change ──

(fn test-sync-emits-on-change []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_tool_a")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (var change-count 0)
  (tool-reg:add-on-change (fn [] (set change-count (+ change-count 1))))

  (sync:start)
  ;; start calls sync which registers; at least 1 change
  (assert (>= change-count 1) "should emit at least 1 change on start/sync")

  (mgr:set-override "preset-a" :off)
  ;; preset-a unregistered from managed, so another change
  (assert (>= change-count 2) "should emit change on manager change")

  (sync:stop))
(table.insert tests {:name "agent-presets-mcp: emits tool-registry on-change"
                     :fn test-sync-emits-on-change})

;; ── Sync: stop removes all managed tools ──

(fn test-sync-stop-removes-all []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_tool_a")
  (register-preset-and-adapter mgr adapters "preset-b" "tool.b" "space_tool_b")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (tool-reg:register {:name "space_unrelated" :description "Unrelated"
                       :inputSchema {:type "object" :properties {}}
                       :run (fn [] "unrelated")})

  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (sync:start)
  (assert (= (# (tool-reg:list)) 3) "should have 3 tools before stop")
  (sync:stop)
  (local tools-after (tool-reg:list))
  (assert (= (# tools-after) 1) "should preserve unrelated tool after stop")
  (assert (= (. tools-after 1 :name) "space_unrelated") "remaining should be unrelated"))
(table.insert tests {:name "agent-presets-mcp: stop removes all managed tools"
                     :fn test-sync-stop-removes-all})

;; ── Sync: status reports diagnostics ──

(fn test-sync-status []
  (local (reg adapters mgr) (setup-mgr))
  (register-preset-and-adapter mgr adapters "preset-a" "tool.a" "space_tool_a")

  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (PresetMcpSync {:manager mgr :tool-registry tool-reg :owner "test"}))
  (sync:start)

  (local s (sync:status))
  (assert s.started? "should be started")
  (assert (= s.owner "test") "owner should match")
  (assert (= s.managed-tool-count 1) "should have 1 managed tool")

  (sync:stop)
  (local s2 (sync:status))
  (assert (not s2.started?))
  (assert (= s2.managed-tool-count 0)))
(table.insert tests {:name "agent-presets-mcp: status reports diagnostics" :fn test-sync-status})

;; ── Main ──

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "agent-presets-mcp" :tests tests}))

{:tests tests
 :main main}
