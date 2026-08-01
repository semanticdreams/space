;; Tests for Test-Isolation with-restored-app wrapper recognition.
;; Separate module to keep precision file under module-length limit.

(local tests [])

;; --- Helpers ---

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
;; T11-WRA: with-restored-app wrapper recognition (same-file def required)
;; ======================================================================

(fn mutation-restoration-allows-with-restored-app-wrapper []
  "T11-WRA-1: Anonymous fn mutation inside with-restored-app wrapper body
   should pass when the same file has a valid with-restored-app definition
   with restoring semantics (snapshot, pcall, restore).
   Models the test-sandbox-activity.fnl pattern."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; Same-file definition: with-restored-app with restoring semantics
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 200
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  ;; Named test function wrapping anon fn with with-restored-app
  (table.insert ff.definitions {:kind :fn
                                 :name "test-with-restored"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 200
                                 :form "(fn test-with-restored []
  (with-restored-app [:engine :renderers]
    (fn []
      (set app.engine custom-engine)
      (set app.renderers custom))))"})
  ;; Anonymous callback fn
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 18 :column 5
                                 :length 80
                                 :form "(fn []
      (set app.engine custom-engine)
      (set app.renderers custom))"})
  ;; Mutations inside the anon callback
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 19 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "renderers"]
                               :line 20 :column 7
                               :form "(set app.renderers custom)"
                               :enclosing-fn "<anonymous>"})
  (assert (= (rule.run (make-ctx [ff])) nil)
          "T11-WRA-1: with-restored-app wrapper with valid same-file def should pass"))

(fn mutation-restoration-flags-with-restored-app-no-same-file-def []
  "T11-WRA-2: with-restored-app wrapper should NOT suppress diagnostics
   when no same-file with-restored-app helper definition exists.
   The wrapper call alone is not sufficient — the file must define
   the helper with restoring semantics."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; NO with-restored-app definition — only the test function using it
  (table.insert ff.definitions {:kind :fn
                                 :name "test-no-helper-def"
                                 :top-level? true
                                 :line 10 :column 1
                                 :length 150
                                 :form "(fn test-no-helper-def []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 12 :column 5
                                 :length 20
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 13 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "T11-WRA-2: should flag — no same-file with-restored-app def")
  (assert (> (length result) 0) "T11-WRA-2: should have at least one diagnostic"))

(fn mutation-restoration-flags-with-restored-app-def-without-pcall []
  "T11-WRA-3: A same-file with-restored-app definition that lacks pcall
   (and thus does not have restoring semantics) should NOT suppress diagnostics.
   The helper must have snapshot + pcall f + restore to be recognized."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; with-restored-app without pcall — just snapshots and restores, no pcall
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 100
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (f)
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-no-pcall-def"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 150
                                 :form "(fn test-no-pcall-def []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 17 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 18 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "T11-WRA-3: should flag — helper def has no pcall")
  (assert (> (length result) 0) "T11-WRA-3: should have at least one diagnostic"))

(fn mutation-restoration-flags-with-restored-app-unlisted-field []
  "T11-WRA-4: with-restored-app wrapper key list [:engine] does NOT cover
   app.renderers. Mutation on app.renderers inside the wrapper body should
   still be flagged — key coverage must include the mutated path."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 200
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-unlisted-key"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 150
                                 :form "(fn test-unlisted-key []
  (with-restored-app [:engine]
    (fn []
      (set app.renderers custom))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 17 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.renderers custom))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "renderers"]
                               :line 18 :column 7
                               :form "(set app.renderers custom)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "T11-WRA-4: should flag — wrapper key does not cover renderers")
  (assert (> (length result) 0) "T11-WRA-4: should have at least one diagnostic"))

(fn mutation-restoration-flags-mutation-outside-with-restored-app []
  "T11-WRA-5: with-restored-app wraps one anon fn, but a separate sibling
   anonymous fn mutates app.engine outside the wrapper. The unwrapped sibling
   should still be flagged — wrapper recognition must be position-aware."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 200
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-outside-wrapper"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 200
                                 :form "(fn test-outside-wrapper []
  (with-restored-app [:engine :renderers]
    (fn [] (set app.engine wrapped-engine)))
  (fn [] (set app.engine leaky-engine)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 17 :column 5
                                 :length 30
                                 :form "(fn [] (set app.engine wrapped-engine))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 18 :column 5
                                 :length 30
                                 :form "(fn [] (set app.engine leaky-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 17 :column 12
                               :form "(set app.engine wrapped-engine)"
                               :enclosing-fn "<anonymous>"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 18 :column 12
                               :form "(set app.engine leaky-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "T11-WRA-5: should flag — unwrapped sibling mutation")
  (local engine-diags [])
  (each [_ d (ipairs result)]
    (when (and d.evidence (= d.evidence.global-path "app.engine"))
      (table.insert engine-diags d)))
  (assert (> (length engine-diags) 0)
          "T11-WRA-5: unwrapped app.engine sibling should be flagged"))

(fn mutation-restoration-real-file-regression-sandbox-activity []
  "T11-WRA-RF: Real-file regression. test-sandbox-activity.fnl should
   produce ZERO lifecycle.global-mutation-restoration diagnostics after
   with-restored-app wrapper recognition is implemented."
  (local fs (require :fs))
  (local assets-path (if (os.getenv "SPACE_ASSETS_PATH") (os.getenv "SPACE_ASSETS_PATH") "assets"))
  (local lua-root (fs.join-path assets-path "lua"))
  (local Source (require :constraints.source))
  (local Facts (require :constraints.facts))
  (local sandbox-path (fs.absolute (fs.join-path lua-root "tests" "test-sandbox-activity.fnl")))
  (local target {:kind :files
                 :files [sandbox-path]
                 :module-roots [(fs.absolute lua-root)]})
  (local source-records (Source.discover target))
  (local fact-db (Facts.extract source-records))
  (local rule (get-test-isolation-rule))
  (local ctx {:target {:kind :repo :name :test} :facts fact-db :files []})
  (local result (rule.run ctx))
  (if result
      (do
        (var sandbox-count 0)
        (each [_ d (ipairs result)]
          (when (string.find (or d.file "") "test-sandbox-activity" 1 true)
            (set sandbox-count (+ sandbox-count 1))))
        (assert (= sandbox-count 0)
                (.. "T11-WRA-RF: expected 0 sandbox-activity diagnostics, got " sandbox-count)))
      (assert true "T11-WRA-RF: pass - no diagnostics returned")))

;; ======================================================================
;; R1-1: Tightened helper definition semantic-shape matching
;; ======================================================================

(fn mutation-restoration-flags-with-restored-app-def-missing-snapshot-loop []
  "R1-1a: Same-file with-restored-app helper that has a restore loop and
   pcall(f) but NO snapshot loop (no (. snapshot key) (. app key) pattern)
   should NOT suppress diagnostics. The helper must have all three markers."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; with-restored-app without snapshot loop — just pcall + restore
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 100
                                 :form "(fn with-restored-app [fields f]
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-no-snapshot"
                                 :top-level? true
                                 :line 12 :column 1
                                 :length 120
                                 :form "(fn test-no-snapshot []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 14 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 15 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1a: should flag — helper def missing snapshot loop")
  (assert (> (length result) 0) "R1-1a: should have at least one diagnostic"))

(fn mutation-restoration-flags-with-restored-app-def-missing-restore-loop []
  "R1-1b: Same-file with-restored-app helper that snapshots and runs pcall(f)
   but has NO restore loop should NOT suppress diagnostics."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; with-restored-app without restore loop
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 100
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-no-restore"
                                 :top-level? true
                                 :line 14 :column 1
                                 :length 120
                                 :form "(fn test-no-restore []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 16 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 17 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1b: should flag — helper def missing restore loop")
  (assert (> (length result) 0) "R1-1b: should have at least one diagnostic"))

(fn mutation-restoration-flags-with-restored-app-def-pcall-of-other-fn []
  "R1-1c: Same-file with-restored-app helper that calls (pcall g) on some
   other function g (not the f parameter) should NOT suppress diagnostics.
   The helper must call (pcall f) specifically — the wrapper callback."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; with-restored-app calling pcall on wrong function
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 120
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall some-other-fn))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-pcall-other-fn"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 120
                                 :form "(fn test-pcall-other-fn []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 17 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 18 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1c: should flag — pcall of other fn, not f")
  (assert (> (length result) 0) "R1-1c: should have at least one diagnostic"))

(fn mutation-restoration-flags-unrelated-same-name-helper []
  "R1-1d: A same-file function named with-restored-app that does completely
   different work (not snapshot/restore of app) should NOT suppress diagnostics.
   Same name alone is insufficient — the definition must have restoring semantics."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; with-restored-app that does unrelated logging, not snapshot/restore
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 60
                                 :form "(fn with-restored-app [fields f]
  (print \"restoring\" fields)
  (f))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-unrelated-helper"
                                 :top-level? true
                                 :line 10 :column 1
                                 :length 120
                                 :form "(fn test-unrelated-helper []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 12 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 13 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1d: should flag — unrelated same-name helper")
  (assert (> (length result) 0) "R1-1d: should have at least one diagnostic"))

;; ======================================================================
;; R1-2: Exact callee match — reject similarly-named wrapper calls
;; ======================================================================

(fn mutation-restoration-flags-similarly-named-wrapper []
  "R1-2a: A not-with-restored-app call should NOT be mistaken for a
   with-restored-app wrapper. The token match must be exact at call position."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; Valid with-restored-app def exists in file
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 200
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  ;; Test function uses not-with-restored-app (not a wrapper, just a call)
  (table.insert ff.definitions {:kind :fn
                                 :name "test-similarly-named"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 120
                                 :form "(fn test-similarly-named []
  (not-with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 17 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 18 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-2a: should flag — similarly-named non-wrapper call")
  (assert (> (length result) 0) "R1-2a: should have at least one diagnostic"))

;; ======================================================================
;; R1-1-fix: Ordered semantic structure — snapshot before pcall, restore after
;; ======================================================================

(fn mutation-restoration-flags-pcall-before-snapshot-restore []
  "R1-1e: Helper calls (pcall f) BEFORE snapshot+restore assignments.
   The correct ordering is snapshot before pcall, restore after pcall.
   A helper that runs pcall first (mutating app), then snapshots the
   already-mutated state and restores from it should NOT be accepted.
   The snapshot assignment must appear BEFORE (pcall f) in the form."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; pcall before snapshot+restore — wrong order
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 150
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-pcall-first"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 120
                                 :form "(fn test-pcall-first []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 17 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 18 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1e: should flag — pcall before snapshot+restore")
  (assert (> (length result) 0) "R1-1e: should have at least one diagnostic"))

;; ======================================================================
;; R1-2-fix: Trailing boundary — reject suffix callee names
;; ======================================================================

(fn mutation-restoration-flags-suffix-callee-name []
  "R1-2b: with-restored-app-extra should NOT be mistaken for a
   with-restored-app wrapper. Both leading and trailing identifier
   boundaries must be checked. The trailing '-' after 'with-restored-app'
   makes it a different identifier."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; Valid with-restored-app def exists in file
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 200
                                 :form "(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))"})
  ;; Test function uses with-restored-app-extra (suffix, different name)
  (table.insert ff.definitions {:kind :fn
                                 :name "test-suffix-callee"
                                 :top-level? true
                                 :line 15 :column 1
                                 :length 120
                                 :form "(fn test-suffix-callee []
  (with-restored-app-extra [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 17 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 18 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-2b: should flag — suffix callee name should not match")
  (assert (> (length result) 0) "R1-2b: should have at least one diagnostic"))

;; Register all tests
(table.insert tests {:name "T11-WRA-1 allows with-restored-app wrapper" :fn mutation-restoration-allows-with-restored-app-wrapper})
(table.insert tests {:name "T11-WRA-2 flags no same-file def" :fn mutation-restoration-flags-with-restored-app-no-same-file-def})
(table.insert tests {:name "T11-WRA-3 flags def without pcall" :fn mutation-restoration-flags-with-restored-app-def-without-pcall})
(table.insert tests {:name "T11-WRA-4 flags unlisted field" :fn mutation-restoration-flags-with-restored-app-unlisted-field})
(table.insert tests {:name "T11-WRA-5 flags mutation outside wrapper" :fn mutation-restoration-flags-mutation-outside-with-restored-app})
(table.insert tests {:name "T11-WRA-RF real-file regression sandbox-activity" :fn mutation-restoration-real-file-regression-sandbox-activity})
(table.insert tests {:name "R1-1a flags missing snapshot loop" :fn mutation-restoration-flags-with-restored-app-def-missing-snapshot-loop})
(table.insert tests {:name "R1-1b flags missing restore loop" :fn mutation-restoration-flags-with-restored-app-def-missing-restore-loop})
(table.insert tests {:name "R1-1c flags pcall of other fn" :fn mutation-restoration-flags-with-restored-app-def-pcall-of-other-fn})
(table.insert tests {:name "R1-1d flags unrelated same-name helper" :fn mutation-restoration-flags-unrelated-same-name-helper})
(table.insert tests {:name "R1-2a flags similarly-named wrapper call" :fn mutation-restoration-flags-similarly-named-wrapper})
(table.insert tests {:name "R1-1e flags pcall before snapshot+restore" :fn mutation-restoration-flags-pcall-before-snapshot-restore})
(table.insert tests {:name "R1-2b flags suffix callee name" :fn mutation-restoration-flags-suffix-callee-name})

;; ======================================================================
;; R1-1f: Marker substrings in string literals — must not match
;; ======================================================================

(fn mutation-restoration-flags-marker-substrings-in-strings []
  "R1-1f: A malformed helper that puts the marker substrings inside
   string literals around (pcall f) should NOT be accepted. The
   validation must check actual Fennel forms, not arbitrary text."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; Malformed helper: marker substrings only in string literals
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 150
                                 :form "(fn with-restored-app [fields f]
  (print \"(. snapshot key) (. app key)\")
  (local (ok result) (pcall f))
  (print \"(. app key) (. snapshot key)\")
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-strings-only"
                                 :top-level? true
                                 :line 14 :column 1
                                 :length 120
                                 :form "(fn test-strings-only []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 16 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 17 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1f: should flag — markers only in string literals")
  (assert (> (length result) 0) "R1-1f: should have at least one diagnostic"))

(table.insert tests {:name "R1-1f flags markers in string literals" :fn mutation-restoration-flags-marker-substrings-in-strings})

;; ======================================================================
;; R1-1g: Marker substrings in comments — must not match
;; ======================================================================

(fn mutation-restoration-flags-marker-substrings-in-comments []
  "R1-1g: A malformed helper that puts the marker substrings inside
   Fennel comments around (pcall f) should NOT be accepted. The
   validation must use actual Fennel forms, not comment text."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; Malformed helper: marker substrings only in comments
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 150
                                 :form "(fn with-restored-app [fields f]
  ; (. snapshot key) (. app key) — not actual code
  (local (ok result) (pcall f))
  ; (. app key) (. snapshot key) — not actual code
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-comments-only"
                                 :top-level? true
                                 :line 14 :column 1
                                 :length 120
                                 :form "(fn test-comments-only []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 16 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 17 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1g: should flag — markers only in comments")
  (assert (> (length result) 0) "R1-1g: should have at least one diagnostic"))

(table.insert tests {:name "R1-1g flags markers in comments" :fn mutation-restoration-flags-marker-substrings-in-comments})

;; ======================================================================
;; R1-1h: Operand substrings in non-set forms (e.g., print) — must flag
;; ======================================================================

(fn mutation-restoration-flags-non-set-operands-around-pcall []
  "R1-1h: A malformed helper that uses (print (. snapshot key) (. app key))
   before (pcall f) and (print (. app key) (. snapshot key)) after pcall
   should NOT be accepted. The operands appear in non-assignment (print)
   contexts — the validation must require actual (set ...) assignment forms.
   This is the core regression for the concrete-assignment-shape fix."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"}))
  ;; Malformed helper: operands in print calls, not actual set assignments
  (table.insert ff.definitions {:kind :fn
                                 :name "with-restored-app"
                                 :top-level? true
                                 :line 1 :column 1
                                 :length 150
                                 :form "(fn with-restored-app [fields f]
  (print (. snapshot key) (. app key))
  (local (ok result) (pcall f))
  (print (. app key) (. snapshot key))
  (if ok result (error result)))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "test-print-operands"
                                 :top-level? true
                                 :line 14 :column 1
                                 :length 120
                                 :form "(fn test-print-operands []
  (with-restored-app [:engine]
    (fn []
      (set app.engine custom-engine))))"})
  (table.insert ff.definitions {:kind :fn
                                 :name "<anonymous>"
                                 :top-level? false
                                 :line 16 :column 5
                                 :length 15
                                 :form "(fn []
      (set app.engine custom-engine))"})
  (table.insert ff.mutations {:op :set
                               :path ["app" "engine"]
                               :line 17 :column 7
                               :form "(set app.engine custom-engine)"
                               :enclosing-fn "<anonymous>"})
  (local result (rule.run (make-ctx [ff])))
  (assert result "R1-1h: should flag — operands in print, not set assignments")
  (assert (> (length result) 0) "R1-1h: should have at least one diagnostic"))

(table.insert tests {:name "R1-1h flags non-set operands around pcall" :fn mutation-restoration-flags-non-set-operands-around-pcall})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-test-isolation-wra" :tests tests})))

{:name "constraints-rules-test-isolation-wra" :tests tests :main main}
