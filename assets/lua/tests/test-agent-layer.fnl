;; Agent layer tests — session CRUD, turn lifecycle, approvals, tool surface, prompt utils, runner, SpaceAgent.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-layer:main

(local tests [])

;; ── Test helpers ──

(local fs (require :fs))
(local json (require :json))
(local Uuid (require :uuid))

(fn temp-dir []
  (local dir (fs.join-path "/tmp/space/tests/agent-layer" (Uuid.v4)))
  (when (not (fs.exists dir))
    (fs.create-dirs dir))
  dir)

(fn clean-dir [dir]
  (when (and dir (fs.exists dir))
    (fs.remove-all dir)))

(fn mock-tool-surface [fragments]
  {:prompt-fragments (fn [self] (or fragments []))})

;; ═══════════════════════════════════════
;; Session CRUD tests
;; ═══════════════════════════════════════

(fn test-session-create []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (assert session "session should be created")
  (assert (= session.agent-id "test-agent") "session should have agent-id")
  (assert (= session.status :idle) "session should start idle")
  (assert (= (type session.id) "string") "session should have string id")
  (assert (= (type session.items) "table") "session should have items table")
  (assert (= (type session.data) "table") "session should have data table")
  (assert (= (type session.created-at) "number") "session should have created-at")
  (assert (= (type session.updated-at) "number") "session should have updated-at")
  ;; Verify persisted to disk
  (local path (fs.join-path dir (.. session.id ".json")))
  (assert (fs.exists path) "session should be persisted to disk")
  (clean-dir dir))

(fn test-session-load-and-cache []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local created (SessionMod.create-session "test-agent" dir))
  ;; Load from disk
  (local loaded (SessionMod.load-session created.id dir))
  (assert loaded "session should be loadable")
  (assert (= loaded.id created.id) "loaded session should have same id")
  (assert (= loaded.agent-id "test-agent") "loaded session should have same agent-id")
  ;; Should be cached
  (SessionMod.invalidate-cache created.id)
  (local reloaded (SessionMod.load-session created.id dir))
  (assert reloaded "session should be reloadable after cache invalidation")
  (assert (= reloaded.id created.id) "reloaded session should have same id")
  (clean-dir dir))

(fn test-session-load-missing []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local result (SessionMod.load-session "nonexistent-id" dir))
  (assert (= result nil) "loading nonexistent session should return nil")
  (clean-dir dir))

(fn test-session-load-corrupt-errors []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session-id "agt-ses-corrupt")
  (fs.write-file (fs.join-path dir (.. session-id ".json")) "{")
  (local (ok err) (pcall SessionMod.load-session session-id dir))
  (assert (not ok) "corrupt session load should error")
  (assert (string.match (tostring err) "failed to parse agent session") "error should mention parse failure")
  (clean-dir dir))

(fn test-session-save-updates-timestamp []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (local original-updated-at session.updated-at)
  (os.execute "sleep 1")  ;; ensure timestamp changes
  (SessionMod.update-session session {:status :busy})
  (SessionMod.save-session session dir)
  (assert (> (or session.updated-at 0) (or original-updated-at 0))
          "updated-at should be newer after save")
  (clean-dir dir))

(fn test-session-delete []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (local path (fs.join-path dir (.. session.id ".json")))
  (assert (fs.exists path) "file should exist before delete")
  (SessionMod.delete-session session.id dir)
  (assert (not (fs.exists path)) "file should not exist after delete")
  ;; Loading should return nil after delete
  (local reloaded (SessionMod.load-session session.id dir))
  (assert (= reloaded nil) "loading deleted session should return nil")
  (clean-dir dir))

(fn test-session-list []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local s1 (SessionMod.create-session "agent-a" dir))
  (local s2 (SessionMod.create-session "agent-b" dir))
  (local items (SessionMod.list-sessions dir))
  (assert (>= (length items) 2) "should list at least 2 sessions")
  (var found-s1 false)
  (var found-s2 false)
  (each [_ entry (ipairs items)]
    (when (= entry.id s1.id) (set found-s1 true))
    (when (= entry.id s2.id) (set found-s2 true)))
  (assert found-s1 "should find session 1")
  (assert found-s2 "should find session 2")
  (clean-dir dir))

(fn test-session-list-empty-dir []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (clean-dir dir)
  (local items (SessionMod.list-sessions dir))
  (assert (= (type items) "table") "should return table")
  (assert (= (length items) 0) "should return empty list")
  (clean-dir dir))

(fn test-session-list-corrupt-errors []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (fs.write-file (fs.join-path dir "agt-ses-corrupt.json") "{")
  (local (ok err) (pcall SessionMod.list-sessions dir))
  (assert (not ok) "corrupt session list entry should error")
  (assert (string.match (tostring err) "failed to parse agent session list entry") "error should mention list parse failure")
  (clean-dir dir))

(fn test-session-append-item []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (SessionMod.append-item session {:id "itm-1" :type "message" :role "user" :content "hello"})
  (assert (= (length session.items) 1) "should have 1 item")
  (local item1 (. session.items 1))
  (assert (= item1.id "itm-1") "item should have correct id")
  (assert (= item1.type "message") "item should have correct type")
  ;; Persist and reload
  (SessionMod.save-session session dir)
  (SessionMod.invalidate-cache session.id)
  (local loaded (SessionMod.load-session session.id dir))
  (assert (= (length loaded.items) 1) "reloaded session should have 1 item")
  (local loaded-item1 (. loaded.items 1))
  (assert (= loaded-item1.id "itm-1") "reloaded item should have correct id")
  (clean-dir dir))

(fn test-session-append-multiple-item-types []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (SessionMod.append-item session {:id "itm-1" :type "message" :role "user" :content "draw"})
  (SessionMod.append-item session {:id "itm-2" :type "tool-call" :name "draw_shape" :arguments "{}" :call-id "call-1" :parent-id "itm-1"})
  (SessionMod.append-item session {:id "itm-3" :type "tool-result" :name "draw_shape" :output "ok" :call-id "call-1" :parent-id "itm-2"})
  (SessionMod.append-item session {:id "itm-4" :type "message" :role "assistant" :content "done" :parent-id "itm-3" :provider "opencode" :model "claude" :usage {:input-tokens 10 :output-tokens 20}})
  (SessionMod.append-item session {:id "itm-5" :type "event" :event-type "turn-started"})
  (SessionMod.append-item session {:id "itm-6" :type "error" :error "something went wrong"})
  (assert (= (length session.items) 6) "should have 6 items")
  ;; Check types preserved
  (local si1 (. session.items 1))
  (local si2 (. session.items 2))
  (local si3 (. session.items 3))
  (local si4 (. session.items 4))
  (local si5 (. session.items 5))
  (local si6 (. session.items 6))
  (assert (= si1.type "message"))
  (assert (= si2.type "tool-call"))
  (assert (= si2.call-id "call-1"))
  (assert (= si3.type "tool-result"))
  (assert (= si3.call-id "call-1"))
  (assert (= si4.type "message"))
  (assert (= si4.provider "opencode"))
  (assert (= si4.usage.input-tokens 10))
  (assert (= si5.type "event"))
  (assert (= si6.type "error"))
  (clean-dir dir))

;; ═══════════════════════════════════════
;; Turn lifecycle tests
;; ═══════════════════════════════════════

(fn test-turn-pair-creation []
  (local TurnMod (require :llm/agent/turn))
  (local (handle controller) (TurnMod.TurnPair "ses-1" {}))
  (assert handle "handle should be created")
  (assert controller "controller should be created")
  (assert (= (type handle.id) "string") "handle should have string id")
  (assert (= handle.session-id "ses-1") "handle should have session-id")
  (assert (= (handle:status) :created) "initial status should be :created")
  (assert (not (handle:running?)) "should not be running initially"))

(fn test-turn-start-and-complete []
  (local TurnMod (require :llm/agent/turn))
  (var completed nil)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-complete (fn [result] (set completed result))}))
  (handle:start)
  (assert (= (handle:status) :running) "status should be :running after start")
  (assert (handle:running?) "should be running")
  (controller:finish {:content "done"})
  (assert (= (handle:status) :completed) "status should be :completed after finish")
  (assert (not (handle:running?)) "should not be running after completion")
  (assert completed "on-complete should have been called")
  (assert (= completed.result.content "done") "result should be passed to callback"))

(fn test-turn-fail []
  (local TurnMod (require :llm/agent/turn))
  (var error-received nil)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [err] (set error-received err))}))
  (handle:start)
  (controller:fail "something broke")
  (assert (= (handle:status) :failed) "status should be :failed")
  (assert (= (handle:error) "something broke") "error should be stored")
  (assert error-received "on-error should have been called")
  (assert (= error-received.error "something broke") "error should match"))

(fn test-turn-cancel []
  (local TurnMod (require :llm/agent/turn))
  (var cancelled false)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [err] (set cancelled true))}))
  (handle:start)
  (local result (handle:cancel))
  (assert result "cancel should return true")
  (assert (= (handle:status) :cancelled) "status should be :cancelled")
  (assert cancelled "on-error should have been called on cancel"))

(fn test-turn-cancel-invokes-registered-fn []
  (local TurnMod (require :llm/agent/turn))
  (var cancel-called false)
  (local (handle controller) (TurnMod.TurnPair "ses-1" {}))
  (controller:set-cancel (fn [] (set cancel-called true)))
  (handle:start)
  (handle:cancel)
  (assert cancel-called "registered cancel function should be invoked"))

(fn test-turn-cancel-surfaces-cancel-fn-error []
  (local TurnMod (require :llm/agent/turn))
  (var error-received nil)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [err] (set error-received err))}))
  (controller:set-cancel (fn [] (error "abort failed")))
  (handle:start)
  (handle:cancel)
  (assert (= (handle:status) :cancelled) "turn should still be cancelled")
  (assert (string.match (handle:error) "cancel hook failed")
          "handle error should mention cancel hook failure")
  (assert (string.match error-received.error "abort failed")
          "on-error should surface cancel hook failure"))

(fn test-turn-cannot-finish-twice []
  (local TurnMod (require :llm/agent/turn))
  (var completion-count 0)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-complete (fn [r] (set completion-count (+ completion-count 1)))}))
  (handle:start)
  (controller:finish {:content "first"})
  (controller:finish {:content "second"})
  (assert (= completion-count 1) "on-complete should only fire once"))

(fn test-turn-fail-after-complete-noop []
  (local TurnMod (require :llm/agent/turn))
  (var error-count 0)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [r] (set error-count (+ error-count 1)))}))
  (handle:start)
  (controller:finish {:content "done"})
  (controller:fail "late error")
  (assert (= error-count 0) "fail after finish should not fire on-error"))

(fn test-turn-cancelled?-flag []
  (local TurnMod (require :llm/agent/turn))
  (local (handle controller) (TurnMod.TurnPair "ses-1" {}))
  (handle:start)
  (assert (not (controller:cancelled?)) "should not be cancelled initially")
  (handle:cancel)
  (assert (controller:cancelled?) "should be cancelled after cancel"))

(fn test-turn-append-item-callback []
  (local TurnMod (require :llm/agent/turn))
  (var items [])
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-item (fn [item] (table.insert items item))}))
  (handle:start)
  (controller:append-item {:id "itm-1" :type "message" :role "user" :content "hi"})
  (assert (= (length items) 1) "on-item should have been called")
  (local captured (. items 1))
  (assert (= captured.id "itm-1") "item should be passed through"))

;; ═══════════════════════════════════════
;; Registry tests
;; ═══════════════════════════════════════

(fn test-registry-register-and-get []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (reg:register "test-agent" (fn [deps] {:id "test-agent" :name "Test" :run (fn [] nil)}))
  (local agent (reg:get "test-agent"))
  (assert agent "agent should be retrievable")
  (assert (= agent.id "test-agent") "agent should have correct id"))

(fn test-registry-lazy-construction []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (var factory-called false)
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "lazy-agent" (fn [deps] (set factory-called true) {:id "lazy-agent" :run (fn [] nil)}))
  (assert (not factory-called) "factory should not be called on register")
  (reg:get "lazy-agent")
  (assert factory-called "factory should be called on first get"))

(fn test-registry-get-unknown []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {}}))
  (local result (reg:get "nonexistent"))
  (assert (= result nil) "getting unknown agent should return nil"))

(fn test-registry-list []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "alpha" (fn [d] {:id "alpha" :name "Alpha"}))
  (reg:register "beta" (fn [d] {:id "beta" :name "Beta"}))
  (local items (reg:list))
  (assert (= (length items) 2) "should list 2 agents")
  (var found-alpha false)
  (var found-beta false)
  (each [_ item (ipairs items)]
    (when (= item.id "alpha") (set found-alpha true))
    (when (= item.id "beta") (set found-beta true)))
  (assert found-alpha "should find alpha")
  (assert found-beta "should find beta"))

(fn test-registry-unregister []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "temp" (fn [d] {:id "temp"}))
  (assert (reg:get "temp") "should be registered")
  (reg:unregister "temp")
  (assert (= (reg:get "temp") nil) "should be nil after unregister"))

(fn test-registry-reregister-invalidates-cache []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (var call-count 0)
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "agent-r" (fn [d] (set call-count (+ call-count 1)) {:id "agent-r" :version 1}))
  (local v1 (reg:get "agent-r"))
  (assert (= v1.version 1))
  (assert (= call-count 1))
  ;; Re-register with new factory
  (reg:register "agent-r" (fn [d] (set call-count (+ call-count 1)) {:id "agent-r" :version 2}))
  (local v2 (reg:get "agent-r"))
  (assert (= v2.version 2))
  (assert (= call-count 2) "factory should be called again after re-register"))

;; ═══════════════════════════════════════
;; Approvals tests
;; ═══════════════════════════════════════

(fn test-approvals-normal-always-approved []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (assert (= (approvals:check-risk :normal) :approved) "normal risk should be auto-approved"))

(fn test-approvals-auto-policy []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {:filesystem-read :auto}}))
  (assert (= (approvals:check-risk :filesystem-read) :approved) "auto policy should approve"))

(fn test-approvals-deny-policy []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {:shell :deny}}))
  (assert (= (approvals:check-risk :shell) :denied) "deny policy should deny"))

(fn test-approvals-ask-default []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (assert (= (approvals:check-risk :filesystem-write) :needs-approval)
          "high-risk without policy should need approval"))

(fn test-approvals-request-risk-auto []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var approved-result nil)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (approvals:request-risk :normal "testing"
    {:on-approved (fn [r] (set approved-result r))
     :on-denied (fn [r] (set approved-result :denied))})
  (assert approved-result "callback should be called")
  (assert (= approved-result.risk :normal) "should report risk"))

(fn test-approvals-request-risk-needs-approval []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var denied-result nil)
  (local approvals (AgentApprovals {:policy {:destructive :ask}}))
  (local result (approvals:request-risk :destructive "delete world"
    {:on-approved (fn [r] nil)
     :on-denied (fn [r] (set denied-result r))}))
  (assert (= result false) "should return false when needs approval")
  (assert denied-result "on-denied should be called")
  (assert denied-result.needs-approval "should indicate needs-approval"))

(fn test-approvals-unknown-risk-asserts []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (local (ok _err) (pcall approvals.check-risk approvals :made-up-risk))
  (assert (not ok) "unknown risk should assert"))

(fn test-approvals-record-decision []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (approvals:record-decision {:risk :normal :reason "test" :decision :approved})
  (approvals:record-decision {:risk :shell :reason "test2" :decision :denied})
  ;; No direct access to decisions list, but no error means success
  (assert true))

;; ═══════════════════════════════════════
;; Tool surface tests
;; ═══════════════════════════════════════

(fn test-tool-surface-active-presets []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local mock-presets
    {:get-active-presets (fn [] [{:name "drawing-shape-tools" :reason "auto"}])})
  (local mock-mcp-tools {})
  (local mock-approvals {:check-risk (fn [self risk context] :approved)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (local presets (surface:active-presets))
  (assert (= (length presets) 1) "should have 1 active preset")
  (local first-preset (. presets 1))
  (assert (= first-preset.name "drawing-shape-tools") "should have correct name"))

(fn test-tool-surface-openai-tools []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local input-schema {:type "object" :properties {:x {:type "number"}}})
  (local mock-def {:name "space_test_tool"
                   :description "A test tool"
                   :inputSchema input-schema
                   :managed-source "tool-test"})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "test-preset"
                                  :reason :context
                                  :risk :normal
                                  :tool-ids ["tool-test"]}])
     :get-prompt-fragments (fn [] [])})
  (local mock-mcp-tools {})
  (local mock-approvals {:check-risk (fn [self risk context] :approved)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (local tools (surface:openai-tools))
  (assert (= (length tools) 1) "should have 1 tool")
  (local first-tool (. tools 1))
  (assert (= first-tool.type "function") "should be function type")
  (assert (= first-tool.name "space_test_tool") "should have correct name")
  (assert (= first-tool.description "A test tool") "should have correct description")
  (assert first-tool.parameters "should have parameters"))

(fn test-tool-surface-mcp-defs []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local mock-def {:name "space_test" :description "test" :inputSchema {} :run (fn []) :managed-source "tool-test"})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "test-preset" :reason :context :risk :normal :tool-ids ["tool-test"]}])
     :get-prompt-fragments (fn [] [])})
  (local mock-mcp-tools {})
  (local mock-approvals {:check-risk (fn [self risk context] :approved)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (local defs (surface:mcp-tool-defs))
  (assert (= (length defs) 1) "should have 1 def")
  (local first-def (. defs 1))
  (assert (= first-def.name "space_test") "should have correct name"))

(fn test-tool-surface-call-delegates-to-mcp []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (var call-log nil)
  (local mock-def {:name "space_draw_circle"
                   :description "draw"
                   :inputSchema {}
                   :managed-source "draw-circle"})
  (local mock-mcp-tools
    {:call (fn [self name args]
             (set call-log {:name name :args args})
             {:content [{:type "text" :text "ok"}] :isError false})})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "drawing" :reason :context :risk :normal :tool-ids ["draw-circle"]}])
     :get-prompt-fragments (fn [] [])})
  (local mock-approvals {:check-risk (fn [self risk context] :approved)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (surface:call "space_draw_circle" {:radius 10})
  (assert call-log "call should have been dispatched")
  (assert (= call-log.name "space_draw_circle") "should call correct tool")
  (assert (= call-log.args.radius 10) "should pass args"))

(fn test-tool-surface-denies-unapproved-risk []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local mock-def {:name "space_shell"
                   :description "shell"
                   :inputSchema {}
                   :managed-source "shell-tool"})
  (var called false)
  (local mock-mcp-tools
    {:call (fn [self name args]
             (set called true)
             {:content []})})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "shell-preset" :reason :override :risk :shell :tool-ids ["shell-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local mock-approvals {:check-risk (fn [self risk context] :needs-approval)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (assert (= (length (surface:mcp-tool-defs)) 0) "unapproved high-risk tool should not be exposed")
  (local (ok err) (pcall (fn [] (surface:call "space_shell" {}))))
  (assert (not ok) "unapproved high-risk tool call should error")
  (assert (not called) "unapproved high-risk tool should not execute"))

;; ═══════════════════════════════════════
;; Agent MCP sync tests
;; ═══════════════════════════════════════

(fn test-agent-mcp-sync-registers-approved-surface-tools []
  (local {: AgentMcpSync} (require :llm/agent/mcp-sync))
  (local ToolRegistry (require :mcp/tool-registry))
  (var defs [{:name "space_agent_echo"
              :description "Echo test tool"
              :inputSchema {:type "object" :properties {}}
              :managed-source "agent.echo"
              :run (fn [] "ok")}])
  (local surface {:mcp-tool-defs (fn [self] defs)})
  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (AgentMcpSync {:surface surface
                             :tool-registry tool-reg
                             :owner "test-agent"}))
  (sync:start)
  (local tools (tool-reg:list))
  (assert (= (# tools) 1) "approved surface tool should be registered")
  (assert (= (. tools 1 :name) "space_agent_echo") "registered tool name should match")
  (set defs [])
  (sync:sync)
  (assert (= (# (tool-reg:list)) 0) "removed surface tool should be unregistered")
  (sync:stop))

(fn test-agent-mcp-sync-does-not_bypass_surface_gating []
  (local {: AgentMcpSync} (require :llm/agent/mcp-sync))
  (local ToolRegistry (require :mcp/tool-registry))
  (local surface {:mcp-tool-defs (fn [self] [])})
  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (AgentMcpSync {:surface surface
                             :tool-registry tool-reg
                             :owner "test-agent"}))
  (sync:start)
  (assert (= (# (tool-reg:list)) 0) "agent MCP sync should expose only surface-approved tools")
  (sync:stop))

(fn test-opencode-mcp-bridge-starts-and-writes-config []
  (local {: AgentOpencodeMcpBridge} (require :llm/agent/opencode-mcp-bridge))
  (local ToolRegistry (require :mcp/tool-registry))
  (local dir (temp-dir))
  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local bridge (AgentOpencodeMcpBridge {:tools tool-reg :data-dir dir}))
  (bridge:start)
  (local status (bridge:status))
  (assert status.started? "bridge should report started")
  (assert (> status.port 0) "bridge should bind a port")
  (local env (bridge:opencode-env))
  (assert (= env.XDG_CONFIG_HOME status.config-root) "OpenCode env should point to bridge config root")
  (local config (json.loads (fs.read-file status.config-path)))
  (assert (= config.mcp.space.type "remote") "config should create remote MCP server")
  (assert (= config.mcp.space.url status.url) "config URL should match bridge URL")
  (assert (= config.mcp.space.enabled true) "config should enable MCP server")
  (bridge:stop)
  (clean-dir dir))

;; ═══════════════════════════════════════
;; Prompt utilities tests
;; ═══════════════════════════════════════

(fn test-prompt-assemble-blocks []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.assemble-blocks
    [{:name "Instructions" :content "Be helpful."}
     {:name "Context" :content "No active context."}]))
  (assert (string.match result "## Instructions") "should include Instructions header")
  (assert (string.match result "Be helpful") "should include content")
  (assert (string.match result "## Context") "should include Context header"))

(fn test-prompt-assemble-blocks-skips-nameless []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.assemble-blocks
    [{:content "No name here"}
     {:name "Valid" :content "Has name"}]))
  (assert (string.match result "## Valid") "should include named block")
  (assert (not (string.match result "No name here")) "should skip nameless block"))

(fn test-prompt-render-template []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.render-template "Hello ${name}, you are ${role}." {:name "Sam" :role "admin"}))
  (assert (= result "Hello Sam, you are admin.") "should replace variables"))

(fn test-prompt-render-template-missing-vars []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.render-template "Hello ${name}!" {}))
  (assert (= result "Hello ${name}!") "should leave missing vars in place"))

(fn test-prompt-format-context-with-enrichers []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (PromptUtils.register-enricher :test-world (fn [ctx] "active world available"))
  (PromptUtils.register-enricher :test-canvas (fn [ctx] "canvas visible"))
  (local result (PromptUtils.format-context {}))
  (assert (string.match result "active world available") "should include enricher output")
  (assert (string.match result "canvas visible") "should include second enricher")
  (PromptUtils.remove-enricher :test-world)
  (PromptUtils.remove-enricher :test-canvas))

(fn test-prompt-format-context-empty []
  (local PromptUtils (require :llm/agent/prompt-utils))
  ;; Ensure no enrichers registered
  (PromptUtils.remove-enricher :test-world)
  (PromptUtils.remove-enricher :test-canvas)
  (local result (PromptUtils.format-context {}))
  (assert (= result "No active context.") "should return default message"))

(fn test-prompt-format-presets []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local mock-presets
    {:get-active-presets (fn [] [{:name "drawing-shape-tools" :reason "auto"}
                                  {:name "drawing-history-tools" :reason "auto"}])})
  (local result (PromptUtils.format-presets mock-presets))
  (assert (string.match result "Active presets") "should have header")
  (assert (string.match result "drawing%-shape%-tools") "should include preset name")
  (assert (string.match result "drawing%-history%-tools") "should include second preset name"))

(fn test-prompt-format-presets-empty []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local mock-presets
    {:get-active-presets (fn [] [])})
  (local result (PromptUtils.format-presets mock-presets))
  (assert (= result "No active presets.") "should return default message"))

(fn test-prompt-remove-enricher []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (PromptUtils.register-enricher :temp-enricher (fn [ctx] "temp"))
  (local with-enricher (PromptUtils.format-context {}))
  (assert (string.match with-enricher "temp") "should have enricher output")
  (PromptUtils.remove-enricher :temp-enricher)
  (local without-enricher (PromptUtils.format-context {}))
  (assert (not (string.match without-enricher "temp")) "should not have removed enricher output"))

(fn test-prompt-enricher-errors-are-explicit []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (PromptUtils.register-enricher :broken-enricher (fn [ctx] (error "context failed")))
  (local (ok err) (pcall (fn [] (PromptUtils.format-context {}))))
  (PromptUtils.remove-enricher :broken-enricher)
  (assert (not ok) "broken enricher should fail loudly")
  (assert (string.match (tostring err) "broken%-enricher")
          "error should name the failing enricher"))

;; ═══════════════════════════════════════
;; Runner tests
;; ═══════════════════════════════════════

(fn test-runner-create-session []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub
            :presets {}
            :tools {}
            :approvals {}
            :agents registry
            :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (assert session "session should be created")
  (assert (= session.agent-id "space-agent") "should have correct agent-id")
  (assert (= session.status :idle) "should start idle")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-get-session []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub
            :presets {}
            :tools {}
            :approvals {}
            :agents registry
            :providers {}}}))
  (local created (runner:create-session "space-agent"))
  (local loaded (runner:get-session created.id))
  (assert loaded "session should be loadable")
  (assert (= loaded.id created.id) "ids should match")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-run-turn-returns-handle-immediately []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  ;; Register an agent that completes immediately
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :name "Test"
       :run (fn [self input session ctx]
              (ctx.turn:finish {:content (.. "echo: " input)}))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub
            :presets {}
            :tools {}
            :approvals {}
            :agents registry
            :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (var turn-result nil)
  (local handle (runner:run-turn session.id "hello"
    {:on-complete (fn [r] (set turn-result r))}))
  (assert handle "handle should be returned immediately")
  (assert (= (handle:status) :completed) "turn should be completed synchronously")
  (assert turn-result "on-complete should have fired")
  (assert (= turn-result.result.content "echo: hello") "should echo input")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-run-turn-appends-user-message []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx] (ctx.turn:finish {:content "ok"}))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (runner:run-turn session.id "draw a circle" {})
  ;; Reload session to check persisted items
  (local reloaded (runner:get-session session.id))
  (assert reloaded "session should be reloadable")
  (assert (>= (length reloaded.items) 1) "should have at least user message item")
  (local user-item (. reloaded.items 1))
  (assert (= user-item.type "message") "first item should be message")
  (assert (= user-item.role "user") "should be user role")
  (assert (= user-item.content "draw a circle") "should have user content")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-cancel-turn []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (var cancel-invoked false)
  (var agent-started false)
  (var agent-finished false)
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx]
              (set agent-started true)
              (ctx.turn:set-cancel (fn [] (set cancel-invoked true)))
              ;; Don't finish - simulate long-running agent
              )}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (local handle (runner:run-turn session.id "do something long" {}))
  (assert agent-started "agent should have started")
  (runner:cancel-turn session.id)
  (assert cancel-invoked "agent-registered cancel should be invoked")
  (assert (= (handle:status) :cancelled) "handle should report cancelled")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-second-turn-cancels-first []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
   (var first-cancelled false)
  (var first-finished false)
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx]
              (ctx.turn:set-cancel (fn [] (set first-cancelled true)))
              ;; Don't finish immediately — simulate long-running turn
              ;; Only finish if not the first input (second turn)
              (when (not (= input "first"))
                (ctx.turn:finish {:content input})))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  ;; First turn - agent registers cancel but does NOT finish (long-running)
  (local handle1 (runner:run-turn session.id "first" {}))
  (assert (= (handle1:status) :running) "first turn should be running")
  ;; Second turn should cancel first
  (local handle2 (runner:run-turn session.id "second" {}))
  (assert (= (handle1:status) :cancelled) "first turn should be cancelled")
  (assert (= (handle2:status) :completed) "second turn should complete")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-delete-session []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (local path (fs.join-path dir (.. session.id ".json")))
  (assert (fs.exists path) "file should exist")
  (runner:delete-session session.id)
  (assert (not (fs.exists path)) "file should not exist after delete")
  (assert (= (runner:get-session session.id) nil) "should not be loadable")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-list-sessions []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (runner:create-session "space-agent")
  (runner:create-session "space-agent")
  (local items (runner:list-sessions))
  (assert (= (length items) 2) "should list 2 sessions")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-turn-fail-persists-error-item []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx]
              (ctx.turn:fail "something went wrong"))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (runner:run-turn session.id "test" {})
  (local reloaded (runner:get-session session.id))
  ;; Should have user message + error item
  (assert (>= (length reloaded.items) 2) "should have user message and error item")
  (local error-item (. reloaded.items (length reloaded.items)))
  (assert (= error-item.type "error") "last item should be error type")
  (assert (= error-item.error "something went wrong") "error should match")
  (runner:drop)
  (clean-dir dir))

;; ═══════════════════════════════════════
;; SpaceAgent fixture tests
;; ═══════════════════════════════════════

(fn test-space-agent-registers-with-registry []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg {:app :stub :presets {} :tools {} :approvals {} :providers {}})
  (local agent (reg:get "space-agent"))
  (assert agent "space-agent should be registered")
  (assert (= agent.id "space-agent") "should have correct id"))

(fn test-space-agent-run-with-mock-opencode []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))

  ;; Mock opencode client
  (var create-calls [])
  (var prompt-calls [])
  (var abort-calls [])
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (table.insert create-calls {:body body})
                (on-response {:ok true :data {:id "oc-ses-mock" :title body.title}}))
      :prompt (fn [id body on-response]
                (table.insert prompt-calls {:id id :body body})
                (on-response {:ok true
                              :data {:info {:model {:modelID "claude-mock"}}
                                     :parts [{:type "text" :text "I'll draw that for you!"}]
                                     :usage {:inputTokens 50 :outputTokens 30}}})
                )
      :abort (fn [id on-response]
               (table.insert abort-calls {:id id})
               (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  ;; Register SpaceAgent with mock provider
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub
     :presets {}
     :tools {}
     :approvals {}
     :providers {:opencode mock-opencode}})

  ;; Create runner
  (local mock-presets
    {:get-active-presets (fn [] [{:name "drawing-shape-tools" :reason "auto"}])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local mock-tools (mock-tool-surface [{:preset "drawing-shape-tools"
                                         :prompt "Use drawing shape tools for geometry edits."}]))
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools mock-tools
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var items-log [])
  (var completed nil)

  (local handle (runner:run-turn session.id "draw a red circle"
    {:on-item (fn [item] (table.insert items-log item))
     :on-complete (fn [r] (set completed r))}))

  ;; Verify handle completed
  (assert (= (handle:status) :completed) "turn should complete")
  (assert completed "on-complete should fire")
  (assert (= completed.result.content "I'll draw that for you!") "result should contain assistant response")

  ;; Verify OpenCode calls
  (assert (= (length create-calls) 1) "should call session.create once")
  (assert (= (length prompt-calls) 1) "should call session.prompt once")
  (local first-call (. prompt-calls 1))
  (local first-part (. first-call.body.parts 1))
  (assert (string.match first-part.text "draw a red circle") "prompt should contain user input")
  (assert (string.match first-call.body.system "Use drawing shape tools")
          "system prompt should include active preset guidance")

  ;; Verify session items persisted
  (local reloaded (runner:get-session session.id))
  (assert (>= (length reloaded.items) 2) "should have user message and assistant message")
  ;; Check user message
  (var user-msg nil)
  (var assistant-msg nil)
  (var user-count 0)
  (var assistant-count 0)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "message") (= item.role "user"))
      (set user-count (+ user-count 1))
      (set user-msg item))
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-count (+ assistant-count 1))
      (set assistant-msg item)))
  (assert (= user-count 1) "should persist exactly one user message")
  (assert (= assistant-count 1) "should persist exactly one assistant message")
  (assert user-msg "should have user message")
  (assert (= user-msg.content "draw a red circle") "user message should match")
  (assert assistant-msg "should have assistant message")
  (assert (= assistant-msg.content "I'll draw that for you!") "assistant message should match")
  (assert (= assistant-msg.provider "opencode") "should record provider")
  (assert (= assistant-msg.model "claude-mock") "should record model")

  ;; OpenCode session ID should be stored
  (assert (= reloaded.data.opencode-session-id "oc-ses-mock") "should store opencode session id")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-persists-opencode-tool-audit []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var messages-called false)
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (on-response {:ok true :data {:id "oc-audit"}}))
      :prompt (fn [id body on-response]
                (on-response {:ok true
                              :data {:info {:model {:modelID "audit-model"}}
                                     :parts [{:type "text" :text "done"}]
                                     :usage {}}}))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (set messages-called true)
                  (on-response
                    {:ok true
                     :data [{:info {:id "msg-tool"}
                             :parts [{:type "tool"
                                      :tool "space_agent_echo_token"
                                      :callID "call-123"
                                      :input {:token "abc"}
                                      :state {:status "completed"
                                              :output "abc"}}
                                     {:type "tool"
                                      :tool "space_agent_fail_token"
                                      :callID "call-err"
                                      :input {:token "bad"}
                                      :state {:status "error"
                                              :error {:message "boom"}}}]}]}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (local handle (runner:run-turn session.id "use the echo tool" {}))
  (assert (= (handle:status) :completed) "turn should complete")
  (assert messages-called "SpaceAgent should fetch OpenCode messages for audit persistence")
  (local reloaded (runner:get-session session.id))
  (var tool-call nil)
  (var tool-result nil)
  (var failed-tool-result nil)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "tool-call") (= item.call-id "call-123"))
      (set tool-call item))
    (when (and (= item.type "tool-result") (= item.call-id "call-123"))
      (set tool-result item))
    (when (and (= item.type "tool-result") (= item.call-id "call-err"))
      (set failed-tool-result item)))
  (assert tool-call "tool call item should be persisted")
  (assert (= tool-call.name "space_agent_echo_token") "tool call should preserve name")
  (assert (= tool-call.call-id "call-123") "tool call should preserve call id")
  (assert (string.match tool-call.arguments "abc") "tool call should preserve arguments")
  (assert tool-result "tool result item should be persisted")
  (assert (= tool-result.call-id "call-123") "tool result should use same call id")
  (assert (= tool-result.output "abc") "tool result should preserve output")
  (assert failed-tool-result "failed tool result item should be persisted")
  (assert failed-tool-result.is-error "failed tool result should be marked as error")
  (assert (string.match failed-tool-result.output "boom")
          "failed tool result should preserve error payload")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-waits-for-async-opencode-callbacks []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var create-callback nil)
  (var prompt-callback nil)
  (var prompt-body nil)
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (set create-callback on-response))
      :prompt (fn [id body on-response]
                (set prompt-body body)
                (set prompt-callback on-response))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var completed nil)
  (local handle (runner:run-turn session.id "async prompt"
    {:on-complete (fn [r] (set completed r))}))
  (assert (= (handle:status) :running) "turn should remain running until callbacks fire")
  (assert create-callback "session.create callback should be captured")
  (create-callback {:ok true :data {:id "oc-async"}})
  (assert (= (handle:status) :running) "turn should remain running until prompt callback fires")
  (assert prompt-callback "session.prompt callback should be captured")
  (local first-part (. prompt-body.parts 1))
  (assert (= first-part.text "async prompt") "prompt should contain input")
  (prompt-callback {:ok true
                    :data {:info {:model {:modelID "async-model"}}
                           :parts [{:type "text" :text "async result"}]
                           :usage {}}})
  (assert (= (handle:status) :completed) "turn should complete after prompt callback")
  (assert (= completed.result.content "async result") "completion should contain async response")
  (local reloaded (runner:get-session session.id))
  (var user-count 0)
  (var assistant-count 0)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "message") (= item.role "user"))
      (set user-count (+ user-count 1)))
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-count (+ assistant-count 1))))
  (assert (= user-count 1) "async path should persist exactly one user message")
  (assert (= assistant-count 1) "async path should persist exactly one assistant message")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-reuses-opencode-session []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))

  (var create-calls [])
  (var get-calls [])
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (table.insert create-calls {:body body})
                (on-response {:ok true :data {:id (.. "oc-ses-" (length create-calls))}}))
      :prompt (fn [id body on-response]
                (on-response {:ok true
                              :data {:info {:model {:modelID "claude-mock"}}
                                     :parts [{:type "text" :text "done"}]
                                     :usage {:inputTokens 1 :outputTokens 1}}}))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (table.insert get-calls {:id id})
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  ;; First turn: should create OpenCode session
  (runner:run-turn session.id "first message" {})
  (assert (= (length create-calls) 1) "first turn should create OpenCode session")

  ;; Second turn: should reuse OpenCode session
  (runner:run-turn session.id "second message" {})
  (assert (= (length create-calls) 1) "second turn should NOT create new OpenCode session")
  ;; Should have called session.get to validate existing session
  (assert (>= (length get-calls) 1) "should call session.get to validate")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-handles-opencode-error []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))

  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (on-response {:ok false :error "server down"}))
      :prompt (fn [id body on-response] nil)
      :abort (fn [id on-response] nil)
      :get (fn [id on-response]
             (on-response {:ok false :error "not found"}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var error-received nil)
  (local handle (runner:run-turn session.id "do something"
    {:on-error (fn [e] (set error-received e))}))

  (assert (= (handle:status) :failed) "turn should fail on opencode error")
  (assert error-received "on-error should fire")
  (assert (string.match error-received.error "server down") "error should mention cause")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-handles-prompt-error []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))

  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (on-response {:ok true :data {:id "oc-ses-mock"}}))
      :prompt (fn [id body on-response]
                (on-response {:ok false :error "rate limited"}))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id}}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var error-received nil)
  (local handle (runner:run-turn session.id "do something"
    {:on-error (fn [e] (set error-received e))}))

  (assert (= (handle:status) :failed) "turn should fail on prompt error")
  (assert (string.match error-received.error "rate limited") "error should mention cause")

  (runner:drop)
  (clean-dir dir))

;; ═══════════════════════════════════════
;; Register all tests
;; ═══════════════════════════════════════

(table.insert tests {:name "session create" :fn test-session-create})
(table.insert tests {:name "session load and cache" :fn test-session-load-and-cache})
(table.insert tests {:name "session load missing" :fn test-session-load-missing})
(table.insert tests {:name "session load corrupt errors" :fn test-session-load-corrupt-errors})
(table.insert tests {:name "session save updates timestamp" :fn test-session-save-updates-timestamp})
(table.insert tests {:name "session delete" :fn test-session-delete})
(table.insert tests {:name "session list" :fn test-session-list})
(table.insert tests {:name "session list empty dir" :fn test-session-list-empty-dir})
(table.insert tests {:name "session list corrupt errors" :fn test-session-list-corrupt-errors})
(table.insert tests {:name "session append item" :fn test-session-append-item})
(table.insert tests {:name "session append multiple item types" :fn test-session-append-multiple-item-types})

(table.insert tests {:name "turn pair creation" :fn test-turn-pair-creation})
(table.insert tests {:name "turn start and complete" :fn test-turn-start-and-complete})
(table.insert tests {:name "turn fail" :fn test-turn-fail})
(table.insert tests {:name "turn cancel" :fn test-turn-cancel})
(table.insert tests {:name "turn cancel invokes registered fn" :fn test-turn-cancel-invokes-registered-fn})
(table.insert tests {:name "turn cancel surfaces cancel fn error" :fn test-turn-cancel-surfaces-cancel-fn-error})
(table.insert tests {:name "turn cannot finish twice" :fn test-turn-cannot-finish-twice})
(table.insert tests {:name "turn fail after complete noop" :fn test-turn-fail-after-complete-noop})
(table.insert tests {:name "turn cancelled? flag" :fn test-turn-cancelled?-flag})
(table.insert tests {:name "turn append item callback" :fn test-turn-append-item-callback})

(table.insert tests {:name "registry register and get" :fn test-registry-register-and-get})
(table.insert tests {:name "registry lazy construction" :fn test-registry-lazy-construction})
(table.insert tests {:name "registry get unknown" :fn test-registry-get-unknown})
(table.insert tests {:name "registry list" :fn test-registry-list})
(table.insert tests {:name "registry unregister" :fn test-registry-unregister})
(table.insert tests {:name "registry reregister invalidates cache" :fn test-registry-reregister-invalidates-cache})

(table.insert tests {:name "approvals normal always approved" :fn test-approvals-normal-always-approved})
(table.insert tests {:name "approvals auto policy" :fn test-approvals-auto-policy})
(table.insert tests {:name "approvals deny policy" :fn test-approvals-deny-policy})
(table.insert tests {:name "approvals ask default" :fn test-approvals-ask-default})
(table.insert tests {:name "approvals request-risk auto" :fn test-approvals-request-risk-auto})
(table.insert tests {:name "approvals request-risk needs-approval" :fn test-approvals-request-risk-needs-approval})
(table.insert tests {:name "approvals unknown risk asserts" :fn test-approvals-unknown-risk-asserts})
(table.insert tests {:name "approvals record decision" :fn test-approvals-record-decision})

(table.insert tests {:name "tool surface active presets" :fn test-tool-surface-active-presets})
(table.insert tests {:name "tool surface openai tools" :fn test-tool-surface-openai-tools})
(table.insert tests {:name "tool surface mcp defs" :fn test-tool-surface-mcp-defs})
(table.insert tests {:name "tool surface call delegates to mcp" :fn test-tool-surface-call-delegates-to-mcp})
(table.insert tests {:name "tool surface denies unapproved risk" :fn test-tool-surface-denies-unapproved-risk})
(table.insert tests {:name "agent mcp sync registers approved surface tools" :fn test-agent-mcp-sync-registers-approved-surface-tools})
(table.insert tests {:name "agent mcp sync does not bypass surface gating" :fn test-agent-mcp-sync-does-not_bypass_surface_gating})
(table.insert tests {:name "opencode mcp bridge starts and writes config" :fn test-opencode-mcp-bridge-starts-and-writes-config})

(table.insert tests {:name "prompt assemble blocks" :fn test-prompt-assemble-blocks})
(table.insert tests {:name "prompt assemble blocks skips nameless" :fn test-prompt-assemble-blocks-skips-nameless})
(table.insert tests {:name "prompt render template" :fn test-prompt-render-template})
(table.insert tests {:name "prompt render template missing vars" :fn test-prompt-render-template-missing-vars})
(table.insert tests {:name "prompt format context with enrichers" :fn test-prompt-format-context-with-enrichers})
(table.insert tests {:name "prompt format context empty" :fn test-prompt-format-context-empty})
(table.insert tests {:name "prompt format presets" :fn test-prompt-format-presets})
(table.insert tests {:name "prompt format presets empty" :fn test-prompt-format-presets-empty})
(table.insert tests {:name "prompt remove enricher" :fn test-prompt-remove-enricher})
(table.insert tests {:name "prompt enricher errors are explicit" :fn test-prompt-enricher-errors-are-explicit})

(table.insert tests {:name "runner create session" :fn test-runner-create-session})
(table.insert tests {:name "runner get session" :fn test-runner-get-session})
(table.insert tests {:name "runner run-turn returns handle immediately" :fn test-runner-run-turn-returns-handle-immediately})
(table.insert tests {:name "runner run-turn appends user message" :fn test-runner-run-turn-appends-user-message})
(table.insert tests {:name "runner cancel turn" :fn test-runner-cancel-turn})
(table.insert tests {:name "runner second turn cancels first" :fn test-runner-second-turn-cancels-first})
(table.insert tests {:name "runner delete session" :fn test-runner-delete-session})
(table.insert tests {:name "runner list sessions" :fn test-runner-list-sessions})
(table.insert tests {:name "runner turn fail persists error item" :fn test-runner-turn-fail-persists-error-item})

(table.insert tests {:name "space-agent registers with registry" :fn test-space-agent-registers-with-registry})
(table.insert tests {:name "space-agent run with mock opencode" :fn test-space-agent-run-with-mock-opencode})
(table.insert tests {:name "space-agent persists opencode tool audit" :fn test-space-agent-persists-opencode-tool-audit})
(table.insert tests {:name "space-agent waits for async opencode callbacks" :fn test-space-agent-waits-for-async-opencode-callbacks})
(table.insert tests {:name "space-agent reuses opencode session" :fn test-space-agent-reuses-opencode-session})
(table.insert tests {:name "space-agent handles opencode error" :fn test-space-agent-handles-opencode-error})
(table.insert tests {:name "space-agent handles prompt error" :fn test-space-agent-handles-prompt-error})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests
      {:name "agent-layer"
       :tests tests})))

{:name "agent-layer"
 :tests tests
 :main main}
