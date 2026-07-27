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

(fn mutation-restoration-allows-non-test-file []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/src/production.fnl"
                              :module "production"
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 10 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn nil}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "non-test file should skip global mutation check"))

(fn mutation-restoration-allows-test-file-with-restoration []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-with-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-with-restore []
  (let [orig app.renderers]
    (set app.renderers custom)
    (do-test)
    (set app.renderers orig)))"}]
                               :mutations [{:op :set
                                            :path ["app" "renderers"]
                                            :line 7 :column 1
                                            :form "(set app.renderers custom)"
                                            :enclosing-fn "test-with-restore"}
                                           {:op :set
                                            :path ["app" "renderers"]
                                            :line 9 :column 1
                                            :form "(set app.renderers orig)"
                                            :enclosing-fn "test-with-restore"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "test file with restoration should pass"))

(fn mutation-restoration-allows-with-restored-app-fields []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-mutate"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-mutate []
  (with-restored-app-fields [app.renderers]
    (set app.renderers custom)
    (do-test)))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-mutate"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "test file with with-restored-app-fields should pass"))

(fn mutation-restoration-allows-pcall-cleanup-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-pcall-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-pcall-restore []
  (let [orig app.renderers]
    (pcall (fn []
             (set app.renderers custom)
             (do-test))
           (set app.renderers orig))))"}]
                               :mutations [{:op :set
                                            :path ["app" "renderers"]
                                            :line 8 :column 1
                                            :form "(set app.renderers custom)"
                                            :enclosing-fn "test-pcall-restore"}
                                           {:op :set
                                            :path ["app" "renderers"]
                                            :line 10 :column 1
                                            :form "(set app.renderers orig)"
                                            :enclosing-fn "test-pcall-restore"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "test file with pcall cleanup restore should pass"))

(fn mutation-restoration-flags-test-file-without-restoration []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-bad-mutate"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn test-bad-mutate []
  (set app.renderers custom)
  (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-bad-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for mutation without restoration")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "test-isolation") "diagnostic should have family test-isolation")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence"))

(fn mutation-restoration-flags-test-file-with-package-loaded-mutation []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-mutate-package"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 80
                                             :form "(fn test-mutate-package []
  (tset package.loaded :some-module nil))"}]
                              :mutations [{:op :tset
                                           :path ["package" "loaded" "some-module"]
                                           :line 8 :column 1
                                           :form "(tset package.loaded :some-module nil)"
                                           :enclosing-fn "test-mutate-package"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for package.loaded mutation")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should have correct constraint-id"))

(fn mutation-restoration-flags-test-file-with-app-engine-mutation []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-engine"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 80
                                             :form "(fn test-engine []
  (set app.engine my-engine))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine"]
                                           :line 8 :column 1
                                           :form "(set app.engine my-engine)"
                                           :enclosing-fn "test-engine"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for app.engine mutation")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should have correct constraint-id"))

(fn mutation-restoration-flags-pcall-without-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-pcall-no-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 120
                                             :form "(fn test-pcall-no-restore []
  (pcall (fn []
    (set app.renderers custom-fn))
  (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom-fn)"
                                           :enclosing-fn "test-pcall-no-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-without-restore"))

(fn mutation-restoration-flags-repeated-mutation-without-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-double-mutate"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 120
                                             :form "(fn test-double-mutate []
  (set app.renderers custom1)
  (do-something)
  (set app.renderers custom2))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 6 :column 1
                                           :form "(set app.renderers custom1)"
                                           :enclosing-fn "test-double-mutate"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom2)"
                                           :enclosing-fn "test-double-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for repeated mutation without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag repeated-mutation-without-restore"))

(fn mutation-restoration-flags-pcall-double-mutate-no-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-pcall-double-mutate"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-pcall-double-mutate []
  (pcall (fn []
    (set app.renderers custom1)
    (set app.renderers custom2))))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 7 :column 1
                                           :form "(set app.renderers custom1)"
                                           :enclosing-fn "test-pcall-double-mutate"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom2)"
                                           :enclosing-fn "test-pcall-double-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall double-mutate without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-double-mutate-no-restore"))

(fn mutation-restoration-flags-pcall-triple-mutate-no-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-pcall-triple-mutate"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-pcall-triple-mutate []
  (pcall (fn []
    (set app.renderers custom1)
    (set app.renderers custom2)
    (set app.renderers custom3))))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 7 :column 1
                                           :form "(set app.renderers custom1)"
                                           :enclosing-fn "test-pcall-triple-mutate"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom2)"
                                           :enclosing-fn "test-pcall-triple-mutate"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 9 :column 1
                                           :form "(set app.renderers custom3)"
                                           :enclosing-fn "test-pcall-triple-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall triple-mutate without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-triple-mutate-no-restore"))

(fn mutation-restoration-flags-snapshot-two-mutations-without-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-snapshot-two-mutates"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-snapshot-two-mutates []
  (let [orig app.renderers]
    (set app.renderers custom1)
    (set app.renderers custom2)))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 7 :column 1
                                           :form "(set app.renderers custom1)"
                                           :enclosing-fn "test-snapshot-two-mutates"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom2)"
                                           :enclosing-fn "test-snapshot-two-mutates"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for snapshot+two-mutations without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag snapshot+two-mutations-without-restore"))

(fn mutation-restoration-flags-snapshot-pcall-two-mutations-without-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-pcall-snapshot-two-mutates"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-pcall-snapshot-two-mutates []
  (let [orig app.renderers]
    (pcall (fn []
      (set app.renderers custom1)
      (set app.renderers custom2)))))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom1)"
                                           :enclosing-fn "test-pcall-snapshot-two-mutates"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 9 :column 1
                                           :form "(set app.renderers custom2)"
                                           :enclosing-fn "test-pcall-snapshot-two-mutates"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for snapshot+pcall+two-mutations without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag snapshot+pcall+two-mutations-without-restore"))

(fn mutation-restoration-flags-pre-restore-then-mutate []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-pre-restore-leak"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-pre-restore-leak []
  (let [orig app.renderers]
    (set app.renderers orig)
    (do-something)
    (set app.renderers custom)))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 6 :column 1
                                           :form "(set app.renderers orig)"
                                           :enclosing-fn "test-pre-restore-leak"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-pre-restore-leak"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pre-restore then later mutation")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pre-restore-then-mutate"))

(fn mutation-restoration-flags-pcall-pre-restore-then-mutate []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-pcall-pre-restore-leak"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-pcall-pre-restore-leak []
  (let [orig app.renderers]
    (set app.renderers orig)
    (pcall (fn []
      (set app.renderers custom)))))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 6 :column 1
                                           :form "(set app.renderers orig)"
                                           :enclosing-fn "test-pcall-pre-restore-leak"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-pcall-pre-restore-leak"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall pre-restore then mutate")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-pre-restore-then-mutate"))

(fn mutation-restoration-flags-pcall-restore-inside-pcall-body []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-pcall-restore-inside-body"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-pcall-restore-inside-body []
  (let [orig app.renderers]
    (pcall (fn []
      (set app.renderers custom)
      (set app.renderers orig)))))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 7 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-pcall-restore-inside-body"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers orig)"
                                           :enclosing-fn "test-pcall-restore-inside-body"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for restore inside pcall body")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag restore-inside-pcall-body"))

(fn mutation-restoration-flags-two-pcalls-second-mutates-in-body-restore []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-two-pcalls-in-body-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 250
                                             :form "(fn test-two-pcalls-in-body-restore []
  (let [orig app.renderers]
    (pcall (fn [] (do-unrelated)))
    (pcall (fn []
      (set app.renderers custom)
      (set app.renderers orig)))))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 9 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-two-pcalls-in-body-restore"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 10 :column 1
                                           :form "(set app.renderers orig)"
                                           :enclosing-fn "test-two-pcalls-in-body-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for two pcalls with in-body restore in second")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag two-pcalls-second-in-body-restore"))

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
;; Rules list structure tests
;; ======================================================================

(fn test-isolation-rules-returns-table-with-one-rule []
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (assert (= (type rules) :table) "rules should be a table")
  (assert (= (length rules) 1) (.. "expected 1 rule, got " (length rules))))

(fn test-isolation-rules-have-required-structure []
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) (.. "rule should have string :id, got " (tostring rule.id)))
    (assert (= rule.family "test-isolation") "rule should have family test-isolation")
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (= rule.kind :static) (.. "rule should be kind static, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) (.. "rule should have :run function for id " (tostring rule.id)))
    (assert (= (type rule.fn) :function) (.. "rule should have :fn function for id " (tostring rule.id)))
    (assert (= rule.fn rule.run) (.. ":fn should alias :run for id " (tostring rule.id)))))

;; ======================================================================
;; Runner integration test
;; ======================================================================

(fn test-isolation-runner-executable []
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (TestIsolation.rules))
  (local target {:kind :repo :name :test
                 :facts (make-fact-db [(make-file-fact {:path "/test/clean.fnl"
                                                        :module "test-clean"
                                                        :accesses []
                                                        :mutations []})])
                 :files []})
  (local result (ConstraintRunner.run {:rules rules :target target :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (= result.status :pass) (.. "expected :pass status, got " result.status))
  (assert (= (length result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (length result.diagnostics))))

;; ======================================================================
;; Register all tests
;; ======================================================================

(table.insert tests {:name "mutation-restoration allows non-test file" :fn mutation-restoration-allows-non-test-file})
(table.insert tests {:name "mutation-restoration allows test file with restoration" :fn mutation-restoration-allows-test-file-with-restoration})
(table.insert tests {:name "mutation-restoration allows with-restored-app-fields" :fn mutation-restoration-allows-with-restored-app-fields})
(table.insert tests {:name "mutation-restoration allows pcall cleanup restore" :fn mutation-restoration-allows-pcall-cleanup-restore})
(table.insert tests {:name "mutation-restoration flags test file without restoration" :fn mutation-restoration-flags-test-file-without-restoration})
(table.insert tests {:name "mutation-restoration flags package.loaded mutation" :fn mutation-restoration-flags-test-file-with-package-loaded-mutation})
(table.insert tests {:name "mutation-restoration flags app.engine mutation" :fn mutation-restoration-flags-test-file-with-app-engine-mutation})
(table.insert tests {:name "mutation-restoration flags pcall without restore" :fn mutation-restoration-flags-pcall-without-restore})
(table.insert tests {:name "mutation-restoration flags repeated mutation without restore" :fn mutation-restoration-flags-repeated-mutation-without-restore})
(table.insert tests {:name "mutation-restoration flags pcall double-mutate without restore" :fn mutation-restoration-flags-pcall-double-mutate-no-restore})
(table.insert tests {:name "mutation-restoration flags pcall triple-mutate without restore" :fn mutation-restoration-flags-pcall-triple-mutate-no-restore})
(table.insert tests {:name "mutation-restoration flags snapshot+two-mutations without restore" :fn mutation-restoration-flags-snapshot-two-mutations-without-restore})
(table.insert tests {:name "mutation-restoration flags snapshot+pcall+two-mutations without restore" :fn mutation-restoration-flags-snapshot-pcall-two-mutations-without-restore})
(table.insert tests {:name "mutation-restoration flags pre-restore then mutate" :fn mutation-restoration-flags-pre-restore-then-mutate})
(table.insert tests {:name "mutation-restoration flags pcall pre-restore then mutate" :fn mutation-restoration-flags-pcall-pre-restore-then-mutate})
(table.insert tests {:name "mutation-restoration flags pcall restore inside pcall body" :fn mutation-restoration-flags-pcall-restore-inside-pcall-body})
(table.insert tests {:name "mutation-restoration flags two pcalls second in-body restore" :fn mutation-restoration-flags-two-pcalls-second-mutates-in-body-restore})
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
(table.insert tests {:name "test-isolation rules returns table with one rule" :fn test-isolation-rules-returns-table-with-one-rule})
(table.insert tests {:name "test-isolation rules have required structure" :fn test-isolation-rules-have-required-structure})
(table.insert tests {:name "test-isolation rules executable by runner" :fn test-isolation-runner-executable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-test-isolation" :tests tests})))

{:name "constraints-rules-test-isolation" :tests tests :main main}
