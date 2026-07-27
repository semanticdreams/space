;; Tests for Structure and Formatting constraint rules.
;; Follows TDD: these tests must FAIL before structure.fnl is implemented.

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

(fn find-rule-by-id [rules id]
  "Find a rule in a rules list by its :id field."
  (var found nil)
  (each [_ r (ipairs rules)]
    (when (= r.id id)
      (set found r)))
  found)

;; ======================================================================
;; structure.max-nesting-depth
;; ======================================================================

(fn max-nesting-depth-allows-depth-7 []
  "A function with max nesting depth 7 (at threshold) should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-nesting-depth"))
  (assert rule "rule structure.max-nesting-depth should be in rules list")
  (local ff (make-file-fact {:path "/src/module.fnl"
                              :module "module"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "normal-fn"
                                                     :line 10
                                                     :column 1
                                                     :length 50
                                                     :max-nesting-depth 7}]}}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "function with depth 7 should pass"))

(fn max-nesting-depth-flags-depth-8 []
  "A function with max nesting depth 8 (exceeds threshold of 7) should produce a diagnostic."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-nesting-depth"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/deep-module.fnl"
                              :module "deep-module"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "deep-fn"
                                                     :line 10
                                                     :column 1
                                                     :length 200
                                                     :max-nesting-depth 8}]}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for depth 8")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.max-nesting-depth")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "structure-formatting") "diagnostic should have family structure-formatting")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.measure 8) "evidence should report the measured value")
  (assert (= d.evidence.limit 7) "evidence should report the limit")
  (assert (= d.evidence.function-name "deep-fn")
          "evidence should report the function name")
  (assert d.evidence.fingerprint "evidence should include a fingerprint")
  (assert (d.evidence.fingerprint:find "deep-fn" 1 true)
          "fingerprint should contain the function name"))

(fn max-nesting-depth-distinct-fingerprints []
  "Two deep functions in the same file should produce distinct fingerprints,
  so baselines for function A do not also suppress function B."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-nesting-depth"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/two-deep.fnl"
                              :module "two-deep"
                              :metrics {:module-lines 300
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "deep-fn-a"
                                                     :line 10
                                                     :column 1
                                                     :length 150
                                                     :max-nesting-depth 8}
                                                    {:name "deep-fn-b"
                                                     :line 200
                                                     :column 1
                                                     :length 100
                                                     :max-nesting-depth 8}]}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for two deep functions")
  (assert (>= (length result) 2) "should have at least two diagnostics")
  (local d1 (. result 1))
  (local d2 (. result 2))
  (assert d1.evidence.fingerprint "first diagnostic should have fingerprint")
  (assert d2.evidence.fingerprint "second diagnostic should have fingerprint")
  (assert (not= d1.evidence.fingerprint d2.evidence.fingerprint)
          "fingerprints for distinct functions should differ")
  (assert d1.line "first diagnostic should include the function line")
  (assert d2.line "second diagnostic should include the function line"))

;; ======================================================================
;; structure.max-function-length
;; ======================================================================

(fn max-function-length-allows-length-120 []
  "A function with length 120 (at threshold) should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-function-length"))
  (assert rule "rule structure.max-function-length should be in rules list")
  (local ff (make-file-fact {:path "/src/module.fnl"
                              :module "module"
                              :metrics {:module-lines 200
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "normal-fn"
                                                     :line 10
                                                     :column 1
                                                     :length 120
                                                     :max-nesting-depth 2}]}}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "function length 120 should pass"))

(fn max-function-length-flags-length-121 []
  "A function with length 121 (exceeds threshold of 120) should produce a diagnostic."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-function-length"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/long-module.fnl"
                              :module "long-module"
                              :metrics {:module-lines 200
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "long-fn"
                                                     :line 10
                                                     :column 1
                                                     :length 121
                                                     :max-nesting-depth 2}]}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for function length 121")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.max-function-length")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "structure-formatting") "diagnostic should have family structure-formatting")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.measure 121) "evidence should report the measured value")
  (assert (= d.evidence.limit 120) "evidence should report the limit")
  (assert (= d.evidence.function-name "long-fn") "evidence should report the function name"))

(fn max-function-length-flags-multiple-functions []
  "A module with multiple functions exceeding the limit should flag each one."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-function-length"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/big-module.fnl"
                              :module "big-module"
                              :metrics {:module-lines 500
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "fn-a"
                                                     :line 10
                                                     :column 1
                                                     :length 150
                                                     :max-nesting-depth 2}
                                                    {:name "fn-b"
                                                     :line 200
                                                     :column 1
                                                     :length 130
                                                     :max-nesting-depth 2}]}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for multiple long functions")
  (assert (>= (length result) 2) "should have at least two diagnostics"))

(fn max-function-length-allows-mixed-short-and-long []
  "A module with a mix of short and long functions; only long ones should be flagged.
  But if all are under threshold, should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-function-length"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/mixed-module.fnl"
                              :module "mixed-module"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "short-fn"
                                                     :line 5
                                                     :column 1
                                                     :length 10
                                                     :max-nesting-depth 1}
                                                    {:name "also-short"
                                                     :line 20
                                                     :column 1
                                                     :length 50
                                                     :max-nesting-depth 2}]}}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "module with only short functions should pass"))

;; ======================================================================
;; structure.max-module-length
;; ======================================================================

(fn max-module-length-allows-length-1200 []
  "A module with 1200 lines (at threshold) should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-module-length"))
  (assert rule "rule structure.max-module-length should be in rules list")
  (local ff (make-file-fact {:path "/src/module.fnl"
                              :module "module"
                              :metrics {:module-lines 1200
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "module length 1200 should pass"))

(fn max-module-length-flags-length-1201 []
  "A module with 1201 lines (exceeds threshold of 1200) should produce a diagnostic."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-module-length"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/huge-module.fnl"
                              :module "huge-module"
                              :metrics {:module-lines 1201
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for module length 1201")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.max-module-length")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "structure-formatting") "diagnostic should have family structure-formatting")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.measure 1201) "evidence should report the measured value")
  (assert (= d.evidence.limit 1200) "evidence should report the limit"))

;; ======================================================================
;; structure.large-inline-structure
;; ======================================================================

(fn large-inline-structure-allows-table-size-80 []
  "A module with max table literal size 80 (at threshold) should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.large-inline-structure"))
  (assert rule "rule structure.large-inline-structure should be in rules list")
  (local ff (make-file-fact {:path "/src/module.fnl"
                              :module "module"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 80
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "table size 80 should pass"))

(fn large-inline-structure-flags-table-size-81 []
  "A module with max table literal size 81 (exceeds threshold of 80) should produce a diagnostic."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.large-inline-structure"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/big-table.fnl"
                              :module "big-table"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 81
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for table size 81")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.large-inline-structure")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "structure-formatting") "diagnostic should have family structure-formatting")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.measure 81) "evidence should report the measured value")
  (assert (= d.evidence.limit 80) "evidence should report the limit"))

(fn large-inline-structure-allows-anon-depth-3 []
  "A module with max anonymous callback depth 3 (at threshold) should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.large-inline-structure"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/module.fnl"
                              :module "module"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 3
                                        :max-table-literal-size 10
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "anon callback depth 3 should pass"))

(fn large-inline-structure-flags-anon-depth-4 []
  "A module with max anonymous callback depth 4 (exceeds threshold of 3) should produce a diagnostic."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.large-inline-structure"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/deep-callbacks.fnl"
                              :module "deep-callbacks"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 4
                                        :max-table-literal-size 10
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for anon depth 4")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.large-inline-structure")
          "diagnostic should have correct constraint-id")
  (assert d.evidence "diagnostic should include evidence"))

(fn large-inline-structure-flags-both-metrics []
  "A module exceeding both table size and anon callback depth should flag both."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.large-inline-structure"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                              :module "bad-module"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 4
                                        :max-table-literal-size 90
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for both exceeded metrics")
  (assert (>= (length result) 2) "should have at least two diagnostics"))

(fn large-inline-structure-allows-small-table-and-shallow-callbacks []
  "A module with small table size and shallow callbacks should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.large-inline-structure"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/clean.fnl"
                              :module "clean"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 20
                                        :functions []}}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "clean module should pass"))

;; ======================================================================
;; structure.style-doctrine
;; ======================================================================

(fn style-doctrine-flags-let-form []
  "A module containing a (let ...) form should be flagged."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule structure.style-doctrine should be in rules list")
  (local ff (make-file-fact {:path "/src/legacy-module.fnl"
                              :module "legacy-module"
                              :definitions [{:kind :fn
                                             :name "old-style"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 50
                                             :form "(fn old-style []
  (let x 10
    (print x)))"}]
                              :exports []
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for let form")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.style-doctrine")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "structure-formatting") "diagnostic should have family structure-formatting")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.construct "let") "evidence should identify let construct"))

(fn style-doctrine-flags-legacy-alias-export []
  "A module exposing an export key containing 'legacy' should be flagged."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/compat-module.fnl"
                              :module "compat-module"
                              :definitions []
                              :exports [{:key "legacy-init"
                                         :line 5 :column 1
                                         :form "legacy-init"}
                                        {:key "new-init"
                                         :line 10 :column 1
                                         :form "new-init"}]
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for legacy alias export")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.style-doctrine")
          "diagnostic should have correct constraint-id")
  (assert d.evidence "diagnostic should include evidence"))

(fn style-doctrine-flags-compat-alias-export []
  "A module exposing an export key containing 'compat' should be flagged."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/compat-module.fnl"
                              :module "compat-module"
                              :definitions []
                              :exports [{:key "render-compat"
                                         :line 5 :column 1
                                         :form "render-compat"}]
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for compat alias export")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.style-doctrine")
          "diagnostic should have correct constraint-id"))

(fn style-doctrine-flags-alias-export []
  "A module exposing an export key containing 'alias' should be flagged."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/alias-module.fnl"
                              :module "alias-module"
                              :definitions []
                              :exports [{:key "old-alias"
                                         :line 5 :column 1
                                         :form "old-alias"}]
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for alias export")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.style-doctrine")
          "diagnostic should have correct constraint-id"))

(fn style-doctrine-flags-silent-fallback-or-form []
  "A definition containing (or required-value fallback-value) without
  assert or error in the same function should be flagged."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/silent-fallback.fnl"
                              :module "silent-fallback"
                              :definitions [{:kind :fn
                                             :name "get-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 60
                                             :form "(fn get-widget []
  (or required-widget default-widget))"}]
                              :exports []
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for silent fallback or-form")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.style-doctrine")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "structure-formatting") "diagnostic should have family structure-formatting")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.construct "silent-fallback") "evidence should identify silent-fallback construct"))

(fn style-doctrine-allows-or-with-assert []
  "A function containing (or required-value fallback-value) with assert in the same function should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/loud-fallback.fnl"
                              :module "loud-fallback"
                              :definitions [{:kind :fn
                                             :name "get-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 80
                                             :form "(fn get-widget []
  (or required-widget default-widget)
  (assert required-widget \"missing widget\"))"}]
                              :exports []
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 7 :column 1
                                       :form "(assert required-widget \"missing widget\")"
                                       :enclosing-fn "get-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "or-form with assert in same function should pass"))

(fn style-doctrine-allows-or-with-error []
  "A function containing (or required-value fallback-value) with error in the same function should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/error-fallback.fnl"
                              :module "error-fallback"
                              :definitions [{:kind :fn
                                             :name "get-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 80
                                             :form "(fn get-widget []
  (or required-widget default-widget)
  (when (not required-widget)
    (error \"missing widget\")))"}]
                              :exports []
                              :calls [{:callee "error"
                                       :receiver nil :method nil
                                       :line 8 :column 1
                                       :form "(error \"missing widget\")"
                                       :enclosing-fn "get-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "or-form with error in same function should pass"))

(fn style-doctrine-allows-clean-module []
  "A module with no let forms, no legacy/compat/alias exports, and no silent fallbacks should pass."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/clean-module.fnl"
                              :module "clean-module"
                              :definitions [{:kind :fn
                                             :name "normal-fn"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 40
                                             :form "(fn normal-fn [x]
  (+ x 1))"}]
                              :exports [{:key "new-api"
                                         :line 10 :column 1
                                         :form "new-api"}]
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "clean module should pass"))

(fn style-doctrine-allows-or-in-different-context []
  "An (or ...) form that is NOT a silent fallback (in a test context
  where assert is present) should pass.  We test that the or-with-assert
  and or-with-error cases pass rather than checking a 3-arg logical or."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/normal-or.fnl"
                              :module "normal-or"
                              :definitions [{:kind :fn
                                             :name "choose"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 80
                                             :form "(fn choose [a]
  (or a :default))"}]
                              :exports []
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 2 :column 1
                                       :form "(assert a \"missing\")"
                                       :enclosing-fn "choose"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "or-form with assert in same function should pass"))

(fn style-doctrine-allows-non-let-local []
  "A module using (local ...) should pass — only (let ...) is flagged."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/local-only.fnl"
                              :module "local-only"
                              :definitions [{:kind :local
                                             :name "x"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 15
                                             :form "(local x 10)"}]
                              :exports []
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "local-only module should pass"))

;; R1-2: let text inside string literals or comments should not be flagged
(fn style-doctrine-allows-let-text-inside-string []
  "A function whose source contains '(let ' as part of a string literal
  should NOT be flagged — the rule checks form syntax, not raw text."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/string-let.fnl"
                              :module "string-let"
                              :definitions [{:kind :fn
                                             :name "render"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 20
                                             :form "(fn render []
  \"example (let text)\")"}]
                              :exports []
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "let inside string literal should not be flagged"))

(fn style-doctrine-allows-or-text-inside-string []
  "A function whose source contains '(or ' inside a string literal
  should NOT be flagged as a silent fallback."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/string-or.fnl"
                              :module "string-or"
                              :definitions [{:kind :fn
                                             :name "format"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 20
                                             :form "(fn format [x]
  \"an (or expr) in a string\")"}]
                              :exports []
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "or inside string literal should not be flagged"))

(fn style-doctrine-allows-let-text-after-comment []
  "A function with '; comment containing (let)' in the same source text
  should NOT be flagged — comments are not code."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.style-doctrine"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/comment-let.fnl"
                              :module "comment-let"
                              :definitions [{:kind :fn
                                             :name "render"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 40
                                             :form "(fn render [x]
  ;(let x 10) - old code
  (* x 2))"}]
                              :exports []
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "let inside comment should not be flagged"))

;; ======================================================================
;; R1-3: Real Source/Facts integration — parse valid and invalid Fennel source
;; ======================================================================

(fn structure-source-facts-passes-valid-source []
  "Valid Fennel source parsed through the tree-sitter fact extractor should
  produce no diagnostics for a clean module under all structure rules."
  (local Structure (require :constraints.rules.structure))
  (local Facts (require :constraints.facts))
  (local ts (require :tree-sitter))
  (local rules (Structure.rules))
  (local source "(fn small-fn [x]
  (+ x 1))

{:name \"test\"
 :version 1}")
  (local tree (ts.parse source {:language :fennel}))
  (local root (tree:root))
  (local file-records [{:target {:kind :repo :name :test}
                         :path "/test/small.fnl"
                         :module "test.small"
                         :source source
                         :root root}])
  (local fact-db (Facts.extract file-records))
  (local ctx {:target {:kind :repo :name :test}
              :facts fact-db
              :files []})
  (each [_ rule (ipairs rules)]
    (let [result (rule.run ctx)]
      (assert (or (= result nil) (= (length result) 0))
              (.. "rule " rule.id " should pass for clean source, got diagnostics")))))

(fn structure-source-facts-flags-deep-nesting-via-facts []
  "Deeply nested Fennel source parsed through the tree-sitter fact extractor
  should produce a max-nesting-depth diagnostic at the offending function."
  (local Structure (require :constraints.rules.structure))
  (local Facts (require :constraints.facts))
  (local ts (require :tree-sitter))
  (local rules (Structure.rules))
  (local rule (find-rule-by-id rules "structure.max-nesting-depth"))
  (assert rule "rule should be in rules list")
  ;; Fennel source with deep nesting using list forms (when, each, print)
  ;; tree-sitter counts list nodes, not let_form/each_form/if_form
  ;; fn_form + 8 nested when lists → depth 9, max-nesting = 8 (> limit 7)
  (local source "(fn deep-nest []
  (when true
    (when true
      (when true
        (when true
          (when true
            (when true
              (when true
                (when true
                  (print :deep))))))))))")
  (local tree (ts.parse source {:language :fennel}))
  (local root (tree:root))
  (local file-records [{:target {:kind :repo :name :test}
                         :path "/test/deep-nest.fnl"
                         :module "test.deep-nest"
                         :source source
                         :root root}])
  (local fact-db (Facts.extract file-records))
  (local ctx {:target {:kind :repo :name :test}
              :facts fact-db
              :files []})
  (local result (rule.run ctx))
  (assert result "real fact extraction should produce diagnostics for deep nesting")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "structure.max-nesting-depth")
          "real-fact diagnostic should have correct constraint-id")
  (assert d.evidence.fingerprint "real-fact diagnostic should include fingerprint"))

;; ======================================================================
;; Runner integration: violation diagnostic contract
;; ======================================================================

(fn structure-runner-violation-contract []
  "When a rule produces violations, the runner must return non-pass status
  and diagnostics that include target, file, constraint-id, and evidence.fingerprint."
  (local Structure (require :constraints.rules.structure))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (Structure.rules))
  ;; Only run the max-nesting-depth rule against a file fact that exceeds the limit
  (local nesting-rule (find-rule-by-id rules "structure.max-nesting-depth"))
  (assert nesting-rule "nesting rule must be in rules list")
  (local ff (make-file-fact {:path "/test/too-deep.fnl"
                              :module "test.too-deep"
                              :metrics {:module-lines 100
                                        :max-nesting-depth 2
                                        :max-anonymous-callback-depth 1
                                        :max-table-literal-size 10
                                        :functions [{:name "deep-fn"
                                                     :line 5
                                                     :column 1
                                                     :length 80
                                                     :max-nesting-depth 9}]}}))
  (local fact-db (make-fact-db [ff]))
  (local target {:kind :repo :name :test
                 :facts fact-db
                 :files []})
  (local result (ConstraintRunner.run {:rules [nesting-rule]
                                        :target target
                                        :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (not= result.status :pass)
          (.. "expected non-pass status for violation, got " result.status))
  (assert (>= (length result.diagnostics) 1)
          "should have at least one diagnostic")
  (local d (. result.diagnostics 1))
  (assert d.target "diagnostic should include target")
  (assert (= d.file "/test/too-deep.fnl")
          (.. "diagnostic should report file, got " (tostring d.file)))
  (assert (= d.constraint-id "structure.max-nesting-depth")
          (.. "diagnostic should have correct constraint-id, got " (tostring d.constraint-id)))
  (assert d.evidence.fingerprint "diagnostic should include evidence.fingerprint"))

;; ======================================================================
;; Structure metadata tests
;; ======================================================================

(fn structure-rules-returns-table []
  "Structure.rules() should return a table with 5 rules."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (assert (= (type rules) :table) "rules should be a table")
  (assert (= (length rules) 5) (.. "expected 5 rules, got " (length rules))))

(fn structure-rules-have-required-structure []
  "Each structure rule should have :id, :family, :targets, :kind, :run, and :fn."
  (local Structure (require :constraints.rules.structure))
  (local rules (Structure.rules))
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) (.. "rule should have string :id, got " (tostring rule.id)))
    (assert (= rule.family "structure-formatting") (.. "rule should have family structure-formatting, got " (tostring rule.family)))
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (= rule.kind :static) (.. "rule should be kind static, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) (.. "rule should have :run function for id " (tostring rule.id)))
    (assert (= (type rule.fn) :function) (.. "rule should have :fn function for id " (tostring rule.id)))
    (assert (= rule.fn rule.run) (.. ":fn should alias :run for id " (tostring rule.id)))))

;; ======================================================================
;; Runner integration tests
;; ======================================================================

(fn structure-runner-executable []
  "Structure.rules() entries must be executable by constraints.runner.run."
  (local Structure (require :constraints.rules.structure))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (Structure.rules))
  (local target {:kind :repo :name :test
                 :facts (make-fact-db [(make-file-fact {:path "/test/clean.fnl"
                                                         :module "test-clean"
                                                         :definitions [{:kind :fn
                                                                        :name "normal-fn"
                                                                        :top-level? true
                                                                        :line 1 :column 1
                                                                        :length 10
                                                                        :form "(fn normal-fn [] nil)"}]
                                                         :exports [{:key "new-api"
                                                                    :line 5 :column 1
                                                                    :form "new-api"}]
                                                         :accesses []
                                                         :calls []})])
                 :files []})
  (local result (ConstraintRunner.run {:rules rules :target target
                                        :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (= result.status :pass) (.. "expected :pass status, got " result.status))
  (assert (= (length result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (length result.diagnostics))))

;; ======================================================================
;; Register all tests
;; ======================================================================

;; structure.max-nesting-depth
(table.insert tests {:name "max-nesting-depth allows depth 7"
                     :fn max-nesting-depth-allows-depth-7})
(table.insert tests {:name "max-nesting-depth flags depth 8"
                     :fn max-nesting-depth-flags-depth-8})
(table.insert tests {:name "max-nesting-depth distinct fingerprints"
                     :fn max-nesting-depth-distinct-fingerprints})

;; structure.max-function-length
(table.insert tests {:name "max-function-length allows length 120"
                     :fn max-function-length-allows-length-120})
(table.insert tests {:name "max-function-length flags length 121"
                     :fn max-function-length-flags-length-121})
(table.insert tests {:name "max-function-length flags multiple functions"
                     :fn max-function-length-flags-multiple-functions})
(table.insert tests {:name "max-function-length allows mixed short and long"
                     :fn max-function-length-allows-mixed-short-and-long})

;; structure.max-module-length
(table.insert tests {:name "max-module-length allows length 1200"
                     :fn max-module-length-allows-length-1200})
(table.insert tests {:name "max-module-length flags length 1201"
                     :fn max-module-length-flags-length-1201})

;; structure.large-inline-structure
(table.insert tests {:name "large-inline-structure allows table size 80"
                     :fn large-inline-structure-allows-table-size-80})
(table.insert tests {:name "large-inline-structure flags table size 81"
                     :fn large-inline-structure-flags-table-size-81})
(table.insert tests {:name "large-inline-structure allows anon depth 3"
                     :fn large-inline-structure-allows-anon-depth-3})
(table.insert tests {:name "large-inline-structure flags anon depth 4"
                     :fn large-inline-structure-flags-anon-depth-4})
(table.insert tests {:name "large-inline-structure flags both metrics"
                     :fn large-inline-structure-flags-both-metrics})
(table.insert tests {:name "large-inline-structure allows clean module"
                     :fn large-inline-structure-allows-small-table-and-shallow-callbacks})

;; structure.style-doctrine
(table.insert tests {:name "style-doctrine flags let form"
                     :fn style-doctrine-flags-let-form})
(table.insert tests {:name "style-doctrine flags legacy alias export"
                     :fn style-doctrine-flags-legacy-alias-export})
(table.insert tests {:name "style-doctrine flags compat alias export"
                     :fn style-doctrine-flags-compat-alias-export})
(table.insert tests {:name "style-doctrine flags alias export"
                     :fn style-doctrine-flags-alias-export})
(table.insert tests {:name "style-doctrine flags silent fallback or-form"
                     :fn style-doctrine-flags-silent-fallback-or-form})
(table.insert tests {:name "style-doctrine allows or with assert"
                     :fn style-doctrine-allows-or-with-assert})
(table.insert tests {:name "style-doctrine allows or with error"
                     :fn style-doctrine-allows-or-with-error})
(table.insert tests {:name "style-doctrine allows clean module"
                     :fn style-doctrine-allows-clean-module})
(table.insert tests {:name "style-doctrine allows or in different context"
                     :fn style-doctrine-allows-or-in-different-context})
(table.insert tests {:name "style-doctrine allows non-let local"
                     :fn style-doctrine-allows-non-let-local})
;; R1-2: string/comment safety
(table.insert tests {:name "style-doctrine allows let text inside string"
                     :fn style-doctrine-allows-let-text-inside-string})
(table.insert tests {:name "style-doctrine allows or text inside string"
                     :fn style-doctrine-allows-or-text-inside-string})
(table.insert tests {:name "style-doctrine allows let text after comment"
                     :fn style-doctrine-allows-let-text-after-comment})

;; Structure metadata
(table.insert tests {:name "structure rules returns table with five rules"
                     :fn structure-rules-returns-table})
(table.insert tests {:name "structure rules have required structure"
                     :fn structure-rules-have-required-structure})

;; Runner integration
(table.insert tests {:name "structure rules executable by runner"
                     :fn structure-runner-executable})
(table.insert tests {:name "structure runner violation contract"
                     :fn structure-runner-violation-contract})
;; R1-3: Source/Facts integration
(table.insert tests {:name "structure source facts passes valid source"
                     :fn structure-source-facts-passes-valid-source})
(table.insert tests {:name "structure source facts flags deep nesting via facts"
                     :fn structure-source-facts-flags-deep-nesting-via-facts})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-structure"
                        :tests tests})))

{:name "constraints-rules-structure"
 :tests tests
 :main main}
