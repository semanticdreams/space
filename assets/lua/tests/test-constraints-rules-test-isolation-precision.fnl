;; Tests for Test-Isolation constraint rules (lifecycle.global-mutation-restoration).

(local tests [])

;; --- Helpers for constructing synthetic fact DBs ---

(fn make-file-fact [opts]
  "Create a synthetic file-fact record for testing rule functions."
  (local o (if opts opts {}))
  {:target (if o.target o.target {:kind :repo :name :test})
   :path (if o.path o.path "/test/module.fnl")
   :module (if o.module o.module "test-module")
   :requires (if o.requires o.requires [])
   :definitions (if o.definitions o.definitions [])
   :exports (if o.exports o.exports [])
   :calls (if o.calls o.calls [])
   :accesses (if o.accesses o.accesses [])
   :mutations (if o.mutations o.mutations [])
   :metrics (if o.metrics o.metrics {:module-lines 0
                                      :max-nesting-depth 0
                                      :max-anonymous-callback-depth 0
                                      :max-table-literal-size 0
                                      :functions []})})

(fn make-fact-db [file-facts]
  (local by-file {})
  (each [_ ff (ipairs file-facts)]
    (tset by-file ff.path ff))
  {:files file-facts
   :by-file by-file})

(fn make-ctx [file-facts]
  {:target {:kind :repo :name :test}
   :facts (make-fact-db file-facts)
   :files []})

(fn find-rule-by-id [rules id]
  (var found nil)
  (each [_ r (ipairs rules)]
    (when (= r.id id)
      (set found r)))
  found)

(fn get-test-isolation-rule []
  "Get the lifecycle.global-mutation-restoration rule from test-isolation."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule lifecycle.global-mutation-restoration should be in rules list")
  rule)

;; ======================================================================
;; lifecycle.global-mutation-restoration (test-isolation)
;; ======================================================================

;; ======================================================================
;; Precision: wrapper anonymous fn restoration (with-restored-app-fields)
;; ======================================================================

(fn mutation-restoration-allows-anonymous-fn-wrapped-by-restore-fields []
  "Mutation inside anonymous fn inside with-restored-app-fields wrapper should pass."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-wrapper-restore"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 200
                                             :form "(fn test-wrapper-restore []
  (with-restored-app-fields [:engine :renderers]
    (fn []
      (set app.engine new-engine)
      (set app.renderers custom))))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 13 :column 1
                                             :length 80
                                             :form "(fn []
      (set app.engine new-engine)
      (set app.renderers custom))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 14 :column 1
                                           :form "(set app.engine new-engine)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 15 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "<anonymous>"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "anonymous fn mutation wrapped by with-restored-app-fields in parent should pass"))

(fn mutation-restoration-flags-anonymous-fn-without-wrapper []
  "Mutation inside anonymous fn without any wrapper should still be flagged."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-no-wrapper"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 150
                                             :form "(fn test-no-wrapper []
  (fn []
    (set app.engine new-engine)
    (set app.renderers custom))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 12 :column 1
                                           :form "(set app.engine new-engine)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag anonymous fn mutation without wrapper")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; ======================================================================
;; Precision: snapshot/restore helper pair
;; ======================================================================

(fn mutation-restoration-allows-snapshot-restore-helper-pair []
  "Test functions using snapshot-app-fields + restore-app-fields! helpers should pass."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-snapshot-helper-pair"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-snapshot-helper-pair []
  (local app-keys [:activity-registry :engine])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.engine custom-engine)
  (do-test)
  (restore-app-fields! app-snapshot))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 8 :column 1
                                           :form "(set app.activity-registry nil)"
                                           :enclosing-fn "test-snapshot-helper-pair"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 9 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "test-snapshot-helper-pair"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "snapshot-app-fields + restore-app-fields! helper pair should pass"))

(fn mutation-restoration-flags-snapshot-helper-without-restore []
  "Test with snapshot-app-fields but without restore-app-fields! should be flagged."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-snapshot-no-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-snapshot-no-restore []
  (local app-keys [:activity-registry])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 8 :column 1
                                           :form "(set app.activity-registry nil)"
                                           :enclosing-fn "test-snapshot-no-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag snapshot helper without restore call")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; ======================================================================
;; Precision: definition matching by line range for anonymous functions
;; ======================================================================

(fn mutation-restoration-matches-anonymous-def-by-line []
  "Multiple anonymous fns in a file: should match the correct one by line containment."
  (local rule (get-test-isolation-rule))
  ;; File has two anonymous fns; the first has restoration, the second doesn't.
  ;; The mutation is in the second, so it should be flagged.
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 5 :column 1
                                             :length 80
                                             :form "(fn []
  (let [orig app.renderers]
    (set app.renderers custom1)
    (set app.renderers orig)))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 15 :column 1
                                             :length 50
                                             :form "(fn []
  (set app.engine custom-engine))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 16 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag mutation in anonymous fn at line 16 without restoration")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; ======================================================================
;; Precision: setup/harness narrow exemption
;; ======================================================================

(fn mutation-restoration-allows-setup-test-env-in-runner []
  "setup-test-env in runner.fnl is test infrastructure, not per-test mutation."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/home/user/project/assets/lua/tests/runner.fnl"
                              :module "tests.runner"
                              :definitions [{:kind :fn
                                             :name "setup-test-env"
                                             :top-level? true
                                             :line 100 :column 1
                                             :length 200
                                             :form "(fn setup-test-env [verbose]
  (set app.engine (Engine {}))
  (set app.lights (LightSystem {})))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 102 :column 1
                                           :form "(set app.engine (Engine {}))"
                                           :enclosing-fn "setup-test-env"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "setup-test-env in runner.fnl should be exempt from test-isolation check"))

(fn mutation-restoration-allows-init-test-app-in-harness []
  "init-test-app in e2e/harness.fnl is test infrastructure, not per-test mutation."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/home/user/project/assets/lua/tests/e2e/harness.fnl"
                              :module "tests.e2e.harness"
                              :definitions [{:kind :fn
                                             :name "init-test-app"
                                             :top-level? true
                                             :line 50 :column 1
                                             :length 100
                                             :form "(fn init-test-app []
  (set app.engine (Engine {:headless true}))
  (set app.engine.audio {}))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 52 :column 1
                                           :form "(set app.engine (Engine {:headless true}))"
                                           :enclosing-fn "init-test-app"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "init-test-app in e2e/harness.fnl should be exempt from test-isolation check"))

(fn mutation-restoration-flags-setup-like-fn-in-other-file []
  "A setup-like function in a non-infrastructure file should still be flagged."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/home/user/project/assets/lua/tests/test-something.fnl"
                              :module "tests.test-something"
                              :definitions [{:kind :fn
                                             :name "setup-test-env"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 100
                                             :form "(fn setup-test-env []
  (set app.engine (Engine {})))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 12 :column 1
                                           :form "(set app.engine (Engine {}))"
                                           :enclosing-fn "setup-test-env"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag setup-test-env in non-runner file")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; ======================================================================
;; R1-1: anonymous grouping should not collapse distinct anonymous fns
;; ======================================================================

(fn mutation-restoration-flags-first-anon-mutation-when-second-restores []
  "R1-1: Two anonymous functions mutating the same path. The first leaks,
   the second restores. The leaking one should still be diagnosed."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-two-anon"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 250
                                             :form "(fn test-two-anon []
  (fn [] (set app.engine leaky-engine))
  (fn [] (let [orig app.engine] (set app.engine new-engine) (set app.engine orig))))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 6 :column 1
                                             :length 50
                                             :form "(fn [] (set app.engine leaky-engine))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 7 :column 1
                                             :length 80
                                             :form "(fn [] (let [orig app.engine] (set app.engine new-engine) (set app.engine orig)))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 6 :column 1
                                           :form "(set app.engine leaky-engine)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 7 :column 1
                                           :form "(set app.engine new-engine)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 7 :column 2
                                           :form "(set app.engine orig)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for the first leaking anonymous mutation")
  (assert (> (length result) 0) "should have at least one diagnostic for the leak"))

;; ======================================================================
;; R1-2: snapshot/restore helper pair must be order-aware
;; ======================================================================

(fn mutation-restoration-flags-helper-restore-before-mutation []
  "R1-2: A function that calls snapshot-app-fields and restore-app-fields!
   before the sensitive mutation should still be flagged."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-restore-before-mutate"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-restore-before-mutate []
  (local app-snapshot (snapshot-app-fields [:activity-registry :engine]))
  (restore-app-fields! app-snapshot)
  (set app.activity-registry nil)
  (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 9 :column 1
                                           :form "(set app.activity-registry nil)"
                                           :enclosing-fn "test-restore-before-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag mutation when restore happens before it")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; ======================================================================
;; R1-3: parent wrapper must contain the mutation, not just same parent
;; ======================================================================

(fn mutation-restoration-flags-sibling-anon-not-inside-wrapper []
  "R1-3: Parent function with with-restored-app-fields around one callback,
   but a separate sibling anonymous fn mutates without being wrapped.
   The unwrapped sibling should still be flagged."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-sibling-wrapper"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 250
                                             :form "(fn test-sibling-wrapper []
  (with-restored-app-fields [:renderers]
    (fn [] (set app.renderers custom-renderer)))
  (fn [] (set app.engine custom-engine)))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 12 :column 1
                                             :length 60
                                             :form "(fn [] (set app.renderers custom-renderer))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 15 :column 1
                                             :length 60
                                             :form "(fn [] (set app.engine custom-engine))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 12 :column 1
                                           :form "(set app.renderers custom-renderer)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 15 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for unwrapped sibling anonymous mutation")
  (local engine-diags [])
  (each [_ d (ipairs result)]
    (when (and d.evidence (= d.evidence.global-path "app.engine"))
      (table.insert engine-diags d)))
  (assert (> (length engine-diags) 0)
          "unwrapped app.engine sibling mutation should be flagged"))

;; ======================================================================
;; R1-1 round2: same-line anonymous fns must be distinct
;; ======================================================================

(fn mutation-restoration-flags-same-line-anon-leak-when-same-line-restores []
  "R1-1 round2: Two anonymous functions on the same line mutating the same path.
   One leaks, one restores (in a pcall). They must not collapse into one group."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-same-line-anons"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 200
                                             :form "(fn test-same-line-anons []
  (fn [] (set app.engine leaky)) (fn [] (let [orig app.engine] (set app.engine new) (set app.engine orig))))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 11 :column 3
                                             :length 30
                                             :form "(fn [] (set app.engine leaky))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 11 :column 30
                                             :length 70
                                             :form "(fn [] (let [orig app.engine] (set app.engine new) (set app.engine orig)))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 10
                                           :form "(set app.engine leaky)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 55
                                           :form "(set app.engine new)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 70
                                           :form "(set app.engine orig)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for the first leaking anon on same line")
  (assert (> (length result) 0) "should have at least one diagnostic for the same-line leak"))

;; ======================================================================
;; R1-2 round2: snapshot helper must cover the mutated path
;; ======================================================================

(fn mutation-restoration-flags-snapshot-with-unrelated-keys []
  "R1-2 round2: snapshot-app-fields covers only :renderers, but mutation
   is on app.activity-registry. Rule should still flag the mutation."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-unrelated-snapshot"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-unrelated-snapshot []
  (local snap (snapshot-app-fields [:renderers :engine]))
  (set app.activity-registry nil)
  (restore-app-fields! snap))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 8 :column 1
                                           :form "(set app.activity-registry nil)"
                                           :enclosing-fn "test-unrelated-snapshot"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag mutation when snapshot covers unrelated keys")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn mutation-restoration-allows-snapshot-covering-path []
  "Snapshot covers app.engine, mutation is on app.engine subfield.
   Restoration should be accepted."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-covered-snapshot"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-covered-snapshot []
  (local snap (snapshot-app-fields [:engine]))
  (set app.engine custom-engine)
  (restore-app-fields! snap))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 8 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "test-covered-snapshot"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "snapshot covering app.engine with app.engine mutation should pass"))

;; ======================================================================
;; R1-3 round2: identical anonymous form text, different positions
;; ======================================================================

(fn mutation-restoration-flags-identical-anon-form-not-inside-wrapper []
  "R1-3 round2: Two anonymous fns with identical form text.
   One is wrapped by with-restored-app-fields, the other is a sibling.
   The unwrapped sibling must still be flagged."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-identical-anons"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 250
                                             :form "(fn test-identical-anons []
  (with-restored-app-fields [:engine] (fn mut [] (set app.engine wrapped)))
  (fn mut [] (set app.engine unwrapped)))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 11 :column 40
                                             :length 50
                                             :form "(fn mut [] (set app.engine wrapped))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 12 :column 3
                                             :length 50
                                             :form "(fn mut [] (set app.engine unwrapped))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 50
                                           :form "(set app.engine wrapped)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 12 :column 10
                                           :form "(set app.engine unwrapped)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for unwrapped identical-form sibling")
  (local engine-diags [])
  (each [_ d (ipairs result)]
    (when (and d.evidence (= d.evidence.global-path "app.engine"))
      (table.insert engine-diags d)))
  (assert (> (length engine-diags) 0)
          "unwrapped identical-form sibling should be flagged"))

;; ======================================================================
;; V1-1: variable-key with-restored-app-fields
;; ======================================================================

(fn mutation-restoration-allows-variable-key-wraf-wrapper []
  "V1-1: with-restored-app-fields with variable key list (not literal vector).
   The anonymous fn inside the wrapper should be recognized as properly restored."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-var-key-wrapper"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 200
                                             :form "(fn test-var-key-wrapper []
  (with-restored-app-fields bind-state-keys
    (fn []
      (set app.engine custom-engine)
      (set app.renderers custom))))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 13 :column 1
                                             :length 80
                                             :form "(fn []
      (set app.engine custom-engine)
      (set app.renderers custom))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 14 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 15 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "<anonymous>"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "variable-key with-restored-app-fields wrapper should be recognized"))

;; ======================================================================
;; V2-1: same-line anonymous, column-aware definition matching
;; ======================================================================

(fn mutation-restoration-flags-same-line-leak-when-first-restores []
  "V2-1: Two same-line anonymous fns. First restores app.engine,
   second leaks app.engine. Column-aware grouping must not collapse them."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-same-line-reverse"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 200
                                             :form "(fn test-same-line-reverse []
  (fn [] (let [orig app.engine] (set app.engine new) (set app.engine orig))) (fn [] (set app.engine leaky)))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 11 :column 3
                                             :length 70
                                             :form "(fn [] (let [orig app.engine] (set app.engine new) (set app.engine orig)))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 11 :column 75
                                             :length 30
                                             :form "(fn [] (set app.engine leaky))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 20
                                           :form "(set app.engine new)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 50
                                           :form "(set app.engine orig)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 85
                                           :form "(set app.engine leaky)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for leaking anon when first restores")
  (assert (> (length result) 0) "should have at least one diagnostic for the same-line leak"))

;; ======================================================================
;; V2-2: parent wrapper column-adjusted byte position
;; ======================================================================

(fn mutation-restoration-flags-same-line-sibling-outside-wrapper []
  "V2-2: Parent wraps one anon, sibling anon on same line outside wrapper.
   Column-adjusted byte position must correctly place sibling outside."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-same-line-sibling"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 200
                                             :form "(fn test-same-line-sibling []
  (with-restored-app-fields [:engine] (fn [] (set app.engine wrapped))) (fn [] (set app.engine unwrapped)))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 11 :column 40
                                             :length 40
                                             :form "(fn [] (set app.engine wrapped))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 11 :column 82
                                             :length 40
                                             :form "(fn [] (set app.engine unwrapped))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 48
                                           :form "(set app.engine wrapped)"
                                           :enclosing-fn "<anonymous>"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 11 :column 90
                                           :form "(set app.engine unwrapped)"
                                           :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for same-line unwrapped sibling")
  (local engine-diags [])
  (each [_ d (ipairs result)]
    (when (and d.evidence (= d.evidence.global-path "app.engine"))
      (table.insert engine-diags d)))
  (assert (> (length engine-diags) 0)
          "unwrapped same-line sibling should be flagged"))

;; ======================================================================
;; V2-3: snapshot subpath coverage and variable key resolution
;; ======================================================================

(fn mutation-restoration-allows-snapshot-covering-subpath []
  "V2-3: snapshot [:engine] should cover app.engine.audio (subpath coverage)."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-subpath-coverage"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-subpath-coverage []
  (local snap (snapshot-app-fields [:engine]))
  (set app.engine.audio mock-audio)
  (restore-app-fields! snap))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "audio"]
                                           :line 8 :column 1
                                           :form "(set app.engine.audio mock-audio)"
                                           :enclosing-fn "test-subpath-coverage"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "snapshot [:engine] should cover app.engine.audio subpath"))

(fn mutation-restoration-flags-variable-key-snapshot-missing-field []
  "V2-3: Variable key list [:activity-registry] should be resolved from local;
   mutating app.engine (not in the resolved keys) should still be flagged."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-var-key-missing"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-var-key-missing []
  (local my-keys [:activity-registry])
  (local snap (snapshot-app-fields my-keys))
  (set app.engine custom-engine)
  (restore-app-fields! snap))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 9 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "test-var-key-missing"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag engine mutation when variable keys only cover activity-registry")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; ======================================================================
;; V3-1: two snapshots / non-restored covering snapshot
;; ======================================================================

(fn mutation-restoration-flags-two-snapshots-non-restored-covering []
  "V3-1: Two snapshots: s1 covers [:renderers], s2 covers [:engine].
   Mutate app.engine, then restore s1 (which does NOT cover engine).
   The rule should flag this because the restored snapshot doesn't cover the mutated path."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-two-snap-nonrestored-covering"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-two-snap-nonrestored-covering []
  (local s1 (snapshot-app-fields [:renderers]))
  (local s2 (snapshot-app-fields [:engine]))
  (set app.engine custom-engine)
  (restore-app-fields! s1))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 9 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "test-two-snap-nonrestored-covering"}]}))
  (local result (rule.run (make-ctx [ff])))
   (assert result "should flag engine mutation when only non-covering snapshot is restored")
   (assert (> (length result) 0) "should have at least one diagnostic for non-restored covering snapshot"))

;; ======================================================================
;; V4-1: any covering snapshot restore accepted
;; ======================================================================

(fn mutation-restoration-allows-later-covering-snapshot-restore []
  "V4-1: Two snapshots both covering app.engine (s1 and s2).
   Only the later one (s2) is restored after mutation.
   This should pass because any covering snapshot var, when restored, is accepted."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-two-covering-snaps"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-two-covering-snaps []
  (local s1 (snapshot-app-fields [:engine]))
  (local s2 (snapshot-app-fields [:engine]))
  (set app.engine custom-engine)
  (restore-app-fields! s2))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 9 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "test-two-covering-snaps"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "V4-1: restore of any covering snapshot after mutation should pass"))

;; ======================================================================
;; R2-1: mixed literal+variable-key snapshot coverage
;; ======================================================================

(fn mutation-restoration-allows-mixed-literal-variable-key-snapshot-restore []
  "R2-1: Two snapshots: s1 literal [:engine], s2 via variable keys [:engine].
   Mutate app.engine, restore only s2. Should pass because s2 covers engine
   and any covering var when restored is accepted."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-mixed-snapshot"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-mixed-snapshot []
  (local s1 (snapshot-app-fields [:engine]))
  (local keys [:engine])
  (local s2 (snapshot-app-fields keys))
  (set app.engine custom-engine)
  (restore-app-fields! s2))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 10 :column 1
                                           :form "(set app.engine custom-engine)"
                                           :enclosing-fn "test-mixed-snapshot"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "R2-1: restore of variable-key snapshot covering engine should pass when literal also exists"))

;; ======================================================================
;; R2-2: named-function with-restored-app-fields containment
;; ======================================================================

(fn mutation-restoration-flags-named-mutation-outside-wrapper []
  "R2-2: Named function with with-restored-app-fields wrapper, but mutation
   is textually outside the wrapper body. Should be diagnosed.
   Previously broad substring check exempted the entire function."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-outside-wrapper"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-outside-wrapper []
  (with-restored-app-fields [:engine]
    (set app.engine wrapped))
  (set app.engine leaky))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 8 :column 1
                                           :form "(set app.engine wrapped)"
                                           :enclosing-fn "test-outside-wrapper"}
                                          {:op :set
                                           :path ["app" "engine"]
                                           :line 10 :column 1
                                           :form "(set app.engine leaky)"
                                           :enclosing-fn "test-outside-wrapper"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "R2-2: mutation outside wraf body should be diagnosed")
  (assert (> (length result) 0) "should have at least one diagnostic for outside-wrapper mutation"))

;; ======================================================================
;; R2-3: same-line restore-before-mutation byte-aware ordering
;; ======================================================================

(fn mutation-restoration-flags-same-line-helper-restore-before-mutation []
  "R2-3: Helper restore before same-line mutation should be flagged.
   Byte-based comparison must detect restore is textually before the mutation."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-same-line-helper"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-same-line-helper []
  (local snap (snapshot-app-fields [:engine]))
  (restore-app-fields! snap) (set app.engine custom))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 7 :column 31
                                           :form "(set app.engine custom)"
                                           :enclosing-fn "test-same-line-helper"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "R2-3: helper restore before same-line mutation should be flagged")
  (assert (> (length result) 0) "should have at least one diagnostic for same-line helper leak"))

(fn mutation-restoration-flags-same-line-direct-restore-before-mutation []
  "R2-3: Direct concrete restore before same-line mutation should be flagged.
   Byte-based comparison must detect restore is textually before the mutation."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-same-line-direct"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-same-line-direct []
  (let [orig app.renderers]
    (set app.renderers orig) (set app.renderers custom)))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 7 :column 30
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-same-line-direct"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "R2-3: direct restore before same-line mutation should be flagged")
  (assert (> (length result) 0) "should have at least one diagnostic for same-line direct leak"))


;; ======================================================================
;; Register all precision tests
;; ======================================================================

(table.insert tests {:name "mutation-restoration allows anonymous fn wrapped by restore fields" :fn mutation-restoration-allows-anonymous-fn-wrapped-by-restore-fields})
(table.insert tests {:name "mutation-restoration flags anonymous fn without wrapper" :fn mutation-restoration-flags-anonymous-fn-without-wrapper})
(table.insert tests {:name "mutation-restoration allows snapshot restore helper pair" :fn mutation-restoration-allows-snapshot-restore-helper-pair})
(table.insert tests {:name "mutation-restoration flags snapshot helper without restore" :fn mutation-restoration-flags-snapshot-helper-without-restore})
(table.insert tests {:name "mutation-restoration matches anonymous def by line" :fn mutation-restoration-matches-anonymous-def-by-line})
(table.insert tests {:name "mutation-restoration allows setup-test-env in runner" :fn mutation-restoration-allows-setup-test-env-in-runner})
(table.insert tests {:name "mutation-restoration allows init-test-app in harness" :fn mutation-restoration-allows-init-test-app-in-harness})
(table.insert tests {:name "mutation-restoration flags setup-like fn in other file" :fn mutation-restoration-flags-setup-like-fn-in-other-file})
(table.insert tests {:name "R1-1 flags first anon leak when second restores" :fn mutation-restoration-flags-first-anon-mutation-when-second-restores})
(table.insert tests {:name "R1-2 flags helper restore before mutation" :fn mutation-restoration-flags-helper-restore-before-mutation})
(table.insert tests {:name "R1-3 flags sibling anon not inside wrapper" :fn mutation-restoration-flags-sibling-anon-not-inside-wrapper})
(table.insert tests {:name "R1-1r2 flags same-line anon leak" :fn mutation-restoration-flags-same-line-anon-leak-when-same-line-restores})
(table.insert tests {:name "R1-2r2 flags snapshot with unrelated keys" :fn mutation-restoration-flags-snapshot-with-unrelated-keys})
(table.insert tests {:name "R1-2r2 allows snapshot covering path" :fn mutation-restoration-allows-snapshot-covering-path})
(table.insert tests {:name "R1-3r2 flags identical-form sibling" :fn mutation-restoration-flags-identical-anon-form-not-inside-wrapper})
(table.insert tests {:name "V1-1 allows variable-key wraf wrapper" :fn mutation-restoration-allows-variable-key-wraf-wrapper})
(table.insert tests {:name "V2-1 flags same-line leak when first restores" :fn mutation-restoration-flags-same-line-leak-when-first-restores})
(table.insert tests {:name "V2-2 flags same-line sibling outside wrapper" :fn mutation-restoration-flags-same-line-sibling-outside-wrapper})
(table.insert tests {:name "V2-3 allows snapshot covering subpath" :fn mutation-restoration-allows-snapshot-covering-subpath})
(table.insert tests {:name "V2-3 flags var-key snapshot missing field" :fn mutation-restoration-flags-variable-key-snapshot-missing-field})
(table.insert tests {:name "V3-1 flags two snapshots non-restored covering" :fn mutation-restoration-flags-two-snapshots-non-restored-covering})
(table.insert tests {:name "V4-1 allows later covering snapshot restore" :fn mutation-restoration-allows-later-covering-snapshot-restore})
(table.insert tests {:name "R2-1 allows mixed literal+variable-key snapshot restore" :fn mutation-restoration-allows-mixed-literal-variable-key-snapshot-restore})
(table.insert tests {:name "R2-2 flags named mutation outside wrapper" :fn mutation-restoration-flags-named-mutation-outside-wrapper})
(table.insert tests {:name "R2-3 flags same-line helper restore before mutation" :fn mutation-restoration-flags-same-line-helper-restore-before-mutation})
(table.insert tests {:name "R2-3 flags same-line direct restore before mutation" :fn mutation-restoration-flags-same-line-direct-restore-before-mutation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-test-isolation-precision" :tests tests})))

{:name "constraints-rules-test-isolation-precision" :tests tests :main main}
