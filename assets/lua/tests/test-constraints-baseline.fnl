(local tests [])

;; --- Baseline fingerprint tests ---

(fn baseline-fingerprint-is-deterministic []
  (local Baseline (require :constraints.baseline))
  (local d1 {:constraint-id "test.rule"
             :family "style"
             :message "bad thing"
             :evidence {:found 3 :measure 5}
             :hint "fix it"
             :file "foo.fnl"
             :line 10})
  (local d2 {:constraint-id "test.rule"
             :family "style"
             :message "bad thing"
             :evidence {:found 3 :measure 5}
             :hint "fix it"
             :file "foo.fnl"
             :line 10})
  (local fp1 (Baseline.fingerprint d1))
  (local fp2 (Baseline.fingerprint d2))
  (assert (= (type fp1) "string") "fingerprint should be a string")
  (assert (= fp1 fp2) "same diagnostic should produce same fingerprint")
  ;; Different message → different fingerprint
  (local d3 {:constraint-id "test.rule"
             :family "style"
             :message "different thing"
             :evidence {:found 3 :measure 5}
             :hint "fix it"
             :file "foo.fnl"
             :line 10})
  (local fp3 (Baseline.fingerprint d3))
  (assert (not= fp1 fp3) "different message should produce different fingerprint")
  ;; Different evidence → different fingerprint
  (local d4 {:constraint-id "test.rule"
             :family "style"
             :message "bad thing"
             :evidence {:found 99 :measure 5}
             :hint "fix it"
             :file "foo.fnl"
             :line 10})
  (local fp4 (Baseline.fingerprint d4))
  (assert (not= fp1 fp4) "different evidence should produce different fingerprint"))

;; --- Exact match suppression ---

(fn baseline-exact-match-suppresses-diagnostic []
  (local Baseline (require :constraints.baseline))
  (local Diagnostics (require :constraints.diagnostics))
  (local d (Diagnostics.violation
             {:constraint-id "structure.max-nesting-depth"
              :family "structure"
              :message "nesting depth 12 exceeds max 8"
              :evidence {:depth 12 :max 8 :measure 12}
              :hint "reduce nesting"
              :file "src/module.fnl"
              :line 42
              :target {:kind :repo :name "test"}}))
  (local fp (Baseline.fingerprint d))
  (local baseline-data
    {:required-rule-ids ["structure.max-nesting-depth"]
     :entries [{:constraint-id "structure.max-nesting-depth"
                :file "src/module.fnl"
                :line 42
                :fingerprint fp
                :measure 12
                :reason "known violation - tracked as tech debt"}]})
  (local result (Baseline.apply [d] baseline-data ["structure.max-nesting-depth"]))
  (assert (= (# result.diagnostics) 0)
          (.. "expected 0 suppressed diagnostics, got " (# result.diagnostics)))
  (assert (= (# result.baseline-diagnostics) 0)
          (.. "expected 0 baseline diagnostics for exact match, got " (# result.baseline-diagnostics))))

;; --- Worsened ---

(fn baseline-worsened-detects-higher-measure []
  (local Baseline (require :constraints.baseline))
  (local Diagnostics (require :constraints.diagnostics))
  (local d (Diagnostics.violation
             {:constraint-id "structure.max-nesting-depth"
              :family "structure"
              :message "nesting depth 15 exceeds max 8"
              :evidence {:depth 15 :max 8 :measure 15}
              :hint "reduce nesting"
              :file "src/module.fnl"
              :line 42
              :target {:kind :repo :name "test"}}))
  ;; The baseline entry has fingerprint for measure=12, current diagnostic has measure=15
  ;; Baseline fingerprint for the old diagnostic with measure=12
  (local old-diag-for-fingerprint {:constraint-id "structure.max-nesting-depth"
                                    :family "structure"
                                    :message "nesting depth 12 exceeds max 8"
                                    :evidence {:depth 12 :max 8 :measure 12}
                                    :hint "reduce nesting"
                                    :file "src/module.fnl"
                                    :line 42})
  (local old-fp (Baseline.fingerprint old-diag-for-fingerprint))
  (local baseline-data
    {:required-rule-ids ["structure.max-nesting-depth"]
     :entries [{:constraint-id "structure.max-nesting-depth"
                :file "src/module.fnl"
                :line 42
                :fingerprint old-fp
                :measure 12
                :reason "known violation"}]})
  (local result (Baseline.apply [d] baseline-data ["structure.max-nesting-depth"]))
  ;; The original diagnostic should still appear (not suppressed since fingerprint differs)
  (assert (= (# result.diagnostics) 1)
          (.. "expected 1 un-suppressed diagnostic, got " (# result.diagnostics)))
  ;; A baseline.worsened diagnostic should be emitted
  (assert (= (# result.baseline-diagnostics) 1)
          (.. "expected 1 baseline diagnostic (worsened), got " (# result.baseline-diagnostics)))
  (local bd (. result.baseline-diagnostics 1))
  (assert (= bd.family "baseline") "baseline diagnostic should have family \"baseline\"")
  (assert (= bd.severity :error) "baseline diagnostic should have severity :error"))

;; --- Stale ---

(fn baseline-stale-detects-unmatched-entry []
  (local Baseline (require :constraints.baseline))
  (local Diagnostics (require :constraints.diagnostics))
  ;; A baseline entry exists, but no current diagnostic matches it
  ;; Create a diagnostic that matches on different file/line so it's not matched
  (local d (Diagnostics.violation
             {:constraint-id "structure.max-nesting-depth"
              :family "structure"
              :message "nesting depth 10 exceeds max 8"
              :evidence {:depth 10 :max 8 :measure 10}
              :hint "reduce nesting"
              :file "src/other.fnl"
              :line 99
              :target {:kind :repo :name "test"}}))
  ;; Baseline entry is for src/module.fnl:42, but diagnostic is for src/other.fnl:99
  (local old-diag-for-fingerprint {:constraint-id "structure.max-nesting-depth"
                                    :family "structure"
                                    :message "nesting depth 12 exceeds max 8"
                                    :evidence {:depth 12 :max 8 :measure 12}
                                    :hint "reduce nesting"
                                    :file "src/module.fnl"
                                    :line 42})
  (local old-fp (Baseline.fingerprint old-diag-for-fingerprint))
  (local baseline-data
    {:required-rule-ids ["structure.max-nesting-depth"]
     :entries [{:constraint-id "structure.max-nesting-depth"
                :file "src/module.fnl"
                :line 42
                :fingerprint old-fp
                :measure 12
                :reason "known violation"}]})
  (local result (Baseline.apply [d] baseline-data ["structure.max-nesting-depth"]))
  ;; The original diagnostic should still appear
  (assert (= (# result.diagnostics) 1)
          (.. "expected 1 un-suppressed diagnostic, got " (# result.diagnostics)))
  ;; A stale baseline diagnostic should be emitted
  (assert (= (# result.baseline-diagnostics) 1)
          (.. "expected 1 baseline diagnostic (stale), got " (# result.baseline-diagnostics)))
  (local bd (. result.baseline-diagnostics 1))
  (assert (= bd.family "baseline") "baseline diagnostic should have family \"baseline\"")
  (assert (= bd.severity :error) "baseline diagnostic should have severity :error")
  (assert bd.stale "stale diagnostic should have :stale flag"))

;; --- Required rule missing ---

(fn baseline-required-rule-missing-detected []
  (local Baseline (require :constraints.baseline))
  (local baseline-data
    {:required-rule-ids ["structure.max-nesting-depth"
                         "scene.sandbox-activation-contract"]
     :entries []})
  ;; present-rule-ids is missing "scene.sandbox-activation-contract"
  (local result (Baseline.apply [] baseline-data ["structure.max-nesting-depth"]))
  (assert (= (# result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (# result.diagnostics)))
  (assert (= (# result.baseline-diagnostics) 1)
          (.. "expected 1 baseline diagnostic (required-rule-missing), got " (# result.baseline-diagnostics)))
  (local bd (. result.baseline-diagnostics 1))
  (assert (= bd.family "baseline") "baseline diagnostic should have family \"baseline\"")
  (assert (= bd.severity :error) "baseline diagnostic should have severity :error")
  (assert bd.missing-required "missing-required diagnostic should have :missing-required flag")
  (assert (= bd.constraint-id "scene.sandbox-activation-contract")
          (.. "expected constraint-id to be the missing rule, got " (tostring bd.constraint-id))))

;; --- Multiple baseline entries ---

(fn baseline-multiple-entries-partial-match []
  (local Baseline (require :constraints.baseline))
  (local Diagnostics (require :constraints.diagnostics))
  ;; Two diagnostics, two baseline entries. One exact match, one stale.
  (local d1 (Diagnostics.violation
              {:constraint-id "structure.max-nesting-depth"
               :family "structure"
               :message "depth 12"
               :evidence {:depth 12 :measure 12}
               :hint "fix"
               :file "a.fnl"
               :line 10}))
  (local d2 (Diagnostics.violation
              {:constraint-id "scene.sandbox-activation-contract"
               :family "scene-sandbox"
               :message "missing contract"
               :evidence {:measure 1}
               :hint "add contract"
               :file "b.fnl"
               :line 20}))
  ;; Baseline entry for a.fnl:10 matches d1
  (local fp1 (Baseline.fingerprint d1))
  ;; Baseline entry for c.fnl:30 is stale (no matching diagnostic)
  (local stale-fp "will-not-match")
  (local baseline-data
    {:required-rule-ids ["structure.max-nesting-depth" "scene.sandbox-activation-contract"]
     :entries [{:constraint-id "structure.max-nesting-depth"
                :file "a.fnl"
                :line 10
                :fingerprint fp1
                :measure 12
                :reason "known"}
               {:constraint-id "scene.sandbox-activation-contract"
                :file "c.fnl"
                :line 30
                :fingerprint stale-fp
                :measure 1
                :reason "known"}]})
  (local result (Baseline.apply [d1 d2] baseline-data
                                ["structure.max-nesting-depth" "scene.sandbox-activation-contract"]))
  ;; d1 suppressed, d2 passes through (no baseline entry for b.fnl:20)
  (assert (= (# result.diagnostics) 1)
          (.. "expected 1 un-suppressed diagnostic (d2), got " (# result.diagnostics)))
  ;; One stale baseline entry
  (assert (= (# result.baseline-diagnostics) 1)
          (.. "expected 1 baseline diagnostic (stale), got " (# result.baseline-diagnostics)))
  (local bd (. result.baseline-diagnostics 1))
  (assert bd.stale "should be stale diagnostic")
  (assert (= bd.constraint-id "scene.sandbox-activation-contract") "stale diagnostic for correct rule"))

;; --- Baseline.load loads data ---

(fn baseline-load-returns-data []
  (local Baseline (require :constraints.baseline))
  (local data (Baseline.load))
  (assert (= (type data) "table") "baseline data should be a table")
  (assert (= (type data.required-rule-ids) "table") "required-rule-ids should be a table")
  (assert (= (type data.entries) "table") "entries should be a table")
  ;; All required rule IDs from the MVP should be present
  (assert (> (# data.required-rule-ids) 0) "required-rule-ids should not be empty"))

;; --- Runner integration: baseline applied after rules ---

(fn runner-applies-baseline-after-rules []
  (local Runner (require :constraints.runner))
  (local Diagnostics (require :constraints.diagnostics))
  ;; Simulate a baseline-data module with a required rule not present.
  ;; The runner should collect rule IDs and apply baseline, finding a missing required rule.
  (local baseline-data
    {:required-rule-ids ["structure.max-nesting-depth"
                         "structure.max-function-length"
                         "scene.sandbox-activation-contract"]
     :entries []})
  (local result (Runner.run
                  {:rules [{:id "structure.max-nesting-depth"
                            :fn (fn [_target] nil)}
                           {:id "structure.max-function-length"
                            :fn (fn [_target]
                                   (Diagnostics.violation
                                     {:constraint-id "structure.max-function-length"
                                      :family "structure"
                                      :message "function too long"
                                      :evidence {:measure 50}
                                      :hint "refactor"
                                      :file "src/test.fnl"
                                      :line 5}))}]
                   :target {:kind :files :name "test-target"}
                   :baseline-data baseline-data}))
  ;; Should have the violation diagnostic + baseline diagnostic for missing required rule
  (assert (not= result.status :pass) "should not be :pass since there are violations")
  (assert (>= result.counts.total 1) (.. "expected at least 1 diagnostic, got " result.counts.total))
  ;; Verify the baseline diagnostic for the missing required rule
  (var found-missing-rule false)
  (each [_ d (ipairs result.diagnostics)]
    (when (and (= d.family "baseline") d.missing-required
               (= d.constraint-id "scene.sandbox-activation-contract"))
      (set found-missing-rule true)))
  (assert found-missing-rule "expected a missing-required baseline diagnostic for scene.sandbox-activation-contract"))

;; Register tests
(table.insert tests {:name "baseline fingerprint is deterministic"
                     :fn baseline-fingerprint-is-deterministic})
(table.insert tests {:name "baseline exact match suppresses diagnostic"
                     :fn baseline-exact-match-suppresses-diagnostic})
(table.insert tests {:name "baseline worsened detects higher measure"
                     :fn baseline-worsened-detects-higher-measure})
(table.insert tests {:name "baseline stale detects unmatched entry"
                     :fn baseline-stale-detects-unmatched-entry})
(table.insert tests {:name "baseline required rule missing detected"
                     :fn baseline-required-rule-missing-detected})
(table.insert tests {:name "baseline multiple entries partial match"
                     :fn baseline-multiple-entries-partial-match})
(table.insert tests {:name "baseline load returns data"
                     :fn baseline-load-returns-data})
(table.insert tests {:name "runner applies baseline after rules"
                     :fn runner-applies-baseline-after-rules})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-baseline"
                       :tests tests})))

{:name "constraints-baseline"
 :tests tests
 :main main}
