(local tests [])

;; --- Diagnostics tests ---

(fn diagnostic-violation-normalizes-fields []
  (local Diagnostics (require :constraints.diagnostics))
  (local d (Diagnostics.violation
             {:constraint-id "test-rule"
              :family "style"
              :severity :warning
              :message "something is wrong"
              :target {:kind :files :name "test-target"}
              :file "test.fnl"
              :line 42
              :column 7
              :evidence {:found "x" :expected "y"}
              :hint "try fixing it"}))
  (assert (= d.constraint-id "test-rule") "constraint-id should be preserved")
  (assert (= d.family "style") "family should be preserved")
  (assert (= d.severity :warning) "severity should be preserved")
  (assert (= d.message "something is wrong") "message should be preserved")
  (assert (= d.target.kind :files) "target kind should be preserved")
  (assert (= d.target.name "test-target") "target name should be preserved")
  (assert (= d.file "test.fnl") "file should be preserved")
  (assert (= d.line 42) "line should be preserved")
  (assert (= d.column 7) "column should be preserved")
  (assert (= d.evidence.found "x") "evidence should be preserved")
  (assert (= d.evidence.expected "y") "evidence should be preserved")
  (assert (= d.hint "try fixing it") "hint should be preserved"))

(fn diagnostic-violation-defaults-severity-and-evidence []
  (local Diagnostics (require :constraints.diagnostics))
  (local d (Diagnostics.violation
             {:constraint-id "test-defaults"
              :family "correctness"
              :message "missing defaults"
              :hint "add them"}))
  (assert (= d.severity :error) "severity should default to :error")
  (assert (= d.evidence.found nil) "evidence should default to empty table")
  (assert (= d.constraint-id "test-defaults") "constraint-id should be preserved")
  (assert (= d.family "correctness") "family should be preserved")
  (assert (= d.message "missing defaults") "message should be preserved")
  (assert (= d.hint "add them") "hint should be preserved"))

(fn diagnostic-violation-requires-constraint-id []
  (local Diagnostics (require :constraints.diagnostics))
  (local (ok err) (pcall #(Diagnostics.violation
                            {:family "style"
                             :message "bad"
                             :hint "fix it"})))
  (assert (not ok) "expected missing constraint-id to raise an error")
  (assert (string.find (tostring err) "constraint-id" 1 true)
          (.. "error should mention constraint-id, got: " (tostring err))))

(fn diagnostic-violation-requires-family []
  (local Diagnostics (require :constraints.diagnostics))
  (local (ok err) (pcall #(Diagnostics.violation
                            {:constraint-id "test"
                             :message "bad"
                             :hint "fix it"})))
  (assert (not ok) "expected missing family to raise an error")
  (assert (string.find (tostring err) "family" 1 true)
          (.. "error should mention family, got: " (tostring err))))

(fn diagnostic-violation-requires-message []
  (local Diagnostics (require :constraints.diagnostics))
  (local (ok err) (pcall #(Diagnostics.violation
                            {:constraint-id "test"
                             :family "style"
                             :hint "fix it"})))
  (assert (not ok) "expected missing message to raise an error")
  (assert (string.find (tostring err) "message" 1 true)
          (.. "error should mention message, got: " (tostring err))))

(fn diagnostic-violation-requires-hint []
  (local Diagnostics (require :constraints.diagnostics))
  (local (ok err) (pcall #(Diagnostics.violation
                            {:constraint-id "test"
                             :family "style"
                             :message "bad"})))
  (assert (not ok) "expected missing hint to raise an error")
  (assert (string.find (tostring err) "hint" 1 true)
          (.. "error should mention hint, got: " (tostring err))))

(fn diagnostic-framework-failure-produces-normalized-diagnostic []
  (local Diagnostics (require :constraints.diagnostics))
  (local d (Diagnostics.framework-failure
             {:constraint-id "runner"
              :family "framework"
              :message "something crashed"
              :hint "check the runner"}))
  (assert (= d.constraint-id "runner") "constraint-id should be preserved")
  (assert (= d.family "framework") "family should be preserved")
  (assert (= d.severity :error) "severity should default to :error")
  (assert (= d.message "something crashed") "message should be preserved")
  (assert (= d.hint "check the runner") "hint should be preserved"))

(fn diagnostic-summary-counts-by-family []
  (local Diagnostics (require :constraints.diagnostics))
  (local diags
    [(Diagnostics.violation
       {:constraint-id "r1" :family "style" :message "m1" :hint "h1"})
     (Diagnostics.violation
       {:constraint-id "r2" :family "style" :message "m2" :hint "h2"})
     (Diagnostics.violation
       {:constraint-id "r3" :family "correctness" :severity :warning :message "m3" :hint "h3"})
     (Diagnostics.framework-failure
       {:constraint-id "f1" :family "framework" :message "m4" :hint "h4"})])
  (local summary (Diagnostics.summary :violations diags))
  (assert (= summary.total 4) "total should be 4")
  (assert (= summary.by-family.style 2) "style count should be 2")
  (assert (= summary.by-family.correctness 1) "correctness count should be 1")
  (assert (= summary.by-family.framework 1) "framework count should be 1")
  (assert (= summary.by-severity.error 3) "error count should be 3")
  (assert (= summary.by-severity.warning 1) "warning count should be 1"))

;; --- Runner tests ---

(fn runner-noop-rule-returns-pass []
  (local Runner (require :constraints.runner))
  (local result (Runner.run
                  {:rules [(fn [_target] nil)]
                   :target {:kind :files :name "test-target"}}))
  (assert (= result.status :pass) (.. "expected :pass, got " (tostring result.status)))
  (assert (= result.counts.total 0) "expected 0 diagnostics for no-op rule")
  (assert (= (# result.diagnostics) 0) "expected empty diagnostics list"))

(fn runner-violation-rule-returns-violations []
  (local Runner (require :constraints.runner))
  (local Diagnostics (require :constraints.diagnostics))
  (local result (Runner.run
                  {:rules [(fn [_target]
                             (Diagnostics.violation
                               {:constraint-id "test-rule"
                                :family "style"
                                :message "something wrong"
                                :hint "fix it"}))]
                   :target {:kind :files :name "test-target"}}))
  (assert (= result.status :violations) (.. "expected :violations, got " (tostring result.status)))
  (assert (= result.counts.total 1) "expected 1 diagnostic")
  (assert (= (# result.diagnostics) 1) "expected 1 diagnostic in list")
  (local d (. result.diagnostics 1))
  (assert (= (. d :constraint-id) "test-rule") "diagnostic should include constraint-id")
  ;; R1-2: every emitted diagnostic includes the runner's target
  (assert (. d :target) "diagnostic should include target")
  (assert (= (. d :target :kind) :files) "target kind should be files")
  (assert (= (. d :target :name) "test-target") "target name should be test-target"))

(fn runner-crashing-rule-returns-fail []
  (local Runner (require :constraints.runner))
  (local result (Runner.run
                  {:rules [(fn [_target]
                             (error "boom"))]
                   :target {:kind :files :name "test-target"}}))
  (assert (= result.status :fail) (.. "expected :fail, got " (tostring result.status)))
  (assert (= result.counts.total 1) "expected 1 diagnostic for crashing rule")
  (assert (= (# result.diagnostics) 1) "expected 1 diagnostic in list")
  (local d (. result.diagnostics 1))
  (assert (= (. d :family) "framework") "crash diagnostic should have family framework")
  ;; R1-2: framework-failure diagnostic includes the runner's target
  (assert (. d :target) "crash diagnostic should include target")
  (assert (= (. d :target :kind) :files) "target kind should be files")
  (assert (= (. d :target :name) "test-target") "target name should be test-target"))

(fn runner-status-precedence []
  (local Runner (require :constraints.runner))
  (local Diagnostics (require :constraints.diagnostics))
  ;; pass + violations = violations
  (local result1 (Runner.run
                   {:rules [(fn [_target] nil)
                            (fn [_target]
                              (Diagnostics.violation
                                {:constraint-id "r1"
                                 :family "style"
                                 :message "issue"
                                 :hint "fix it"}))]
                    :target {:kind :files :name "precedence-test"}}))
  (assert (= result1.status :violations) (.. "pass + violations should be :violations, got " (tostring result1.status)))
  ;; violations + fail = fail
  (local result2 (Runner.run
                   {:rules [(fn [_target]
                              (Diagnostics.violation
                                {:constraint-id "r1"
                                 :family "style"
                                 :message "issue"
                                 :hint "fix it"}))
                            (fn [_target]
                              (error "crash"))]
                    :target {:kind :files :name "precedence-test"}}))
  (assert (= result2.status :fail) (.. "violations + fail should be :fail, got " (tostring result2.status))))

(fn runner-main-prints-json-and-exits-zero-on-pass []
  (local Runner (require :constraints.runner))
  (var printed nil)
  (var exit-code nil)
  (local fake-print (fn [msg] (set printed msg)))
  (local fake-exit (fn [code] (set exit-code code)))
  (Runner.main {:rules [(fn [_target] nil)]
                :target {:kind :files :name "test"}
                :print fake-print
                :exit fake-exit})
  (assert printed "expected print to be called")
  (local json (require :json))
  (local (ok parsed) (pcall json.loads printed))
  (assert ok (.. "expected valid JSON, got: " (tostring printed)))
  (assert (= parsed.status :pass) (.. "no rules should yield :pass, got " (tostring parsed.status)))
  (assert (= parsed.counts.total 0) "no rules should yield 0 diagnostics")
  (assert exit-code "expected exit to be called")
  (assert (= exit-code 0) "pass should exit 0"))

(fn runner-main-prints-json-and-exits-nonzero-on-violations []
  (local Runner (require :constraints.runner))
  (local Diagnostics (require :constraints.diagnostics))
  (var printed nil)
  (var exit-code nil)
  (local fake-print (fn [msg] (set printed msg)))
  (local fake-exit (fn [code] (set exit-code code)))
  (Runner.main {:rules [(fn [_target]
                          (Diagnostics.violation
                            {:constraint-id "test"
                             :family "style"
                             :message "bad"
                             :hint "fix"}))]
                :target {:kind :files :name "test"}
                :print fake-print
                :exit fake-exit})
  (assert printed "expected print to be called")
  (local json (require :json))
  (local (ok parsed) (pcall json.loads printed))
  (assert ok (.. "expected valid JSON, got: " (tostring printed)))
  (assert (= parsed.status :violations) (.. "expected :violations, got " (tostring parsed.status)))
  (assert (= parsed.counts.total 1) "expected 1 diagnostic")
  (assert exit-code "expected exit to be called")
  (assert (not= exit-code 0) (.. "violations should exit non-zero, got " (tostring exit-code))))

;; R1-1: Runner.main tolerates nil opts (runtime zero-arg entry point)
(fn runner-main-handles-nil-opts []
  (local Runner (require :constraints.runner))
  ;; The runtime calls module functions with no arguments.
  ;; Verify Runner.main does not crash when opts is nil.
  ;; We stub os.exit because the real one would terminate the test process.
  (var exit-code nil)
  (local orig-exit os.exit)
  (tset os :exit (fn [code] (set exit-code code)))
  (local (ok err) (pcall #(Runner.main)))  ;; nil opts
  (tset os :exit orig-exit)
  (assert ok (.. "Runner.main(nil) must not crash, got: " (tostring err)))
  (assert exit-code "exit should have been called"))

;; R1-3: timeout produces :interrupted status
(fn runner-timeout-produces-interrupted []
  (local Runner (require :constraints.runner))
  ;; A busy-loop rule with a short timeout should be interrupted.
  (fn busy-rule [_target]
    ;; Tight loop: keep CPU busy so the timer hook fires
    (var i 0)
    (while true
      (set i (+ i 1))))
  (local result (Runner.run
                  {:rules [busy-rule]
                   :target {:kind :files :name "timeout-test"}
                   :timeout-seconds 0.1}))
  (assert (= result.status :interrupted)
          (.. "expected :interrupted for timed-out rule, got " (tostring result.status)))
  (assert (= result.counts.total 1) "expected 1 diagnostic for interrupted rule")
  (assert (= (# result.diagnostics) 1) "expected 1 diagnostic in list")
  (local d (. result.diagnostics 1))
  (assert (. d :interrupted) "interrupted diagnostic should have :interrupted flag")
  (assert (. d :target) "interrupted diagnostic should include target"))

;; R1-3: interrupted wins precedence over fail
(fn runner-interrupted-precedence-over-fail []
  (local Runner (require :constraints.runner))
  (local Diagnostics (require :constraints.diagnostics))
  ;; A violation rule first, then a timed-out rule. Result should be :interrupted.
  (fn busy-rule [_target]
    (var i 0)
    (while true
      (set i (+ i 1))))
  (local result (Runner.run
                  {:rules [(fn [_target]
                             (Diagnostics.violation
                               {:constraint-id "v1"
                                :family "style"
                                :message "violation"
                                :hint "fix"}))
                           busy-rule]
                   :target {:kind :files :name "precedence-interrupt"}
                   :timeout-seconds 0.1}))
  (assert (= result.status :interrupted)
          (.. "violations + interrupted should be :interrupted, got " (tostring result.status))))

;; Known limitation: timeout uses a Lua instruction-count debug hook
;; (debug.sethook) and os.clock (CPU time).  Neither can preempt
;; blocking C/library calls such as os.execute.  This regression test
;; documents that rules with brief blocking calls complete normally
;; rather than hanging the gate.
(fn runner-blocking-call-completes-despite-timeout-limitation []
  (local Runner (require :constraints.runner))
  (var rule-finished false)
  (fn rule-with-blocking-call [_target]
    ;; os.execute blocks the Lua VM; the timeout hook cannot fire during it.
    (os.execute "sleep 0.1")
    (set rule-finished true))
  (local result (Runner.run
                  {:rules [rule-with-blocking-call]
                   :target {:kind :files :name "blocking-limitation"}
                   :timeout-seconds 0.5}))
  (assert rule-finished
          "rule should complete after brief blocking call")
  (assert (= result.status :pass)
          (.. "expected :pass (timeout hook cannot interrupt os.execute), got "
              (tostring result.status))))

;; Register tests
(table.insert tests {:name "diagnostic violation normalizes fields"
                     :fn diagnostic-violation-normalizes-fields})
(table.insert tests {:name "diagnostic violation defaults severity and evidence"
                     :fn diagnostic-violation-defaults-severity-and-evidence})
(table.insert tests {:name "diagnostic violation requires constraint-id"
                     :fn diagnostic-violation-requires-constraint-id})
(table.insert tests {:name "diagnostic violation requires family"
                     :fn diagnostic-violation-requires-family})
(table.insert tests {:name "diagnostic violation requires message"
                     :fn diagnostic-violation-requires-message})
(table.insert tests {:name "diagnostic violation requires hint"
                     :fn diagnostic-violation-requires-hint})
(table.insert tests {:name "diagnostic framework-failure produces normalized diagnostic"
                     :fn diagnostic-framework-failure-produces-normalized-diagnostic})
(table.insert tests {:name "diagnostic summary counts by family"
                     :fn diagnostic-summary-counts-by-family})
(table.insert tests {:name "runner noop rule returns pass"
                     :fn runner-noop-rule-returns-pass})
(table.insert tests {:name "runner violation rule returns violations"
                     :fn runner-violation-rule-returns-violations})
(table.insert tests {:name "runner crashing rule returns fail"
                     :fn runner-crashing-rule-returns-fail})
(table.insert tests {:name "runner status precedence"
                     :fn runner-status-precedence})
(table.insert tests {:name "runner main prints JSON and exits zero on pass"
                     :fn runner-main-prints-json-and-exits-zero-on-pass})
(table.insert tests {:name "runner main prints JSON and exits nonzero on violations"
                     :fn runner-main-prints-json-and-exits-nonzero-on-violations})
(table.insert tests {:name "runner main handles nil opts (runtime convention)"
                     :fn runner-main-handles-nil-opts})
(table.insert tests {:name "runner timeout produces interrupted status"
                     :fn runner-timeout-produces-interrupted})
(table.insert tests {:name "runner interrupted precedence over fail"
                     :fn runner-interrupted-precedence-over-fail})
(table.insert tests {:name "runner timeout cannot interrupt blocking calls (known limitation)"
                     :fn runner-blocking-call-completes-despite-timeout-limitation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-runner"
                       :tests tests})))

{:name "constraints-runner"
 :tests tests
 :main main}
