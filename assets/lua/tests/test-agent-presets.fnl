;; Agent Presets unit tests — preset schema, context resolution, overrides.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-presets:main

(local tests [])
(local {: PresetRegistry} (require :llm/presets/registry))
(local {: ToolAdapterRegistry} (require :llm/presets/tool-adapters))
(local {: PresetManager} (require :llm/presets/init))
(local BuiltinDrawing (require :llm/presets/builtins/drawing))
(local BuiltinGraph (require :llm/presets/builtins/graph))
(local BuiltinScene (require :llm/presets/builtins/scene))
(local BuiltinGeneral (require :llm/presets/builtins/general))

(fn make-dummy-app []
  {})

(fn make-dummy-adapters []
  (ToolAdapterRegistry {}))

(fn make-dummy-preset [name]
  {:name (or name "test-preset")
   :default-state :auto
   :risk :normal
   :contexts [{:surface :canvas :mode "drawing"}]
   :tool-ids [(.. (or name "test-preset") ".tool1")]})

(fn dummy-adapter-factory [id mcp-name]
  {:id id
   :mcp-name mcp-name
   :description (.. "Adapter for " id)
   :inputSchema {:type "object" :properties {}}
   :make-run (fn [_app] (fn [] (.. "ran " id)))})

;; ── Registry: create ──

(fn test-registry-create []
  (local reg (PresetRegistry {}))
  (assert reg "registry should be created")
  (local s (reg:status))
  (assert (= s.preset-count 0) "fresh registry should have 0 presets"))

(table.insert tests {:name "agent-presets: registry create" :fn test-registry-create})

;; ── Registry: register and list ──

(fn test-registry-register []
  (local reg (PresetRegistry {}))
  (reg:register {:name "test-preset"
                  :default-state :auto
                  :risk :normal
                  :contexts [{:surface :canvas :mode "drawing"}]
                  :tool-ids ["t1" "t2"]
                  :system-prompt "Hello"})
  (local presets (reg:list))
  (assert (= (# presets) 1) "should have 1 preset")
  (assert (= (. presets 1 :name) "test-preset") "preset name should match")
  (assert (= (. presets 1 :risk) :normal) "risk should match")
  (assert (= (. presets 1 :system-prompt) "Hello") "system-prompt should match"))

(table.insert tests {:name "agent-presets: registry register and list" :fn test-registry-register})

;; ── Registry: reject duplicate name ──

(fn test-registry-duplicate-name []
  (local reg (PresetRegistry {}))
  (reg:register (make-dummy-preset "dup"))
  (local (ok err) (pcall reg.register reg (make-dummy-preset "dup")))
  (assert (not ok) "should reject duplicate preset name")
  (assert (string.find (tostring err) "dup") "error should mention duplicate name"))

(table.insert tests {:name "agent-presets: reject duplicate preset name" :fn test-registry-duplicate-name})

;; ── Registry: unregister ──

(fn test-registry-unregister []
  (local reg (PresetRegistry {}))
  (reg:register (make-dummy-preset "a"))
  (reg:register (make-dummy-preset "b"))
  (assert (= (# (reg:list)) 2) "should have 2 presets")
  (reg:unregister "a")
  (assert (= (# (reg:list)) 1) "should have 1 preset after unregister")
  (assert (= (. (reg:list) 1 :name) "b") "remaining preset should be 'b'"))

(table.insert tests {:name "agent-presets: unregister" :fn test-registry-unregister})

;; ── Registry: unregister unknown fails ──

(fn test-registry-unregister-unknown []
  (local reg (PresetRegistry {}))
  (local (ok err) (pcall reg.unregister reg "nonexistent"))
  (assert (not ok) "should fail for unknown preset"))

(table.insert tests {:name "agent-presets: unregister unknown fails" :fn test-registry-unregister-unknown})

;; ── Registry: on-change callback ──

(fn test-registry-on-change []
  (local reg (PresetRegistry {}))
  (var count 0)
  (reg:add-on-change (fn [] (set count (+ count 1))))
  (reg:register (make-dummy-preset "a"))
  (assert (= count 1) "on-change should fire on register")
  (reg:unregister "a")
  (assert (= count 2) "on-change should fire on unregister"))

(table.insert tests {:name "agent-presets: on-change callback" :fn test-registry-on-change})

;; ── Registry: remove on-change ──

(fn test-registry-remove-on-change []
  (local reg (PresetRegistry {}))
  (var count 0)
  (local token (reg:add-on-change (fn [] (set count (+ count 1)))))
  (reg:register (make-dummy-preset "a"))
  (assert (= count 1))
  (reg:remove-on-change token)
  (reg:register (make-dummy-preset "b"))
  (assert (= count 1) "removed listener should not fire"))

(table.insert tests {:name "agent-presets: remove on-change listener" :fn test-registry-remove-on-change})

;; ── Registry: accessors return defensive copies ──

(fn test-registry-defensive-copies []
  (local reg (PresetRegistry {}))
  (reg:register (make-dummy-preset "copy-test"))
  (local listed (reg:list))
  (set (. listed 1 :name) "mutated")
  (assert (= (. (reg:get "copy-test") :name) "copy-test")
          "mutating list output should not mutate registry state")
  (local fetched (reg:get "copy-test"))
  (set fetched.name "mutated-again")
  (assert (= (. (reg:get "copy-test") :name) "copy-test")
          "mutating get output should not mutate registry state"))

(table.insert tests {:name "agent-presets: registry accessors return defensive copies"
                     :fn test-registry-defensive-copies})

;; ── Registry: list-by-group ──

(fn test-registry-list-by-group []
  (local reg (PresetRegistry {}))
  (reg:register {:name "a" :group "x" :default-state :auto :risk :normal
                  :contexts [{:surface :any}] :tool-ids ["t1"]})
  (reg:register {:name "b" :group "x" :default-state :auto :risk :normal
                  :contexts [{:surface :any}] :tool-ids ["t2"]})
  (reg:register {:name "c" :group "y" :default-state :auto :risk :normal
                  :contexts [{:surface :any}] :tool-ids ["t3"]})
  (assert (= (# (reg:list-by-group "x")) 2) "group x should have 2 presets")
  (assert (= (# (reg:list-by-group "y")) 1) "group y should have 1 preset")
  (assert (= (# (reg:list-by-group "z")) 0) "unknown group should be empty")
  (local grouped (reg:list-by-group "x"))
  (set (. grouped 1 :name) "mutated")
  (assert (= (. (reg:get "a") :name) "a")
          "mutating group list output should not mutate registry state"))

(table.insert tests {:name "agent-presets: list-by-group" :fn test-registry-list-by-group})

;; ── Registry: validate default-state ──

(fn test-registry-validate-default-state []
  (local reg (PresetRegistry {}))
  (local (ok err) (pcall reg.register reg
                          {:name "bad" :default-state :invalid :risk :normal
                           :contexts [{:surface :any}] :tool-ids ["t1"]}))
  (assert (not ok) "should reject invalid default-state"))

(table.insert tests {:name "agent-presets: validate default-state" :fn test-registry-validate-default-state})

;; ── Registry: validate risk ──

(fn test-registry-validate-risk []
  (local reg (PresetRegistry {}))
  (local (ok err) (pcall reg.register reg
                          {:name "bad" :default-state :auto :risk :invalid
                           :contexts [{:surface :any}] :tool-ids ["t1"]}))
  (assert (not ok) "should reject invalid risk"))

(table.insert tests {:name "agent-presets: validate risk" :fn test-registry-validate-risk})

;; ── Registry: validate contexts present ──

(fn test-registry-validate-contexts []
  (local reg (PresetRegistry {}))
  (local (ok err) (pcall reg.register reg
                          {:name "bad" :default-state :auto :risk :normal
                           :contexts [] :tool-ids ["t1"]}))
  (assert (not ok) "should reject empty contexts"))

(table.insert tests {:name "agent-presets: validate contexts present" :fn test-registry-validate-contexts})

;; ── Registry: validate tool-ids ──

(fn test-registry-validate-tool-ids []
  (local reg (PresetRegistry {}))
  (local (ok err) (pcall reg.register reg
                          {:name "bad" :default-state :auto :risk :normal
                           :contexts [{:surface :any}] :tool-ids []}))
  (assert (not ok) "should reject empty tool-ids")
  (assert (string.find (tostring err) "tool") "error should mention tool-ids"))

(table.insert tests {:name "agent-presets: validate tool-ids" :fn test-registry-validate-tool-ids})

;; ── Resolution: exact context match ──

(fn test-resolution-exact-match []
  (local reg (PresetRegistry {}))
  (reg:register {:name "drawing-tools" :default-state :auto :risk :normal
                  :contexts [{:surface :canvas :mode "drawing"}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :canvas :mode "drawing" :canvas-visible? true} nil))
  (assert (= (# result.active-presets) 1) "should have 1 active preset")
  (assert (= (. result.active-presets 1 :name) "drawing-tools"))
  (assert (= (. result.active-presets 1 :reason) :context)))

(table.insert tests {:name "agent-presets: exact context match" :fn test-resolution-exact-match})

;; ── Resolution: no match ──

(fn test-resolution-no-match []
  (local reg (PresetRegistry {}))
  (reg:register {:name "drawing-tools" :default-state :auto :risk :normal
                  :contexts [{:surface :canvas :mode "drawing"}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :scene :mode nil :canvas-visible? false} nil))
  (assert (= (# result.active-presets) 0) "should have 0 active presets when no context matches"))

(table.insert tests {:name "agent-presets: no context match" :fn test-resolution-no-match})

;; ── Resolution: :any wildcard ──

(fn test-resolution-any-wildcard []
  (local reg (PresetRegistry {}))
  (reg:register {:name "general-tools" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :scene :mode nil :canvas-visible? false} nil))
  (assert (= (# result.active-presets) 1) ":any should match scene")
  (local result2 (reg:resolve {:surface :canvas :mode "graph" :canvas-visible? true} nil))
  (assert (= (# result2.active-presets) 1) ":any should match canvas"))

(table.insert tests {:name "agent-presets: :any wildcard" :fn test-resolution-any-wildcard})

;; ── Resolution: missing field is wildcard ──

(fn test-resolution-missing-field []
  (local reg (PresetRegistry {}))
  (reg:register {:name "scene-tools" :default-state :auto :risk :normal
                  :contexts [{:surface :scene}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :scene :mode "drawing" :canvas-visible? false} nil))
  (assert (= (# result.active-presets) 1) "missing mode field should be wildcard match"))

(table.insert tests {:name "agent-presets: missing field wildcard" :fn test-resolution-missing-field})

;; ── Resolution: nil mode match ──

(fn test-resolution-nil-mode []
  (local reg (PresetRegistry {}))
  (reg:register {:name "nil-mode-tools" :default-state :auto :risk :normal
                  :contexts [{:surface :scene :mode nil}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :scene :mode nil :canvas-visible? false} nil))
  (assert (= (# result.active-presets) 1) "nil mode should match nil mode"))

(table.insert tests {:name "agent-presets: nil mode match" :fn test-resolution-nil-mode})

;; ── Resolution: :off preset never auto-activates ──

(fn test-resolution-off-never-auto []
  (local reg (PresetRegistry {}))
  (reg:register {:name "destructive-tools" :default-state :off :risk :destructive
                  :contexts [{:surface :any}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :canvas :mode nil :canvas-visible? true} nil))
  (assert (= (# result.active-presets) 0) ":off preset should never auto-activate"))

(table.insert tests {:name "agent-presets: :off never auto-activates" :fn test-resolution-off-never-auto})

;; ── Resolution: force on via override ──

(fn test-resolution-force-on []
  (local reg (PresetRegistry {}))
  (reg:register {:name "destructive-tools" :default-state :off :risk :destructive
                  :contexts [{:surface :any}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :scene :mode nil :canvas-visible? false}
                              {"destructive-tools" {:state :on}}))
  (assert (= (# result.active-presets) 1) "force on should activate :off preset")
  (assert (= (. result.active-presets 1 :reason) :override))

  (local result2 (reg:resolve {:surface :canvas :mode "drawing" :canvas-visible? true}
                               {"destructive-tools" {:state :on}}))
  (assert (= (# result2.active-presets) 1) "force on should work regardless of context"))

(table.insert tests {:name "agent-presets: force :on via override" :fn test-resolution-force-on})

;; ── Resolution: force off via override ──

(fn test-resolution-force-off []
  (local reg (PresetRegistry {}))
  (reg:register {:name "drawing-tools" :default-state :auto :risk :normal
                  :contexts [{:surface :canvas :mode "drawing"}]
                  :tool-ids ["t1"]})
  (local result (reg:resolve {:surface :canvas :mode "drawing" :canvas-visible? true}
                              {"drawing-tools" {:state :off}}))
  (assert (= (# result.active-presets) 0) "force off should deactivate auto preset"))

(table.insert tests {:name "agent-presets: force :off via override" :fn test-resolution-force-off})

;; ── Resolution: prompt fragments in order ──

(fn test-resolution-prompt-fragments []
  (local reg (PresetRegistry {}))
  (reg:register {:name "a" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["t1"]
                  :system-prompt "First prompt"})
  (reg:register {:name "b" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["t2"]
                  :system-prompt "Second prompt"})
  (local result (reg:resolve {:surface :scene :mode nil :canvas-visible? false} nil))
  (assert (= (# result.prompt-fragments) 2) "should have 2 prompt fragments")
  (assert (= (. result.prompt-fragments 1 :prompt) "First prompt") "first fragment matches registration order")
  (assert (= (. result.prompt-fragments 2 :prompt) "Second prompt") "second fragment matches registration order")
  (assert (= (. result.prompt-fragments 1 :preset) "a"))
  (assert (= (. result.prompt-fragments 2 :preset) "b")))

(table.insert tests {:name "agent-presets: prompt fragments in registration order"
                     :fn test-resolution-prompt-fragments})

;; ── Resolution: duplicate tool-id rejected ──

(fn test-resolution-duplicate-tool-id []
  (local reg (PresetRegistry {}))
  (reg:register {:name "a" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["shared-tool"]})
  (reg:register {:name "b" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["shared-tool"]})
  (local (ok err) (pcall reg.resolve reg {:surface :scene :mode nil :canvas-visible? false} nil))
  (assert (not ok) "should reject duplicate tool-id")
  (assert (string.find (tostring err) "duplicate") "error should mention duplicate"))
(table.insert tests {:name "agent-presets: reject duplicate resolved tool-id"
                     :fn test-resolution-duplicate-tool-id})

;; ── Resolution: multiple context patterns OR-match ──

(fn test-resolution-or-match []
  (local reg (PresetRegistry {}))
  (reg:register {:name "multi-surface" :default-state :auto :risk :normal
                  :contexts [{:surface :canvas :mode "drawing"} {:surface :scene}]
                  :tool-ids ["t1"]})
  (local result1 (reg:resolve {:surface :canvas :mode "drawing" :canvas-visible? true} nil))
  (assert (= (# result1.active-presets) 1) "should match first context pattern")
  (local result2 (reg:resolve {:surface :scene :mode nil :canvas-visible? false} nil))
  (assert (= (# result2.active-presets) 1) "should match second context pattern"))

(table.insert tests {:name "agent-presets: OR-match across context patterns"
                     :fn test-resolution-or-match})

;; ── Resolution: validate context ──

(fn test-resolution-validate-context []
  (local reg (PresetRegistry {}))
  (local (ok err) (pcall reg.resolve reg {:surface :scene} nil))
  (assert (not ok) "should reject context without canvas-visible?"))

(table.insert tests {:name "agent-presets: validate context fields" :fn test-resolution-validate-context})

;; ── Resolution: validate overrides ──

(fn test-resolution-validate-overrides []
  (local reg (PresetRegistry {}))
  (reg:register {:name "test" :default-state :auto :risk :normal
                  :contexts [{:surface :any}] :tool-ids ["t1"]})
  (local (ok err) (pcall reg.resolve reg {:surface :scene :mode nil :canvas-visible? false}
                           {"test" {:state :invalid}}))
  (assert (not ok) "should reject invalid override state"))

(table.insert tests {:name "agent-presets: validate override state" :fn test-resolution-validate-overrides})

;; ── Resolution: unknown override name rejected ──

(fn test-resolution-rejects-unknown-override-name []
  (local reg (PresetRegistry {}))
  (reg:register {:name "known" :default-state :auto :risk :normal
                  :contexts [{:surface :any}] :tool-ids ["t1"]})
  (local (ok err) (pcall reg.resolve reg {:surface :scene :mode nil :canvas-visible? false}
                          {"typo" {:state :on}}))
  (assert (not ok) "should reject unknown override names")
  (assert (string.find (tostring err) "typo") "error should mention unknown override name"))

(table.insert tests {:name "agent-presets: reject unknown override names during resolution"
                     :fn test-resolution-rejects-unknown-override-name})

;; ── ToolAdapterRegistry: create ──

(fn test-adapters-create []
  (local adapters (ToolAdapterRegistry {}))
  (assert adapters "adapters should be created"))

(table.insert tests {:name "agent-presets: adapter-registry create" :fn test-adapters-create})

;; ── ToolAdapterRegistry: register and resolve ──

(fn test-adapters-register-resolve []
  (local adapters (ToolAdapterRegistry {}))
  (adapters:register (dummy-adapter-factory "t1" "space_t1"))
  (local def (adapters:resolve "t1" (make-dummy-app)))
  (assert def "should resolve adapter")
  (assert (= def.name "space_t1") "mcp-name should match")
  (assert (= (type def.run) "function") "resolved def should have run function")
  (assert (= def.managed-owner "agent-presets") "should have managed-owner")
  (assert (= def.managed-source "t1") "should have managed-source"))

(table.insert tests {:name "agent-presets: adapter register and resolve"
                     :fn test-adapters-register-resolve})

;; ── ToolAdapterRegistry: unknown adapter fails ──

(fn test-adapters-unknown []
  (local adapters (ToolAdapterRegistry {}))
  (local (ok err) (pcall adapters.resolve adapters "nonexistent" (make-dummy-app)))
  (assert (not ok) "should fail for unknown adapter"))

(table.insert tests {:name "agent-presets: unknown adapter fails" :fn test-adapters-unknown})

;; ── ToolAdapterRegistry: validate mcp-name prefix ──

(fn test-adapters-validate-prefix []
  (local adapters (ToolAdapterRegistry {}))
  (local (ok err) (pcall adapters.register adapters
                          {:id "t1" :mcp-name "bad_name" :description "desc"
                           :inputSchema {:type "object" :properties {}}
                           :make-run (fn [_app] (fn [] "ok"))}))
  (assert (not ok) "should reject mcp-name without space_ prefix"))

(table.insert tests {:name "agent-presets: validate mcp-name prefix" :fn test-adapters-validate-prefix})

;; ── PresetManager: create ──

(fn test-manager-create []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (assert mgr "manager should be created"))
(table.insert tests {:name "agent-presets: manager create" :fn test-manager-create})

;; ── PresetManager: set-context and get-context ──

(fn test-manager-context []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (assert (= (. (mgr:get-context) :surface) :scene) "initial context should be scene")
  (mgr:set-context {:surface :canvas :mode "drawing" :canvas-visible? true})
  (assert (= (. (mgr:get-context) :surface) :canvas) "context should be updated"))
(table.insert tests {:name "agent-presets: set/get context" :fn test-manager-context})

;; ── PresetManager: accessors return defensive copies ──

(fn test-manager-defensive-copies []
  (local reg (PresetRegistry {}))
  (reg:register {:name "test" :default-state :auto :risk :normal
                  :contexts [{:surface :scene}] :tool-ids ["t1"]})
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (local context (mgr:get-context))
  (set context.surface :canvas)
  (assert (= (. (mgr:get-context) :surface) :scene)
          "mutating get-context output should not mutate manager context")
  (mgr:set-override "test" :on)
  (local overrides (mgr:get-overrides))
  (set (. overrides "test" :state) :off)
  (assert (= (. (mgr:get-overrides) "test" :state) :on)
          "mutating get-overrides output should not mutate manager overrides")
  (local active (mgr:get-active-presets))
  (set (. active 1 :name) "mutated")
  (assert (= (. (mgr:get-active-presets) 1 :name) "test")
          "mutating active preset output should not mutate cached resolution"))

(table.insert tests {:name "agent-presets: manager accessors return defensive copies"
                     :fn test-manager-defensive-copies})

;; ── PresetManager: set-override unknown preset ──

(fn test-manager-override-unknown []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (local (ok err) (pcall mgr.set-override mgr "nonexistent" :on))
  (assert (not ok) "should reject unknown preset in override"))
(table.insert tests {:name "agent-presets: reject unknown override name" :fn test-manager-override-unknown})

;; ── PresetManager: get-tool-defs resolves adapters ──

(fn test-manager-get-tool-defs []
  (local reg (PresetRegistry {}))
  (reg:register {:name "test" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["t1" "t2"]})
  (local adapters (ToolAdapterRegistry {}))
  (adapters:register (dummy-adapter-factory "t1" "space_t1"))
  (adapters:register (dummy-adapter-factory "t2" "space_t2"))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (local defs (mgr:get-tool-defs))
  (assert (= (# defs) 2) "should have 2 tool defs")
  (assert (= (. defs 1 :name) "space_t1") "first def should be space_t1")
  (assert (= (. defs 2 :name) "space_t2") "second def should be space_t2"))
(table.insert tests {:name "agent-presets: get-tool-defs resolves adapters" :fn test-manager-get-tool-defs})

;; ── PresetManager: get-tool-defs rejects duplicate MCP names ──

(fn test-manager-get-tool-defs-duplicate []
  (local reg (PresetRegistry {}))
  (reg:register {:name "a" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["t1"]})
  (reg:register {:name "b" :default-state :auto :risk :normal
                  :contexts [{:surface :any}]
                  :tool-ids ["t2"]})
  (local adapters (ToolAdapterRegistry {}))
  (adapters:register (dummy-adapter-factory "t1" "space_same"))
  (adapters:register (dummy-adapter-factory "t2" "space_same"))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (local (ok err) (pcall mgr.get-tool-defs mgr))
  (assert (not ok) "should reject duplicate MCP tool names"))
(table.insert tests {:name "agent-presets: reject duplicate MCP tool names" :fn test-manager-get-tool-defs-duplicate})

;; ── PresetManager: on-change fires on context change ──

(fn test-manager-on-change-context []
  (local reg (PresetRegistry {}))
  (reg:register {:name "test" :default-state :auto :risk :normal
                  :contexts [{:surface :canvas :mode "drawing"}]
                  :tool-ids ["t1"]})
  (local adapters (ToolAdapterRegistry {}))
  (adapters:register (dummy-adapter-factory "t1" "space_t1"))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (var count 0)
  (mgr:add-on-change (fn [] (set count (+ count 1))))
  (mgr:set-context {:surface :canvas :mode "drawing" :canvas-visible? true})
  (assert (= count 1) "on-change should fire on context change"))
(table.insert tests {:name "agent-presets: on-change fires on context change" :fn test-manager-on-change-context})

;; ── PresetManager: on-change does NOT fire on same context ──

(fn test-manager-on-change-same-context []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (var count 0)
  (mgr:add-on-change (fn [] (set count (+ count 1))))
  (mgr:set-context {:surface :scene :mode nil :canvas-visible? false})
  (assert (= count 0) "on-change should NOT fire when context is unchanged"))
(table.insert tests {:name "agent-presets: on-change does not fire on same context"
                     :fn test-manager-on-change-same-context})

;; ── Built-ins: register adapters reachable from manager ──

(fn test-builtins-register-adapters []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (BuiltinDrawing.register mgr)
  (BuiltinGraph.register mgr)
  (BuiltinScene.register mgr)
  (BuiltinGeneral.register mgr)
  (local defs (mgr:get-tool-defs))
  (assert (> (# defs) 0) "built-in presets should resolve MCP tool definitions")
  (local names {})
  (each [_ def (ipairs defs)]
    (set (. names def.name) true))
  (assert names.space_scene_add_cuboid "scene built-in adapter should be registered")
  (assert names.space_app_set_theme "general built-in adapter should be registered"))
(table.insert tests {:name "agent-presets: built-ins register adapters through manager"
                     :fn test-builtins-register-adapters})

;; ── Built-ins: publish complete state during registration ──

(fn test-builtins-register-adapters-before-presets []
  (local reg (PresetRegistry {}))
  (local adapters (ToolAdapterRegistry {}))
  (local mgr (PresetManager {:registry reg :tool-adapters adapters :app (make-dummy-app)
                              :context {:surface :scene :mode nil :canvas-visible? false}}))
  (var sync-ok? true)
  (var sync-err nil)
  (mgr:add-on-change
    (fn []
      (local (ok err) (pcall mgr.get-tool-defs mgr))
      (when (not ok)
        (set sync-ok? false)
        (set sync-err err))))
  (BuiltinScene.register mgr)
  (assert sync-ok? (.. "registration should not expose presets before adapters: " (tostring sync-err))))
(table.insert tests {:name "agent-presets: built-ins publish adapters before presets"
                     :fn test-builtins-register-adapters-before-presets})

;; ── Main ──

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "agent-presets" :tests tests}))

{:tests tests
 :main main}
