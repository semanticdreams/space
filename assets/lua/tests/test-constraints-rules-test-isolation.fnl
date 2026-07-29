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
;; Precision: hyphenated path (e.g. app.activity-registry) restore detection
;; ======================================================================

(fn mutation-restoration-allows-hyphenated-path-restore []
  "hyphenated path app.activity-registry: snapshot + mutate + restore = no diagnostic."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-hyphen-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-hyphen-restore []
  (local prev app.activity-registry)
  (set app.activity-registry nil)
  (do-test)
  (set app.activity-registry prev))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 8 :column 1
                                           :form "(set app.activity-registry nil)"
                                           :enclosing-fn "test-hyphen-restore"}
                                          {:op :set
                                           :path ["app" "activity-registry"]
                                           :line 10 :column 1
                                           :form "(set app.activity-registry prev)"
                                           :enclosing-fn "test-hyphen-restore"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "hyphenated path with snapshot+mutate+restore should pass"))

(fn mutation-restoration-flags-hyphenated-path-no-restore []
  "hyphenated path app.activity-registry: mutation without restore should still flag."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-hyphen-no-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn test-hyphen-no-restore []
  (set app.activity-registry nil)
  (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 7 :column 1
                                           :form "(set app.activity-registry nil)"
                                           :enclosing-fn "test-hyphen-no-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag hyphenated path mutation without restore")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn mutation-restoration-flags-unrelated-rhs-hyphenated-path []
  "hyphenated path app.activity-registry: restore RHS must match snapshot var."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-unrelated-rhs"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn test-unrelated-rhs []
  (local prev app.activity-registry)
  (set app.activity-registry some-other-var)
  (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 8 :column 1
                                           :form "(set app.activity-registry some-other-var)"
                                           :enclosing-fn "test-unrelated-rhs"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag when RHS does not match snapshot var")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn mutation-restoration-flags-restore-before-later-mutation-hyphenated-path []
  "Restore before a later non-restore mutation should still flag."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-restore-before-mutate"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-restore-before-mutate []
  (local prev app.activity-registry)
  (set app.activity-registry prev)
  (do-test)
  (set app.activity-registry custom))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 7 :column 1
                                           :form "(set app.activity-registry prev)"
                                           :enclosing-fn "test-restore-before-mutate"}
                                          {:op :set
                                           :path ["app" "activity-registry"]
                                           :line 9 :column 1
                                           :form "(set app.activity-registry custom)"
                                           :enclosing-fn "test-restore-before-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag when later mutation follows restore")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn mutation-restoration-allows-multi-nonrestore-then-restore-hyphenated []
  "Multiple non-restore mutations then restore after last = no diagnostic."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-multi-mutate-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-multi-mutate-restore []
  (local prev app.activity-registry)
  (set app.activity-registry custom1)
  (set app.activity-registry custom2)
  (set app.activity-registry prev))"}]
                              :mutations [{:op :set
                                           :path ["app" "activity-registry"]
                                           :line 7 :column 1
                                           :form "(set app.activity-registry custom1)"
                                           :enclosing-fn "test-multi-mutate-restore"}
                                          {:op :set
                                           :path ["app" "activity-registry"]
                                           :line 8 :column 1
                                           :form "(set app.activity-registry custom2)"
                                           :enclosing-fn "test-multi-mutate-restore"}
                                          {:op :set
                                           :path ["app" "activity-registry"]
                                           :line 9 :column 1
                                           :form "(set app.activity-registry prev)"
                                           :enclosing-fn "test-multi-mutate-restore"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "multiple non-restore mutations then restore after last should pass"))

;; ======================================================================
;; (and ...) nil-guarded snapshot tests
;; ======================================================================

(fn mutation-restoration-allows-and-guarded-subpath-snapshot []
  "Positive: (and app.engine app.engine.width) snapshot + pcall mutate + restore after pcall passes."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-and-subpath"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-and-subpath []
  (local orig (and app.engine app.engine.width))
  (pcall (fn []
    (set app.engine.width 100)))
  (set app.engine.width orig))"}]
                               :mutations [{:op :set
                                            :path ["app" "engine" "width"]
                                            :line 8 :column 1
                                            :form "(set app.engine.width 100)"
                                            :enclosing-fn "test-and-subpath"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "guarded subpath (and app.engine app.engine.width) snapshot + pcall restore should pass"))

(fn mutation-restoration-allows-and-guarded-whole-object-snapshot []
  "Positive: (and app app.engine) whole-object snapshot + pcall mutate + restore after pcall passes."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-and-whole"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-and-whole []
  (local prev (and app app.engine))
  (pcall (fn []
    (set app.engine {:now-ms (fn [s] 0)})))
  (set app.engine prev))"}]
                               :mutations [{:op :set
                                            :path ["app" "engine"]
                                            :line 8 :column 1
                                            :form "(set app.engine {:now-ms (fn [s] 0)})"
                                            :enclosing-fn "test-and-whole"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "guarded whole-object (and app app.engine) snapshot + pcall restore should pass"))

(fn mutation-restoration-flags-or-guarded-snapshot []
  "Negative: (or ...) snapshot does not count as exact snapshot."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-or-guard"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-or-guard []
  (local orig (or app.engine.width 100))
  (pcall (fn []
    (set app.engine.width 200)))
  (set app.engine.width orig))"}]
                               :mutations [{:op :set
                                            :path ["app" "engine" "width"]
                                            :line 8 :column 1
                                            :form "(set app.engine.width 200)"
                                            :enclosing-fn "test-or-guard"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag (or ...) snapshot — not an exact snapshot")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")))

(fn mutation-restoration-flags-and-with-unrelated-guard []
  "Negative: (and condition app.engine.width) where condition is not a path prefix should not count."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-unrelated-guard"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-unrelated-guard []
  (local orig (and some-condition app.engine.width))
  (pcall (fn []
    (set app.engine.width 200)))
  (set app.engine.width orig))"}]
                               :mutations [{:op :set
                                            :path ["app" "engine" "width"]
                                            :line 8 :column 1
                                            :form "(set app.engine.width 200)"
                                            :enclosing-fn "test-unrelated-guard"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag (and condition path) where condition is not a path prefix")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")))

(fn mutation-restoration-flags-pcall-restore-before-mutate-and-guard []
  "Negative: restore before pcall then later unguarded mutation should still flag."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-restore-before-leak"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 250
                                             :form "(fn test-restore-before-leak []
  (local orig (and app.engine app.engine.width))
  (set app.engine.width orig)
  (pcall (fn []
    (set app.engine.width 300))))"}]
                               :mutations [{:op :set
                                            :path ["app" "engine" "width"]
                                            :line 6 :column 1
                                            :form "(set app.engine.width orig)"
                                            :enclosing-fn "test-restore-before-leak"}
                                           {:op :set
                                            :path ["app" "engine" "width"]
                                            :line 9 :column 1
                                            :form "(set app.engine.width 300)"
                                            :enclosing-fn "test-restore-before-leak"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag restore before pcall + later unguarded mutation")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; ======================================================================
;; Parent-scope pcall restoration tests
;; ======================================================================

(fn mutation-restoration-allows-anon-pcall-parent-restore []
  "Positive: anonymous fn inside pcall; mutation attributed to <anonymous>; parent named fn has snapshot/restore around pcall."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-parent-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 250
                                             :form "(fn test-parent-restore []
  (local orig (and app.engine app.engine.width))
  (pcall (fn []
    (set app.engine.width 100)))
  (set app.engine.width orig))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 8 :column 1
                                             :length 50
                                  :form "(fn [] (set app.engine.width 100))"}]
                                :mutations [{:op :set
                                             :path ["app" "engine" "width"]
                                             :line 8 :column 1
                                             :form "(set app.engine.width 100)"
                                             :enclosing-fn "<anonymous>"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "anonymous pcall-body mutation restored by parent snapshot/restore after pcall should pass"))

(fn mutation-restoration-flags-anon-pcall-no-parent-restore []
  "Negative: anonymous fn inside pcall; parent has no snapshot or restore — flag."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-anon-no-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-anon-no-restore []
  (pcall (fn []
    (set app.engine.width 100)))
  (do-test))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 7 :column 1
                                             :length 40
                                  :form "(fn [] (set app.engine.width 100))"}]
                                :mutations [{:op :set
                                             :path ["app" "engine" "width"]
                                             :line 7 :column 1
                                             :form "(set app.engine.width 100)"
                                             :enclosing-fn "test-anon-no-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag anonymous pcall mutation without parent restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")))

(fn mutation-restoration-flags-parent-restore-outside-pcall []
  "Negative: parent restore should not suppress a mutation outside pcall body when the mutation was not inside pcall."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                              :module "tests.test-bad"
                              :definitions [{:kind :fn
                                             :name "test-outside-pcall"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-outside-pcall []
  (set app.engine.width 100)
  (pcall (fn []
    (do-something)))
  (do-test))"}]
                               :mutations [{:op :set
                                            :path ["app" "engine" "width"]
                                            :line 7 :column 1
                                            :form "(set app.engine.width 100)"
                                            :enclosing-fn "test-outside-pcall"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag mutation outside pcall body without snapshot or restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")))

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
(table.insert tests {:name "mutation-restoration allows hyphenated path restore" :fn mutation-restoration-allows-hyphenated-path-restore})
(table.insert tests {:name "mutation-restoration flags hyphenated path no restore" :fn mutation-restoration-flags-hyphenated-path-no-restore})
(table.insert tests {:name "mutation-restoration flags unrelated RHS hyphenated path" :fn mutation-restoration-flags-unrelated-rhs-hyphenated-path})
(table.insert tests {:name "mutation-restoration flags restore before later mutation hyphenated" :fn mutation-restoration-flags-restore-before-later-mutation-hyphenated-path})
(table.insert tests {:name "mutation-restoration allows multi nonrestore then restore hyphenated" :fn mutation-restoration-allows-multi-nonrestore-then-restore-hyphenated})
(table.insert tests {:name "mutation-restoration allows and guarded subpath snapshot" :fn mutation-restoration-allows-and-guarded-subpath-snapshot})
(table.insert tests {:name "mutation-restoration allows and guarded whole object snapshot" :fn mutation-restoration-allows-and-guarded-whole-object-snapshot})
(table.insert tests {:name "mutation-restoration flags or guarded snapshot" :fn mutation-restoration-flags-or-guarded-snapshot})
(table.insert tests {:name "mutation-restoration flags and with unrelated guard" :fn mutation-restoration-flags-and-with-unrelated-guard})
(table.insert tests {:name "mutation-restoration flags pcall restore before mutate and guard" :fn mutation-restoration-flags-pcall-restore-before-mutate-and-guard})
(table.insert tests {:name "mutation-restoration allows anon pcall parent restore" :fn mutation-restoration-allows-anon-pcall-parent-restore})
(table.insert tests {:name "mutation-restoration flags anon pcall no parent restore" :fn mutation-restoration-flags-anon-pcall-no-parent-restore})
(table.insert tests {:name "mutation-restoration flags parent restore outside pcall" :fn mutation-restoration-flags-parent-restore-outside-pcall})
(table.insert tests {:name "test-isolation rules returns table with one rule" :fn test-isolation-rules-returns-table-with-one-rule})
(table.insert tests {:name "test-isolation rules have required structure" :fn test-isolation-rules-have-required-structure})
(table.insert tests {:name "test-isolation rules executable by runner" :fn test-isolation-runner-executable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-test-isolation" :tests tests})))

{:name "constraints-rules-test-isolation" :tests tests :main main}
