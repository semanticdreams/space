;; Tests for layout.interactive-context-assertion rule.
;; Auto-split from test-constraints-rules-layout.fnl.

(local H (require :tests.constraints-layout-helpers))
(local make-file-fact H.make-file-fact)
(local make-fact-db H.make-fact-db)
(local make-ctx H.make-ctx)
(local find-rule-by-id H.find-rule-by-id)
(local tests [])

;; layout.interactive-context-assertion
;; ======================================================================

(fn interactive-assertion-allows-file-without-clickables []
  "A file with no clickables/hoverables access should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule layout.interactive-context-assertion should be in rules list")
  (local ff (make-file-fact {:path "/src/clean-module.fnl"
                              :module "clean-module"
                              :definitions [{:kind :fn
                                             :name "render-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn render-widget [ctx]
  (print :hello))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file without clickables should pass"))

(fn interactive-assertion-allows-clickables-with-assert-call []
  "A function using clickables with an assert CALL (not just form text) should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "render-button"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn render-button [ctx]
  (let [cs (assert ctx.clickables \"missing\")]
    (set-clickables cs))"}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "render-button"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with clickables and assert call should pass"))

(fn interactive-assertion-allows-hoverables-with-assert-call []
  "A function using hoverables with an assert CALL should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "render-tooltip"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn render-tooltip [ctx]
  (let [hs (assert ctx.hoverables \"missing\")]
    (set-hoverables hs))"}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(assert ctx.hoverables \"missing\")"
                                       :enclosing-fn "render-tooltip"}]
                              :accesses [{:path ["ctx" "hoverables"]
                                          :text "ctx.hoverables"
                                          :line 6 :column 1
                                          :form "ctx.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with hoverables and assert call should pass"))

(fn interactive-assertion-flags-clickables-without-assert []
  "A function using clickables without assert should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-button"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-button [ctx]
  (let [cs ctx.clickables]
    (when cs
      (handle-clickables cs))))"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for clickables without assert")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "layout-rendering") "diagnostic should have family layout-rendering")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence"))

(fn interactive-assertion-flags-hoverables-without-assert []
  "A function using hoverables without assert should be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-tooltip"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-tooltip [ctx]
  (let [hs ctx.hoverables]
    (when hs
      (handle-hoverables hs))))"}]
                              :accesses [{:path ["ctx" "hoverables"]
                                          :text "ctx.hoverables"
                                          :line 6 :column 1
                                          :form "ctx.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for hoverables without assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should have correct constraint-id"))

(fn interactive-assertion-flags-assert-in-different-function []
  "A function using clickables without assert is flagged even if assert exists in another function."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-button"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-button [ctx]
  (let [cs ctx.clickables]
    (when cs (handle cs))))"}
                                            {:kind :fn
                                             :name "assert-routing"
                                             :top-level? true
                                             :line 20 :column 1
                                             :length 80
                                             :form "(fn assert-routing [ctx]
  (assert ctx.clickables \"missing\"))"}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 21 :column 1
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "assert-routing"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for clickables without assert in same function")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should have correct constraint-id"))

(fn interactive-assertion-flags-silent-guard-clickables []
  "A function guarding clickables silently (no assert call) should be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn render-widget [ctx]
  (or ctx.clickables {})
  (let [cs clickables]
    (each [_ c (ipairs cs)]
      (render c))))"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}
                                         {:path ["clickables"]
                                          :text "clickables"
                                          :line 7 :column 1
                                          :form "clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for silent guard on clickables")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn interactive-assertion-allows-bare-clickables-with-assert-call []
  "A function using bare 'clickables' with an assert CALL should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "render-panel"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn render-panel [ctx]
  (let [cs (assert clickables \"missing\")]
    (process cs))"}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(assert clickables \"missing\")"
                                       :enclosing-fn "render-panel"}]
                              :accesses [{:path ["clickables"]
                                          :text "clickables"
                                          :line 6 :column 1
                                          :form "clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "bare clickables with assert call should pass"))

(fn interactive-assertion-flags-hoverables-with-when-no-assert []
  "A function silently guarding hoverables should be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-tooltip"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-tooltip [ctx]
  (when ctx.hoverables
    (handle ctx.hoverables)))"}]
                              :accesses [{:path ["ctx" "hoverables"]
                                          :text "ctx.hoverables"
                                          :line 6 :column 1
                                          :form "ctx.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for when-guarded hoverables without assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should have correct constraint-id"))

;; R1-2: bare clickables without access fact
(fn interactive-assertion-flags-bare-clickables-no-access-fact []
  "A function using bare 'clickables' as a single-segment symbol (which
  Task-4 does not emit as an access) should still be detected via form text
  scanning and flagged when no assert call exists."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "silent-render"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn silent-render [ctx]
  (when clickables
    (handle clickables)))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for bare clickables without assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag bare clickables without assert"))

;; R1-2: bare hoverables without access fact
(fn interactive-assertion-flags-bare-hoverables-no-access-fact []
  "A function using bare 'hoverables' without an access fact should be flagged
  when no assert call exists."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "silent-tooltip"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn silent-tooltip [ctx]
  (when hoverables
    (handle hoverables)))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for bare hoverables without assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag bare hoverables without assert"))

;; R1-2: real fact extraction test
(fn interactive-assertion-flags-bare-clickables-via-real-facts []
  "Use the actual fact extractor to parse Fennel source containing bare
  'clickables' and verify the interactive-assertion rule flags it."
  (local Facts (require :constraints.facts))
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  ;; Real Fennel source with bare clickables and no assert
  (local source "(fn silent-click [ctx]
  (when clickables
    (handle clickables)))")
  ;; Extract facts using tree-sitter (needs a real parser)
  (local ts (require :tree-sitter))
  (local tree (ts.parse source {:language :fennel}))
  (local root (tree:root))
  (local file-records [{:target {:kind :repo :name :test}
                         :path "/test/silent-click.fnl"
                         :module "test.silent-click"
                         :source source
                         :root root}])
  (local fact-db (Facts.extract file-records))
  (local ctx {:target {:kind :repo :name :test}
              :facts fact-db
              :files []})
  (local result (rule.run ctx))
  (assert result "real fact extraction should produce diagnostics for bare clickables without assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "real-fact diagnostic should flag bare clickables"))

;; R1-2: real fact extraction test — helper skip (param-based)
(fn interactive-assertion-allows-param-clickables-via-real-facts []
  "Use the actual fact extractor to parse Fennel source containing
  clickables as a bare parameter.  The real facts extractor emits no
  bare access facts for single-symbol references, so the parameter-based
  skip must work even without :accesses entries."
  (local Facts (require :constraints.facts))
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  ;; Real Fennel source: clickables is a function parameter, not an access
  (local source "(fn process-clicks [clickables]
  (each [_ c (ipairs clickables)]
    (register c)))")
  ;; Extract facts using tree-sitter
  (local ts (require :tree-sitter))
  (local tree (ts.parse source {:language :fennel}))
  (local root (tree:root))
  (local file-records [{:target {:kind :repo :name :test}
                         :path "/test/process-clicks.fnl"
                         :module "test.process-clicks"
                         :source source
                         :root root}])
  (local fact-db (Facts.extract file-records))
  (local ctx {:target {:kind :repo :name :test}
              :facts fact-db
              :files []})
  (local result (rule.run ctx))
  (assert (= result nil) "real fact extraction should NOT flag param clickables helper"))

;; R1-4: assertion fn not real assert (call-based check)
(fn interactive-assertion-flags-assertion-fn-not-real-assert []
  "A function named 'assertion' that uses clickables but has no assert CALL
  should still be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 180
                                             :form "(fn render-widget [ctx]
  (let [cs ctx.clickables]
    (assertion cs \"some check\")
    (handle cs)))"}]
                              :calls [{:callee "assertion"
                                       :receiver nil :method nil
                                       :line 7 :column 1
                                       :form "(assertion cs \"some check\")"
                                       :enclosing-fn "render-widget"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for clickables with assertion fn (not real assert)")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag when only 'assertion' (not real assert call) is present"))

;; R1-4: string literal assert
(fn interactive-assertion-flags-string-assert-not-real-assert []
  "A function with a log/warning string containing 'assert' but no assert CALL
  should still be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "soft-warn"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 180
                                             :form "(fn soft-warn [ctx]
  (let [hs ctx.hoverables]
    (when (not hs)
      (log-warn \"missing assert for hoverables\"))
    (handle hs)))"}]
                              :accesses [{:path ["ctx" "hoverables"]
                                          :text "ctx.hoverables"
                                          :line 6 :column 1
                                          :form "ctx.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for hoverables with string 'assert' (not real assert)")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag when only string 'assert' is present"))

;; R1-5: handle-clickables / unclickables should NOT be flagged
(fn interactive-assertion-allows-handle-clickables-identifier []
  "A function using 'handle-clickables' (hyphenated identifier) should NOT
  trigger the bare-interactive detector."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "render-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-widget [ctx]
  (let [cs (handle-clickables ctx)]
    (render cs)))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "handle-clickables should not be flagged as bare clickables"))

;; R3-F1: string/comment text must not trigger bare-interactive
(fn interactive-assertion-allows-string-containing-clickables []
  "A function whose form text contains a string literal with ' clickables'
  should NOT be flagged by the bare-interactive detector."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "log-missing"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 120
                                             :form "(fn log-missing [ctx]
  (when (not ctx.clickables)
    (log \"missing clickables\")))"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag the ctx.clickables access without assert")
  ;; Verify only ONE diagnostic (for ctx.clickables, not for string content)
  (assert (= (length result) 1) (.. "expected 1 diagnostic, got " (length result)))
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should be for ctx.clickables, not string content"))

;; R3-F2: unrelated anonymous function far from layouter context

;; R3-F3: cross-anonymous-function assert must not correlate
(fn interactive-assertion-flags-second-anonymous-without-own-assert []
  "Two anonymous functions: one using clickables with assert, another
  using clickables without assert.  The assert in the first must NOT
  suppress the missing-assert diagnostic in the second."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  ;; Two anonymous fns in same file
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn [ctx]
  (let [cs (assert clickables \"missing\")]
    (process cs)))"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 15 :column 1
                                             :length 150
                                             :form "(fn [ctx]
  (when clickables
    (handle clickables)))"}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(assert clickables \"missing\")"
                                       :enclosing-fn "<anonymous>"}]
                              ;; No access facts for bare clickables (Task-4 doesn't emit)
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for second anonymous fn without assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag second anonymous fn without own assert"))

;; R4-1: comment-only clickables must NOT be flagged as bare interactive
(fn interactive-assertion-allows-comment-only-clickables []
  "A function containing only a comment ';; missing clickables' and no real
  clickables access should NOT be flagged by the bare-interactive detector."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "render-empty"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 80
                                             :form "(fn render-empty [ctx]
  ;; missing clickables
  (print :done))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "comment-only clickables should not trigger bare-interactive detection"))



;; R4-3: comment-only assert in anonymous function
(fn interactive-assertion-flags-comment-only-assert-in-anonymous []
  "An anonymous function using clickables with only a commented-out assert
  ';; (assert clickables ...)' should still be flagged (the comment should
  not count as a real assert)."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn [ctx]
  ;; (assert clickables \"missing\")
  (when clickables
    (handle clickables)))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for clickables with only commented-out assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag anonymous fn with commented-out assert"))

;; R1-6: parameter-based skip — helper receives interactive access as bare parameter
(fn interactive-assertion-allows-parameter-clickables []
  "A function that receives clickables as a bare parameter (e.g.,
  (fn helper [clickables]) where clickables is a direct parameter)
  should NOT be flagged.  The caller is responsible for the assert.
  No synthetic :accesses are injected — real facts extraction does
  not produce access records for bare single-symbol accesses."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "process-clicks"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn process-clicks [clickables]
  (each [_ c (ipairs clickables)]
    (register c)))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "helper receiving clickables as bare parameter should pass"))

;; R1-7: parameter-based skip with hoverables
(fn interactive-assertion-allows-parameter-hoverables []
  "A function that receives hoverables as a bare parameter (e.g.,
  (fn helper [hoverables]) where hoverables is a direct parameter)
  should NOT be flagged — the caller already validated the context.
  No synthetic :accesses are injected — matches real facts extraction."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "setup-hover"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn setup-hover [hoverables]
  (each [_ h (ipairs hoverables)]
    (register-hover h)))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "helper receiving hoverables as bare parameter should pass"))

;; R1-7b: param skip must NOT suppress dotted access
(fn interactive-assertion-flags-param-with-dotted-access []
  "A function that has clickables as a bare parameter BUT also accesses
  ctx.clickables directly via dotted access should STILL be flagged.  The
  parameter skip must not over-exempt functions with dotted interactive access."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-clickables"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-clickables [ctx clickables]
  (each [_ c (ipairs ctx.clickables)]
    (register c)))"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag param clickables with dotted ctx.clickables access")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag dotted access despite clickables parameter"))

;; R1-7c: param skip must NOT suppress dotted hoverables access
(fn interactive-assertion-flags-param-hoverables-with-dotted-access []
  "A function that has hoverables as a bare parameter BUT also accesses
  options.hoverables directly via dotted access should STILL be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "setup-hoverables"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn setup-hoverables [opts hoverables]
  (each [_ h (ipairs options.hoverables)]
    (register-hover h)))"}]
                              :accesses [{:path ["options" "hoverables"]
                                          :text "options.hoverables"
                                          :line 6 :column 1
                                          :form "options.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag param hoverables with dotted options.hoverables access")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag dotted hoverables despite hoverables parameter"))
;; R1-8R3: named function with clickables/hoverables in name + dot-access → flags
(fn interactive-assertion-flags-named-dot-access []
  "A function named render-clickables-panel that accesses ctx.clickables
  directly via dot-access (not bare) should be FLAGGED despite the name.
  The name-only exemption has been removed; only bare keyword parameters
  trigger the helper skip."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-clickables-panel"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-clickables-panel [ctx]
  (each [_ c (ipairs ctx.clickables)]
    (register c)))"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag named function with dot-access despite containing clickables in name")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag named dot-access without assert"))

;; R1-9: direct unasserted ctx/options/app access still flags
(fn interactive-assertion-flags-direct-access-in-named-fn []
  "A function that accesses ctx.clickables directly without assert and
  whose name does NOT contain a skip pattern should still be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  ;; The function name does NOT contain 'clickables' or 'hoverables',
  ;; and 'ctx' is not a parameter (it's a capture from outer scope in
  ;; this synthetic test).
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "render-button"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-button []
  (let [cs ctx.clickables]
    (process cs)))"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag direct ctx.clickables access without assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "diagnostic should flag direct access without assert"))

;; ==== precision: outer factory not flagged for nested asserted build ====

(fn interactive-assertion-allows-outer-factory-with-nested-assert []
  "An outer factory function (e.g., Button) containing a nested build
  function that asserts ctx.clickables should NOT be flagged at the
  outer level.  The nested function's accesses must not be attributed
  to the enclosing factory."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local build-form "(fn build [ctx]
  (assert ctx.clickables \"missing\")
  (set-clickables ctx.clickables))")
  (local button-form (.. "(fn Button [opts]
  (let [ctx (make-ctx opts)]
    " build-form "
    (build ctx)))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "Button"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length button-form)
                                             :form button-form}
                                            {:kind :fn
                                             :name "build"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length build-form)
                                             :form build-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 4 :column 3
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "build"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 4 :column 3
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged-button false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "Button")
      (set flagged-button true)))
  (assert (not flagged-button) "outer Button should not be flagged for nested build's accesses"))

;; ==== precision: closure helper using asserted local passes ====

(fn interactive-assertion-allows-closure-helper-with-asserted-local []
  "A nested helper function using bare clickables that was bound via
  (local clickables (assert ...)) in the enclosing scope should pass.
  The helper is a SEPARATE definition with no own assert, relying
  on the parent's asserted local via closure capture."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local widget-form (.. "(fn make-widget [ctx]
  (local clickables (assert ctx.clickables \"missing\"))
  (let [h " helper-form "]
    (h)))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length widget-form)
                                             :form widget-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 10
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 2 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "make-widget"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 2 :column 16
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  ;; Neither make-widget (has its own assert) nor helper (closure-captures
  ;; asserted local) should be flagged
  (assert (= result nil) "closure helper using asserted local clickables should pass"))

;; R6-2 negative: asserted clickables + bare hoverables still flags
(fn interactive-assertion-flags-bare-hoverables-despite-asserted-clickables []
  "A nested helper using bare hoverables should still be flagged even if
  the enclosing parent asserts clickables.  The closure bypass must be
  keyword-specific: asserting clickables does not excuse bare hoverables."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (each [_ h (ipairs hoverables)]
    (display h)))")
  (local widget-form (.. "(fn make-widget [ctx]
  (local clickables (assert ctx.clickables \"missing\"))
  (let [h " helper-form "]
    (h)))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length widget-form)
                                             :form widget-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 10
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 2 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "make-widget"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 2 :column 16
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "bare hoverables should flag despite asserted clickables")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; R6-2 negative: shadowed clickables still flags
(fn interactive-assertion-flags-shadowed-clickables []
  "A nested helper that shadows clickables with its own (local clickables ...)
  should still be flagged.  The parent's asserted local is shadowed."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (local clickables [])
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local widget-form (.. "(fn make-widget [ctx]
  (local clickables (assert ctx.clickables \"missing\"))
  (let [h " helper-form "]
    (h)))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length widget-form)
                                             :form widget-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 10
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 2 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "make-widget"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 2 :column 16
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "shadowed clickables should still flag")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; R7-1: reassigned clickables still flags
(fn interactive-assertion-flags-reassigned-clickables []
  "A nested helper that reassigns clickables via (set clickables [])
  should still be flagged.  The parent's asserted local is invalidated
  by reassignment."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (set clickables [])
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local widget-form (.. "(fn make-widget [ctx]
  (local clickables (assert ctx.clickables \"missing\"))
  (let [h " helper-form "]
    (h)))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length widget-form)
                                             :form widget-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 10
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 2 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "make-widget"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 2 :column 16
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "reassigned clickables should still flag")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; R6-1: anonymous nested asserted build does not flag outer factory
(fn interactive-assertion-allows-outer-with-anonymous-nested-assert []
  "An outer factory containing an anonymous nested callback that asserts
  ctx.clickables should NOT be flagged.  The anonymous nested body
  must be blanked from the outer scan."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local anon-form "(fn [ctx]
  (assert ctx.clickables \"missing\")
  (set-clickables ctx.clickables))")
  (local factory-form (.. "(fn make-factory [opts]
  (let [callback " anon-form "]
    (callback (make-ctx opts))))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-factory"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length factory-form)
                                             :form factory-form}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 2 :column 16
                                             :length (length anon-form)
                                             :form anon-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 4 :column 3
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "<anonymous>"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 4 :column 3
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged-factory false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "make-factory")
      (set flagged-factory true)))
  (assert (not flagged-factory)
          "outer factory should not be flagged for anonymous nested assert"))

;; ==== regression: unasserted bare access still flags ====

(fn interactive-assertion-flags-unasserted-bare-access []
  "A function using bare clickables without assert should still be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "silent-user"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 100
                                             :form "(fn silent-user []
  (each [_ c (ipairs clickables)]
    (handle c)))"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "unasserted bare clickables should still flag")
  (assert (> (length result) 0) "should have at least one diagnostic"))

;; Import V12 precision tests
(local precision (require :tests.test-constraints-rules-layout-interactive-precision))
(each [_ t (ipairs precision.tests)] (table.insert tests t))

;; Register all interactive tests
;; layout.interactive-context-assertion
(table.insert tests {:name "interactive-assertion allows file without clickables"
                     :fn interactive-assertion-allows-file-without-clickables})
(table.insert tests {:name "interactive-assertion allows clickables with assert call"
                     :fn interactive-assertion-allows-clickables-with-assert-call})
(table.insert tests {:name "interactive-assertion allows hoverables with assert call"
                     :fn interactive-assertion-allows-hoverables-with-assert-call})
(table.insert tests {:name "interactive-assertion flags clickables without assert"
                     :fn interactive-assertion-flags-clickables-without-assert})
(table.insert tests {:name "interactive-assertion flags hoverables without assert"
                     :fn interactive-assertion-flags-hoverables-without-assert})
(table.insert tests {:name "interactive-assertion flags assert in different function"
                     :fn interactive-assertion-flags-assert-in-different-function})
(table.insert tests {:name "interactive-assertion flags silent guard clickables"
                     :fn interactive-assertion-flags-silent-guard-clickables})
(table.insert tests {:name "interactive-assertion allows bare clickables with assert call"
                     :fn interactive-assertion-allows-bare-clickables-with-assert-call})
(table.insert tests {:name "interactive-assertion flags hoverables with when no assert"
                     :fn interactive-assertion-flags-hoverables-with-when-no-assert})
;; R1-2: bare names
(table.insert tests {:name "interactive-assertion flags bare clickables no access fact"
                     :fn interactive-assertion-flags-bare-clickables-no-access-fact})
(table.insert tests {:name "interactive-assertion flags bare hoverables no access fact"
                     :fn interactive-assertion-flags-bare-hoverables-no-access-fact})
;; R1-2: real fact extraction
(table.insert tests {:name "interactive-assertion flags bare clickables via real facts"
                     :fn interactive-assertion-flags-bare-clickables-via-real-facts})
;; R1-2: real fact extraction — helper skip
(table.insert tests {:name "interactive-assertion allows param clickables via real facts"
                     :fn interactive-assertion-allows-param-clickables-via-real-facts})
;; R1-4: not real assert
(table.insert tests {:name "interactive-assertion flags assertion fn not real assert"
                     :fn interactive-assertion-flags-assertion-fn-not-real-assert})
(table.insert tests {:name "interactive-assertion flags string assert not real assert"
                     :fn interactive-assertion-flags-string-assert-not-real-assert})
;; R1-5: handle-clickables negative
(table.insert tests {:name "interactive-assertion allows handle-clickables identifier"
                     :fn interactive-assertion-allows-handle-clickables-identifier})
;; R3-F1: string/comment text
(table.insert tests {:name "interactive-assertion allows string containing clickables"
                     :fn interactive-assertion-allows-string-containing-clickables})
;; R3-F2: unrelated anonymous far from layouter
;; R4-2: unrelated anonymous near layouter (within 5-line window)
;; R3-F3: cross-anonymous-function assert
(table.insert tests {:name "interactive-assertion flags second anonymous without own assert"
                     :fn interactive-assertion-flags-second-anonymous-without-own-assert})
;; R4-1: comment-only clickables
(table.insert tests {:name "interactive-assertion allows comment-only clickables"
                     :fn interactive-assertion-allows-comment-only-clickables})
;; R5-1 adjudicated: long inline layouter beyond 10 lines from call start
;; R5-1: duplicate anonymous form same as inline layouter
;; R5-1b: duplicate same-form — conservative skip (R6-1)
;; R6-1: duplicate same-form callbacks in same Layout call under different keys
;; R4-3: comment-only assert in anonymous
(table.insert tests {:name "interactive-assertion flags comment-only assert in anonymous"
                     :fn interactive-assertion-flags-comment-only-assert-in-anonymous})
;; R1-6: parameter-based skip
(table.insert tests {:name "interactive-assertion allows parameter clickables"
                     :fn interactive-assertion-allows-parameter-clickables})
;; R1-7: parameter-based skip with hoverables
(table.insert tests {:name "interactive-assertion allows parameter hoverables"
                     :fn interactive-assertion-allows-parameter-hoverables})
;; R1-7b: param skip must NOT suppress dotted access
(table.insert tests {:name "interactive-assertion flags param with dotted access"
                     :fn interactive-assertion-flags-param-with-dotted-access})
;; R1-7c: param skip must NOT suppress dotted hoverables access
(table.insert tests {:name "interactive-assertion flags param hoverables with dotted access"
                     :fn interactive-assertion-flags-param-hoverables-with-dotted-access})
;; R1-8R3: named dot-access with clickables in name still flags
(table.insert tests {:name "interactive-assertion flags named dot-access despite name"
                     :fn interactive-assertion-flags-named-dot-access})
;; R1-9: direct unasserted access still flags
(table.insert tests {:name "interactive-assertion flags direct access in named fn"
                     :fn interactive-assertion-flags-direct-access-in-named-fn})
;; ==== new precision tests ====
(table.insert tests {:name "interactive-assertion allows outer factory with nested assert"
                     :fn interactive-assertion-allows-outer-factory-with-nested-assert})
(table.insert tests {:name "interactive-assertion allows closure helper with asserted local"
                     :fn interactive-assertion-allows-closure-helper-with-asserted-local})
;; R6-2 negative: bare hoverables despite asserted clickables
(table.insert tests {:name "interactive-assertion flags bare hoverables despite asserted clickables"
                     :fn interactive-assertion-flags-bare-hoverables-despite-asserted-clickables})
;; R6-2 negative: shadowed clickables still flags
(table.insert tests {:name "interactive-assertion flags shadowed clickables"
                     :fn interactive-assertion-flags-shadowed-clickables})
;; R7-1: reassigned clickables still flags
(table.insert tests {:name "interactive-assertion flags reassigned clickables"
                     :fn interactive-assertion-flags-reassigned-clickables})
;; R6-1: anonymous nested assert does not flag outer
(table.insert tests {:name "interactive-assertion allows outer with anonymous nested assert"
                     :fn interactive-assertion-allows-outer-with-anonymous-nested-assert})
(table.insert tests {:name "interactive-assertion flags unasserted bare access"
                     :fn interactive-assertion-flags-unasserted-bare-access})
{:tests tests}
