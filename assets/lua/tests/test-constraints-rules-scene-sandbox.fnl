;; Tests for Scene/Sandbox constraint rules.
;; Follows TDD: these tests must FAIL before scene-sandbox.fnl and scenarios.fnl are implemented.

(local tests [])

;; --- Helpers for constructing synthetic fact DBs ---

(fn make-file-fact [opts]
  "Create a synthetic file-fact record for testing rule functions."
  (local o (or opts {}))
  {:target (or o.target {:kind :repo :name :test})
   :path (or o.path "/test/module.fnl")
   :module (or o.module "test-module")
   :requires (or o.requires [])
   :definitions (or o.definitions [])
   :exports (or o.exports [])
   :calls (or o.calls [])
   :accesses (or o.accesses [])
   :mutations (or o.mutations [])
   :metrics (or o.metrics {:module-lines 0
                           :max-nesting-depth 0
                           :max-anonymous-callback-depth 0
                           :max-table-literal-size 0
                           :functions []})})

(fn make-fact-db [file-facts]
  "Create a synthetic fact-db from a list of file-fact records."
  (let [by-file {}]
    (each [_ ff (ipairs file-facts)]
      (tset by-file ff.path ff))
    {:files file-facts
     :by-file by-file}))

(fn make-ctx [file-facts]
  "Create a context table for rule execution."
  {:target {:kind :repo :name :test}
   :facts (make-fact-db file-facts)
   :files []})

;; --- Rule 1: scene.no-legacy-world-state-scene ---

(fn find-rule-by-id [rules id]
  "Find a rule in a rules list by its :id field."
  (var found nil)
  (each [_ r (ipairs rules)]
    (when (= r.id id)
      (set found r)))
  found)

(fn no-legacy-allows-clean-file []
  "A file with no world.state.scene access should pass."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.no-legacy-world-state-scene"))
  (assert rule "rule scene.no-legacy-world-state-scene should be in rules list")
  (local ff (make-file-fact {:path "/src/new-module.fnl"
                             :module "new-module"
                             :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "clean file should pass without diagnostics"))

(fn no-legacy-flags-world-state-scene-access []
  "A non-allowlisted file with world.state.scene.* access should produce a diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.no-legacy-world-state-scene"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/new-module.fnl"
                             :module "new-module"
                             :accesses [{:path ["world" "state" "scene" "panels"]
                                         :text "world.state.scene.panels"
                                         :line 42
                                         :column 5
                                         :form "world.state.scene.panels"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "scene.no-legacy-world-state-scene")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "scene-sandbox") "diagnostic should have family scene-sandbox")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert (= d.line 42) "diagnostic should include line")
  (assert (= d.column 5) "diagnostic should include column")
  (assert d.evidence "diagnostic should include evidence"))

(fn no-legacy-allows-allowlisted-migration-files []
  "An allowlisted migration file with world.state.scene access should pass."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.no-legacy-world-state-scene"))
  (assert rule "rule should be in rules list")
  ;; home-world.fnl is an allowed migration file
  (local ff (make-file-fact {:path "/lua/home-world.fnl"
                             :module "home-world"
                             :accesses [{:path ["world" "state" "scene" "panels"]
                                         :text "world.state.scene.panels"
                                         :line 10
                                         :column 1
                                         :form "world.state.scene.panels"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "allowlisted migration file should pass"))

;; --- Rule 2: scene.activity-slot-ownership ---

(fn slot-ownership-allows-correct-graph-slot []
  "graph-activity-unit calling ensure/activate with 'graph' should pass."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.activity-slot-ownership"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/graph-activity-unit.fnl"
                             :module "graph-activity-unit"
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 10 :column 1
                                      :form "(scene:ensure-activity-slot \"graph\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 11 :column 1
                                      :form "(scene:activate-activity-slot \"graph\")"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "correct slot ownership should pass"))

(fn slot-ownership-flags-graph-using-sandbox []
  "graph-activity-unit calling ensure/activate with 'sandbox' should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.activity-slot-ownership"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/graph-activity-unit.fnl"
                             :module "graph-activity-unit"
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 10 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 11 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "scene.activity-slot-ownership")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "scene-sandbox") "diagnostic should have family scene-sandbox"))

(fn slot-ownership-flags-drawing-using-sandbox []
  "drawing-activity-unit calling ensure/activate with 'sandbox' should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.activity-slot-ownership"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/drawing-activity-unit.fnl"
                             :module "drawing-activity-unit"
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 10 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn slot-ownership-flags-board-using-sandbox []
  "board-activity-unit calling ensure/activate with 'sandbox' should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.activity-slot-ownership"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/board-activity-unit.fnl"
                             :module "board-activity-unit"
                             :calls [{:callee "scene:activate-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 10 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn slot-ownership-flags-missing-ensure-call []
  "graph-activity-unit missing scene:ensure-activity-slot should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.activity-slot-ownership"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/graph-activity-unit.fnl"
                             :module "graph-activity-unit"
                             :calls [{:callee "scene:activate-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 10 :column 1
                                      :form "(scene:activate-activity-slot \"graph\")"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for missing ensure-activity-slot")
  (assert (> (length result) 0) "should have at least one diagnostic")
  ;; Verify at least one diagnostic references the missing call
  (var found-missing false)
  (each [_ d (ipairs result)]
    (when (. d.evidence :missing-call)
      (set found-missing true)))
  (assert found-missing "should include diagnostic for missing call"))

(fn slot-ownership-flags-wrong-id-not-sandbox []
  "graph-activity-unit calling ensure with 'drawing' (non-sandbox wrong id) should be flagged."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.activity-slot-ownership"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/graph-activity-unit.fnl"
                             :module "graph-activity-unit"
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 10 :column 1
                                      :form "(scene:ensure-activity-slot \"drawing\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil
                                      :method nil
                                      :line 11 :column 1
                                      :form "(scene:activate-activity-slot \"graph\")"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for wrong slot id")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var found-wrong false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.actual-arg "drawing")
      (set found-wrong true)))
  (assert found-wrong "should flag call with unexpected non-sandbox id 'drawing'"))

;; --- Rule 3: scene.sandbox-activation-contract ---

(fn sandbox-contract-passes-when-all-calls-present []
  "sandbox-activity-unit with all required calls should pass."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires [{:module "runtime.scene"
                                         :line 10 :column 1
                                         :form "(require :runtime.scene)"}]
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-surface-state!"
                                      :receiver nil :method nil
                                      :line 22 :column 1
                                      :form "(ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :scene)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) (.. "complete sandbox contract should pass, got " (if result (length result) 0) " diagnostics")))

(fn sandbox-contract-flags-missing-requires-runtime []
  "sandbox-activity-unit missing require of runtime should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires []
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-surface-state!"
                                      :receiver nil :method nil
                                      :line 22 :column 1
                                      :form "(ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :scene)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "scene.sandbox-activation-contract")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "scene-sandbox") "diagnostic should have family scene-sandbox"))

(fn sandbox-contract-flags-missing-activate-sandbox []
  "sandbox-activity-unit missing scene:activate-activity-slot call should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires [{:module "runtime.scene"
                                         :line 10 :column 1
                                         :form "(require :runtime.scene)"}]
                             :calls [{:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-surface-state!"
                                      :receiver nil :method nil
                                      :line 22 :column 1
                                      :form "(ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :scene)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn sandbox-contract-flags-missing-set-surface-state []
  "sandbox-activity-unit missing ctx:set-surface-state! call should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires [{:module "runtime.scene"
                                         :line 10 :column 1
                                         :form "(require :runtime.scene)"}]
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :scene)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn sandbox-contract-flags-wrong-require-module []
  "sandbox-activity-unit requiring 'runtime' instead of 'runtime.scene' should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires [{:module "runtime"
                                         :line 10 :column 1
                                         :form "(require :runtime)"}]
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-surface-state!"
                                      :receiver nil :method nil
                                      :line 22 :column 1
                                      :form "(ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :scene)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for wrong require module")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var found-require false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.required-require "runtime.scene")
      (set found-require true)))
  (assert found-require "should flag missing runtime.scene require"))

(fn sandbox-contract-flags-wrong-ensure-slot-id []
  "sandbox-activity-unit calling ensure-activity-slot with 'graph' should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires [{:module "runtime.scene"
                                         :line 10 :column 1
                                         :form "(require :runtime.scene)"}]
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(scene:ensure-activity-slot \"graph\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-surface-state!"
                                      :receiver nil :method nil
                                      :line 22 :column 1
                                      :form "(ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :scene)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for wrong ensure slot id")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var found-wrong false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.expected-arg "sandbox")
      (set found-wrong true)))
  (assert found-wrong "should flag call with wrong sandbox id"))

(fn sandbox-contract-flags-canvas-not-hidden []
  "sandbox-activity-unit calling set-surface-state! without canvas hidden should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires [{:module "runtime.scene"
                                         :line 10 :column 1
                                         :form "(require :runtime.scene)"}]
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-surface-state!"
                                      :receiver nil :method nil
                                      :line 22 :column 1
                                      :form "(ctx:set-surface-state! {:canvas {:visible? true}})"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :scene)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for canvas not hidden")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn sandbox-contract-flags-wrong-preferred-surface []
  "sandbox-activity-unit calling set-preferred-interaction-surface! with :canvas should produce diagnostic."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.sandbox-activation-contract"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/lua/sandbox-activity-unit.fnl"
                             :module "sandbox-activity-unit"
                             :requires [{:module "runtime.scene"
                                         :line 10 :column 1
                                         :form "(require :runtime.scene)"}]
                             :calls [{:callee "scene:ensure-activity-slot"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(scene:ensure-activity-slot \"sandbox\")"}
                                     {:callee "scene:activate-activity-slot"
                                      :receiver nil :method nil
                                      :line 21 :column 1
                                      :form "(scene:activate-activity-slot \"sandbox\")"}
                                     {:callee "ctx:set-surface-state!"
                                      :receiver nil :method nil
                                      :line 22 :column 1
                                      :form "(ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})"}
                                     {:callee "ctx:set-preferred-interaction-surface!"
                                      :receiver nil :method nil
                                      :line 23 :column 1
                                      :form "(ctx:set-preferred-interaction-surface! :canvas)"}
                                     {:callee "ctx:set-root-actions!"
                                      :receiver nil :method nil
                                      :line 24 :column 1
                                      :form "(ctx:set-root-actions! sandbox-root-actions)"}
                                     {:callee "ctx:set-target-enabled!"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(ctx:set-target-enabled! sandbox-target-enabled?)"}
                                     {:callee "ctx:set-update!"
                                      :receiver nil :method nil
                                      :line 26 :column 1
                                      :form "(ctx:set-update! sandbox-activity-update)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for wrong preferred surface")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; --- Rule 4: scene.active-render-context-routing ---

(fn active-render-context-routing-scenario []
  "Executable scenario verifies active Scene slot context supplies render vectors.
  This test requires a real app environment — the rule runner handles setup/teardown."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.active-render-context-routing"))
  (assert rule "rule should be in rules list")
  ;; The rule internally uses Scenarios.with-test-app;
  ;; the test must NOT double-wrap in with-test-app.
  ;; Call rule.run directly with a context that has the expected shape.
  (local result (rule.run {:target {:kind :repo :name :test}
                           :facts (make-fact-db [])
                           :files []}))
  ;; The scenario runs against a real test app; it returns nil on pass
  ;; or a diagnostics table on violations. Both are valid.
  (assert (or (= result nil) (= (type result) :table))
          (.. "scenario rule should return nil or a diagnostics table, got " (type result)))
  ;; Check that diagnostics (if any) have the correct family
  (when (and result (> (length result) 0))
    (each [_ d (ipairs result)]
      (assert (= d.family "scene-sandbox")
              "all diagnostics should have family scene-sandbox"))))

;; --- Rules list structure tests ---

(fn rules-returns-table-with-four-rules []
  "SceneSandbox.rules() should return a table with exactly 4 rules."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (assert (= (type rules) :table) "rules should be a table")
  (assert (= (length rules) 4) (.. "expected 4 rules, got " (length rules))))

(fn rules-have-required-structure []
  "Each rule should have :id, :family, :targets, :kind, :run, and :fn."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local expected-ids {"scene.no-legacy-world-state-scene" "static"
                       "scene.activity-slot-ownership" "static"
                       "scene.sandbox-activation-contract" "static"
                       "scene.active-render-context-routing" "scenario"})
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) (.. "rule should have string :id, got " (tostring rule.id)))
    (assert (= rule.family "scene-sandbox") "rule should have family scene-sandbox")
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (or (= rule.kind :static) (= rule.kind :scenario))
            (.. "rule kind should be static or scenario, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) (.. "rule should have :run function for id " (tostring rule.id)))
    (assert (= (type rule.fn) :function) (.. "rule should have :fn function for id " (tostring rule.id)))
    (assert (= rule.fn rule.run) (.. ":fn should alias :run for id " (tostring rule.id)))
    ;; Check expected kind for known ids
    (when (. expected-ids rule.id)
      (assert (= rule.kind (. expected-ids rule.id))
              (.. "rule " rule.id " should be kind " (. expected-ids rule.id))))))

;; Register all tests
(table.insert tests {:name "scene sandbox rules returns table with four rules"
                     :fn rules-returns-table-with-four-rules})
(table.insert tests {:name "scene sandbox rules have required structure"
                     :fn rules-have-required-structure})
(table.insert tests {:name "no-legacy-world-state-scene allows clean file"
                     :fn no-legacy-allows-clean-file})
(table.insert tests {:name "no-legacy-world-state-scene flags world.state.scene access"
                     :fn no-legacy-flags-world-state-scene-access})
(table.insert tests {:name "no-legacy-world-state-scene allows allowlisted migration files"
                     :fn no-legacy-allows-allowlisted-migration-files})
(table.insert tests {:name "activity-slot-ownership allows correct graph slot"
                     :fn slot-ownership-allows-correct-graph-slot})
(table.insert tests {:name "activity-slot-ownership flags graph using sandbox"
                     :fn slot-ownership-flags-graph-using-sandbox})
(table.insert tests {:name "activity-slot-ownership flags drawing using sandbox"
                     :fn slot-ownership-flags-drawing-using-sandbox})
(table.insert tests {:name "activity-slot-ownership flags board using sandbox"
                     :fn slot-ownership-flags-board-using-sandbox})
(table.insert tests {:name "activity-slot-ownership flags missing ensure-activity-slot call"
                     :fn slot-ownership-flags-missing-ensure-call})
(table.insert tests {:name "activity-slot-ownership flags wrong id (not sandbox)"
                     :fn slot-ownership-flags-wrong-id-not-sandbox})
(table.insert tests {:name "sandbox-activation-contract passes when all calls present"
                     :fn sandbox-contract-passes-when-all-calls-present})
(table.insert tests {:name "sandbox-activation-contract flags missing requires runtime"
                     :fn sandbox-contract-flags-missing-requires-runtime})
(table.insert tests {:name "sandbox-activation-contract flags missing activate sandbox"
                     :fn sandbox-contract-flags-missing-activate-sandbox})
(table.insert tests {:name "sandbox-activation-contract flags missing set-surface-state"
                     :fn sandbox-contract-flags-missing-set-surface-state})
(table.insert tests {:name "sandbox-activation-contract flags wrong require module"
                     :fn sandbox-contract-flags-wrong-require-module})
(table.insert tests {:name "sandbox-activation-contract flags wrong ensure slot id"
                     :fn sandbox-contract-flags-wrong-ensure-slot-id})
(table.insert tests {:name "sandbox-activation-contract flags canvas not hidden"
                     :fn sandbox-contract-flags-canvas-not-hidden})
(table.insert tests {:name "sandbox-activation-contract flags wrong preferred surface"
                     :fn sandbox-contract-flags-wrong-preferred-surface})
(table.insert tests {:name "active-render-context-routing scenario"
                     :fn active-render-context-routing-scenario})

;; --- Runner integration test: verify rules are executable by constraints.runner ---

(fn runner-rules-executable []
  "SceneSandbox.rules() entries must be executable by constraints.runner.run."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (SceneSandbox.rules))
  ;; Take only static rules (scenario rule needs special setup)
  (local static-rules [])
  (each [_ r (ipairs rules)]
    (when (= r.kind :static)
      (table.insert static-rules r)))
  (local target {:kind :repo :name :test
                 :facts (make-fact-db [(make-file-fact {:path "/test/module.fnl"
                                                        :module "test-module"
                                                        :accesses []
                                                        :calls []})])
                 :files []})
  (local result (ConstraintRunner.run {:rules static-rules :target target
                                        :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (= result.status :pass) (.. "expected :pass status, got " result.status))
  (assert (= (length result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (length result.diagnostics))))

(table.insert tests {:name "runner recognizes scene sandbox rules"
                     :fn runner-rules-executable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-scene-sandbox"
                        :tests tests})))

{:name "constraints-rules-scene-sandbox"
 :tests tests
 :main main}
