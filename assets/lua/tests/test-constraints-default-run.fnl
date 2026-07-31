;; Tests for RuleRegistry and default repo execution.

(local tests [])

;; --- RuleRegistry tests ---

(fn rule-registry-all-rules-returns-all-required-ids []
  "Prove that RuleRegistry.all-rules returns every id in baseline-data.required-rule-ids."
  (local RuleRegistry (require :constraints.rules.init))
  (local BaselineData (require :constraints.baseline-data))
  (local rules (RuleRegistry.all-rules))
  (assert (= (type rules) "table") "all-rules should return a table")
  (assert (> (# rules) 0) "should return at least one rule")

  ;; Collect all rule IDs from the registry
  (local registry-ids {})
  (each [_ rule (ipairs rules)]
    (let [id (or rule.id rule.constraint-id "unknown")]
      (tset registry-ids id true)))

  ;; Verify every required rule ID is present
  (each [_ required-id (ipairs BaselineData.required-rule-ids)]
    (assert (. registry-ids required-id)
            (.. "required rule not in registry: " required-id)))

  ;; Verify deterministic family order:
  ;; scene-sandbox first, lifecycle second, test-isolation third,
  ;; layout-rendering fourth, structure-formatting last.
  (var last-family nil)
  (local family-order [])
  (each [_ rule (ipairs rules)]
    (let [fam (or rule.family "")]
      (when (or (= (# family-order) 0)
                (not= fam (. family-order (# family-order))))
        (table.insert family-order fam))))
  (assert (>= (# family-order) 5) "expected at least 5 families")
  (assert (or (= (. family-order 1) "scene-sandbox")
              (string.find (. family-order 1) "scene" 1 true))
          (.. "first family should be scene-sandbox, got " (. family-order 1)))
  (assert (= (. family-order 5) "structure-formatting")
          (.. "last family should be structure-formatting, got " (. family-order 5))))

(fn rule-registry-all-rules-are-well-formed []
  "Each rule entry must have :id, :family, :targets, :kind, :run, and :fn."
  (local RuleRegistry (require :constraints.rules.init))
  (local rules (RuleRegistry.all-rules))
  (each [_ rule (ipairs rules)]
    (assert (or rule.id rule.constraint-id)
            (.. "rule missing id: " (tostring (or rule.id rule.constraint-id "nil"))))
    (assert rule.family (.. "rule missing family: " (or rule.id "nil")))
    (assert rule.targets (.. "rule missing targets: " (or rule.id "nil")))
    (assert rule.kind (.. "rule missing kind: " (or rule.id "nil")))
    (assert rule.run (.. "rule missing run: " (or rule.id "nil")))
    (assert rule.fn (.. "rule missing fn: " (or rule.id "nil")))
    ;; Verify target is a known target kind
    (each [_ tgt (ipairs rule.targets)]
      (let [allowed {:repo true :unit true :app true :files true}]
        (assert (. allowed tgt) (.. "unknown target kind: " (tostring tgt)))))))

;; --- Runner.run-target tests ---

(fn runner-run-target-returns-structured-result []
  "Prove run-target returns a proper result with status, counts, and diagnostics."
  (local Runner (require :constraints.runner))
  (local fs (require :fs))
  ;; Build a files target pointing to the minimal test fixture
  (local fixture-path (fs.absolute "assets/lua/tests/data/constraint-fixture.fnl"))
  (local target {:kind :files
                 :name "constraint-fixture"
                 :roots []
                 :files [fixture-path]
                  :module-roots []
                  :suites [:scene-sandbox :lifecycle :test-isolation :layout-rendering :structure-formatting]})
  (local result (Runner.run-target target {:baseline-data false}))
  ;; Verify result structure
  (assert (= (type result) "table") "result should be a table")
  (assert result.status (.. "result should have status, got " (tostring result)))
  (assert result.counts (.. "result should have counts, got " (tostring result)))
  (assert result.diagnostics (.. "result should have diagnostics, got " (tostring result)))
  (assert (= (type result.diagnostics) "table") "diagnostics should be a table")
  ;; Verify counts structure
  (assert (>= result.counts.total 0) "counts.total should be non-negative")
  (assert result.counts.by-family (.. "counts should have by-family, got " (tostring result)))
  (assert result.counts.by-severity (.. "counts should have by-severity, got " (tostring result))))

(fn runner-run-target-diagnostics-include-target-metadata []
  "Prove that every diagnostic from run-target includes target.kind and target.name."
  (local Runner (require :constraints.runner))
  (local fs (require :fs))
  ;; Use a minimal files target — any diagnostics produced must carry target metadata
  (local fixture-path (fs.absolute "assets/lua/tests/data/constraint-fixture.fnl"))
  (local target {:kind :files
                 :name "metadata-test-target"
                 :roots []
                 :files [fixture-path]
                 :module-roots []
                 :suites [:scene-sandbox :lifecycle :test-isolation :layout-rendering :structure-formatting]})
  (local result (Runner.run-target target {:baseline-data false}))
  ;; Check that all diagnostics include target metadata
  (each [_ d (ipairs result.diagnostics)]
    (assert (. d :target) (.. "diagnostic missing target, constraint-id: " (or d.constraint-id "nil")))
    (if (. d :target)
        (do
          (assert (. d.target :kind)
                  (.. "diagnostic target missing kind, constraint-id: " (or d.constraint-id "nil")))
          (assert (. d.target :name)
                  (.. "diagnostic target missing name, constraint-id: " (or d.constraint-id "nil")))))))

(fn runner-run-target-explicit-files-target-works []
  "Prove that a non-repo files target can run through the same pipeline."
  (local Runner (require :constraints.runner))
  (local fs (require :fs))
  (local fixture-path (fs.absolute "assets/lua/tests/data/constraint-fixture.fnl"))
  (local target {:kind :files
                 :name "explicit-files-test"
                 :roots []
                 :files [fixture-path]
                 :module-roots []
                 :suites [:scene-sandbox :lifecycle :test-isolation :layout-rendering :structure-formatting]})
  (local result (Runner.run-target target {:baseline-data false}))
  ;; Should not crash; the fixture file is well-formed Fennel
  (assert (= (type result) "table") "run-target should return a table")
  (assert result.status "run-target should return a status")
  (assert (or (= result.status :pass)
              (= result.status :violations)
              (= result.status :fail)
              (= result.status :interrupted))
          (.. "status should be one of :pass, :violations, :fail, :interrupted, got "
              (tostring result.status))))

(fn runner-run-target-with-repo-target-runs-full-pipeline []
  "Prove that run-target with a repo target discovers files, extracts facts,
  runs rules, and applies baseline — returns a structured, non-empty result."
  (local Runner (require :constraints.runner))
  (local fs (require :fs))
  (local lua-dir (fs.absolute "assets/lua"))
  (local target {:kind :repo
                 :name "repo"
                 :roots [lua-dir]
                 :files []
                 :module-roots [lua-dir]
                 :suites [:scene-sandbox :lifecycle :test-isolation :layout-rendering :structure-formatting]})
  (local result (Runner.run-target target {:baseline-data false}))
  ;; Should complete without crash; the real repo will have violations.
  (assert (= (type result) "table") "run-target should return a table")
  (assert result.status "run-target should return a status")
  (assert (>= result.counts.total 0) "counts.total should be non-negative")
  ;; The real repo should produce some diagnostics (our codebase has violations)
  (assert (> result.counts.total 0) "repo target should produce diagnostics")
  ;; Verify diagnostics include actual file paths and constraint-ids
  (var has-file false)
  (var has-constraint-id false)
  (each [_ d (ipairs result.diagnostics)]
    (when (and d.file (> (length d.file) 0)) (set has-file true))
    (when (and d.constraint-id (> (length d.constraint-id) 0)) (set has-constraint-id true)))
  (assert has-file "at least one diagnostic should have a file")
  (assert has-constraint-id "at least one diagnostic should have a constraint-id"))

;; --- Runner.main argv tests ---

(fn default-target-suites-match-rule-families []
  "Prove that all registry rule families are represented in the default target
  suites so that no required rule is filtered out before execution."
  (local RuleRegistry (require :constraints.rules.init))
  (local Targets (require :constraints.targets))
  (local BaselineData (require :constraints.baseline-data))
  ;; Resolve the default repo target — same path Runner.main nil-argv takes.
  (local target (Targets.resolve [] {}))
  (local target-suites (or target.suites []))
  ;; Collect all unique family names from the registry
  (local registry-families {})
  (local all-rules (RuleRegistry.all-rules))
  (each [_ rule (ipairs all-rules)]
    (tset registry-families rule.family true))
  ;; Every target suite name should match a real rule family
  (each [_ suite (ipairs target-suites)]
    (assert (. registry-families suite)
            (.. "target suite \"" suite "\" should match a rule family")))
  ;; Every registry family should be in the target suites
  (each [fam _ (pairs registry-families)]
    (var found false)
    (each [_ suite (ipairs target-suites)]
      (when (= suite fam) (set found true)))
    (assert found (.. "rule family \"" fam "\" should be in default target suites"))))

(fn default-target-runs-all-required-rules []
  "Prove that the default repo target executes every required MVP rule from
  the registry and no required rule is incorrectly filtered out."
  (local Runner (require :constraints.runner))
  (local RuleRegistry (require :constraints.rules.init))
  (local Targets (require :constraints.targets))
  (local BaselineData (require :constraints.baseline-data))
  ;; Resolve the default repo target — same path Runner.main nil-argv takes.
  (local target (Targets.resolve [] {}))
  ;; Collect all rule IDs from the registry
  (local all-rules (RuleRegistry.all-rules))
  (local registry-ids {})
  (each [_ rule (ipairs all-rules)]
    (let [id (or rule.id rule.constraint-id "unknown")]
      (tset registry-ids id true)))
  ;; Run the full pipeline with default baseline
  (local result (Runner.run-target target {}))
  (assert (= (type result) "table") "run-target should return a table")
  ;; Verify no missing-required diagnostic refers to a rule that exists
  ;; in the registry.  If a missing-required diagnostic fires for a rule
  ;; the registry knows about, it was incorrectly filtered out.
  (each [_ d (ipairs result.diagnostics)]
    (when (and (. d :missing-required) d.constraint-id)
      (assert (not (. registry-ids d.constraint-id))
              (.. "required rule \"" d.constraint-id "\" should not be missing — "
                  "it is in the registry but was filtered out"))))
  ;; Verify that every required rule id from baseline-data is in the registry.
  ;; If baseline-data requires a rule the registry does not publish, the test
  ;; must fail early rather than producing a false-missing signal at runtime.
  (each [_ required-id (ipairs BaselineData.required-rule-ids)]
    (assert (. registry-ids required-id)
            (.. "baseline-data requires \"" required-id
                "\" but it is not in the rule registry"))))

(fn runner-main-argv-defaults-to-repo []
  "Runner.main() with nil argv should default to repo target and execute pipeline."
  (local Runner (require :constraints.runner))
  (var printed nil)
  (var exit-code nil)
  (local fake-print (fn [msg] (set printed msg)))
  (local fake-exit (fn [code] (set exit-code code)))
  (Runner.main {:print fake-print :exit fake-exit})
  (assert printed "expected JSON output from default repo execution")
  (local json (require :json))
  (local (ok parsed) (pcall json.loads printed))
  (assert ok (.. "expected valid JSON, got: " (tostring printed)))
  (assert (= (type parsed) "table") "parsed JSON should be a table")
  (assert parsed.status (.. "parsed JSON should have status, got: " (tostring printed)))
  (assert parsed.counts (.. "parsed JSON should have counts, got: " (tostring printed)))
  (assert parsed.diagnostics (.. "parsed JSON should have diagnostics, got: " (tostring printed)))
  (assert exit-code "expected exit to be called")
  (assert (= exit-code 0)
          "repo target with cleaned real codebase should exit zero"))

;; Register tests
(table.insert tests {:name "rule-registry all-rules returns all required ids"
                     :fn rule-registry-all-rules-returns-all-required-ids})
(table.insert tests {:name "rule-registry all rules are well-formed"
                     :fn rule-registry-all-rules-are-well-formed})
(table.insert tests {:name "runner run-target returns structured result"
                     :fn runner-run-target-returns-structured-result})
(table.insert tests {:name "runner run-target diagnostics include target metadata"
                     :fn runner-run-target-diagnostics-include-target-metadata})
(table.insert tests {:name "runner run-target explicit files target works"
                     :fn runner-run-target-explicit-files-target-works})
(table.insert tests {:name "runner run-target with repo target runs full pipeline"
                     :fn runner-run-target-with-repo-target-runs-full-pipeline})
(table.insert tests {:name "default target suites match rule families"
                     :fn default-target-suites-match-rule-families})
(table.insert tests {:name "default target runs all required rules"
                     :fn default-target-runs-all-required-rules})
(table.insert tests {:name "runner main argv defaults to repo"
                     :fn runner-main-argv-defaults-to-repo})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-default-run"
                       :tests tests})))

{:name "constraints-default-run"
 :tests tests
 :main main}
