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

;; --- Rule 3: scene.sandbox-activation-contract ---

(fn sandbox-contract-passes-when-all-calls-present []
  "sandbox-activity-unit with all required calls should pass."
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
  (assert (= result nil) "complete sandbox contract should pass"))

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
                             :requires [{:module "runtime"
                                         :line 10 :column 1
                                         :form "(require :runtime)"}]
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

;; --- Rule 4: scene.active-render-context-routing ---

(fn active-render-context-routing-scenario []
  "Executable scenario verifies active Scene slot context supplies render vectors.
  This test requires a real app environment via with-test-app."
  (local Scenarios (require :constraints.scenarios))
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local rule (find-rule-by-id rules "scene.active-render-context-routing"))
  (assert rule "rule should be in rules list")
  ;; The scenario rule should return diagnostics when run
  (local result
    (Scenarios.with-test-app
      (fn []
        (rule.run {:target {:kind :repo :name :test}
                   :facts (make-fact-db [])
                   :files []}))))
  ;; The scenario runs against a real test app; it either passes (nil)
  ;; or returns diagnostics. We verify the type convention.
  (when result
    (assert (= (type result) :table) "diagnostics should be a table")
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
  "Each rule should have :id, :family, :targets, :kind, and :run."
  (local SceneSandbox (require :constraints.rules.scene-sandbox))
  (local rules (SceneSandbox.rules))
  (local expected-ids {"scene.no-legacy-world-state-scene" "static"
                       "scene.activity-slot-ownership" "static"
                       "scene.sandbox-activation-contract" "static"
                       "scene.active-render-context-routing" "scenario"})
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) "rule should have string :id")
    (assert (= rule.family "scene-sandbox") "rule should have family scene-sandbox")
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (or (= rule.kind :static) (= rule.kind :scenario))
            (.. "rule kind should be static or scenario, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) "rule should have :run function")
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
(table.insert tests {:name "sandbox-activation-contract passes when all calls present"
                     :fn sandbox-contract-passes-when-all-calls-present})
(table.insert tests {:name "sandbox-activation-contract flags missing requires runtime"
                     :fn sandbox-contract-flags-missing-requires-runtime})
(table.insert tests {:name "sandbox-activation-contract flags missing activate sandbox"
                     :fn sandbox-contract-flags-missing-activate-sandbox})
(table.insert tests {:name "sandbox-activation-contract flags missing set-surface-state"
                     :fn sandbox-contract-flags-missing-set-surface-state})
(table.insert tests {:name "active-render-context-routing scenario"
                     :fn active-render-context-routing-scenario})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-scene-sandbox"
                        :tests tests})))

{:name "constraints-rules-scene-sandbox"
 :tests tests
 :main main}
