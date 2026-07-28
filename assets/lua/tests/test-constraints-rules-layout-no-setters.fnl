;; Tests for layout.no-setters-in-layouters rule.
;; Auto-split from test-constraints-rules-layout.fnl.

(local H (require :tests.constraints-layout-helpers))
(local make-file-fact H.make-file-fact)
(local make-ctx H.make-ctx)
(local find-rule-by-id H.find-rule-by-id)
(local tests [])

;; ======================================================================
;; layout.no-setters-in-layouters
;; ======================================================================

(fn no-setters-allows-file-without-layouter []
  "A file with no layouter-named functions should pass the setter rule."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule layout.no-setters-in-layouters should be in rules list")
  (local ff (make-file-fact {:path "/src/normal-module.fnl"
                              :module "normal-module"
                              :definitions [{:kind :fn
                                             :name "render-button"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn render-button [ctx] (print :hello))"}]
                              :calls [{:callee "print"
                                       :receiver nil :method nil
                                       :line 1 :column 1
                                       :form "(print :hello)"
                                       :enclosing-fn "render-button"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file without layouter should pass"))

(fn no-setters-allows-layouter-without-setter-calls []
  "A file with a layouter function that does not call forbidden setters should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "widget-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn widget-layouter [ctx child]
  (child:set-flex 1)
  (child:set-align :center))"}]
                              :calls [{:callee "child:set-flex"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-flex 1)"
                                       :enclosing-fn "widget-layouter"}
                                      {:callee "child:set-align"
                                       :receiver nil :method nil
                                       :line 7 :column 1
                                       :form "(child:set-align :center)"
                                       :enclosing-fn "widget-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "layouter without setter calls should pass"))

(fn no-setters-flags-set-position-in-layouter []
  "A layouter function calling :set-position should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "bad-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn bad-layouter [ctx child]
  (child:set-position 10 20))"}]
                              :calls [{:callee "child:set-position"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-position 10 20)"
                                       :enclosing-fn "bad-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for :set-position in layouter")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "layout-rendering") "diagnostic should have family layout-rendering")
  (assert (= d.file ff.path) "diagnostic should include file path"))

(fn no-setters-flags-set-rotation-in-layouter []
  "A layouter function calling :set-rotation should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "rot-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn rot-layouter [ctx child]
  (child:set-rotation 1.5))"}]
                              :calls [{:callee "child:set-rotation"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-rotation 1.5)"
                                       :enclosing-fn "rot-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for :set-rotation in layouter")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should have correct constraint-id"))

(fn no-setters-flags-set-size-in-layouter []
  "A layouter function calling :set-size should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "size-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn size-layouter [ctx child]
  (child:set-size 100 200))"}]
                              :calls [{:callee "child:set-size"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-size 100 200)"
                                       :enclosing-fn "size-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for :set-size in layouter")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should have correct constraint-id"))

(fn no-setters-flags-mark-layout-dirty-in-layouter []
  "A layouter function calling mark-layout-dirty should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "dirty-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn dirty-layouter [ctx]
  (mark-layout-dirty))"}]
                              :calls [{:callee "mark-layout-dirty"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(mark-layout-dirty)"
                                       :enclosing-fn "dirty-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for mark-layout-dirty in layouter")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should have correct constraint-id"))

(fn no-setters-flags-mark-measure-dirty-in-layouter []
  "A layouter function calling mark-measure-dirty should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "measure-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn measure-layouter [ctx]
  (mark-measure-dirty))"}]
                              :calls [{:callee "mark-measure-dirty"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(mark-measure-dirty)"
                                       :enclosing-fn "measure-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for mark-measure-dirty in layouter")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should have correct constraint-id"))

(fn no-setters-allows-setters-in-non-layouter []
  "A non-layouter function calling forbidden setters should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/normal-widget.fnl"
                              :module "normal-widget"
                              :definitions [{:kind :fn
                                             :name "init-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn init-widget [ctx child]
  (child:set-position 0 0)
  (child:set-rotation 0)
  (child:set-size 100 100))"}]
                              :calls [{:callee "child:set-position"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-position 0 0)"
                                       :enclosing-fn "init-widget"}
                                      {:callee "child:set-rotation"
                                       :receiver nil :method nil
                                       :line 7 :column 1
                                       :form "(child:set-rotation 0)"
                                       :enclosing-fn "init-widget"}
                                      {:callee "child:set-size"
                                       :receiver nil :method nil
                                       :line 8 :column 1
                                       :form "(child:set-size 100 100)"
                                       :enclosing-fn "init-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "non-layouter function with setters should pass"))

(fn no-setters-flags-multiple-setter-calls-in-layouter []
  "A layouter with multiple forbidden setter calls should flag all of them."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "bad-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn bad-layouter [ctx child]
  (child:set-position 10 20)
  (child:set-size 100 200))"}]
                              :calls [{:callee "child:set-position"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-position 10 20)"
                                       :enclosing-fn "bad-layouter"}
                                      {:callee "child:set-size"
                                       :receiver nil :method nil
                                       :line 7 :column 1
                                       :form "(child:set-size 100 200)"
                                       :enclosing-fn "bad-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for multiple setter calls")
  (assert (>= (length result) 2) "should have at least two diagnostics"))

(fn no-setters-flags-layouter-name-at-end []
  "A function named my-layouter (layouter at end) should be flagged for setter calls."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :definitions [{:kind :fn
                                             :name "my-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn my-layouter [ctx child]
  (child:set-position 5 5))"}]
                              :calls [{:callee "child:set-position"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-position 5 5)"
                                       :enclosing-fn "my-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for my-layouter with setter calls")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should have correct constraint-id"))

;; R1-1: inline :layouter (fn ...) via call form text
(fn no-setters-flags-inline-layouter-via-call-form []
  "An inline :layouter in a (Layout {:layouter (fn [self] (self:set-size 10 20))})
  call should be detected through the call form text, even without top-level exports.
  Task-4 produces <anonymous> for the function and records the Layout call's form."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 5 :column 28
                                             :length 100
                                             :form "(fn [self] (self:set-size 10 20))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:layouter (fn [self] (self:set-size 10 20))})"
                                       :enclosing-fn nil}
                                      {:callee "self:set-size"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(self:set-size 10 20)"
                                       :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for inline :layouter with setter via call form text")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should flag inline :layouter (fn ...) via call form text"))

;; R1-6: method call (obj:layouter) does NOT trigger false positive
(fn no-setters-allows-layouter-method-call []
  "A file where the only :layouter reference is a method call like
  (obj.layout:layouter) should NOT be treated as a layouter context,
  and thus forbidden setters inside it should NOT be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  ;; Method call: (obj.layout:layouter) — NOT a Layout constructor
  (local ff (make-file-fact {:path "/src/normal-widget.fnl"
                              :module "normal-widget"
                              :definitions [{:kind :fn
                                             :name "my-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn my-layouter [ctx]
  (obj.layout:layouter {:a 1}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method "layouter"
                                       :line 6 :column 1
                                       :form "(obj.layout:layouter {:a 1})"
                                       :enclosing-fn "my-layouter"}
                                      {:callee "ctx:set-size"
                                       :receiver nil :method nil
                                       :line 7 :column 1
                                       :form "(ctx:set-size 10 20)"
                                       :enclosing-fn "my-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "method call (obj:layouter) should not create false positive"))

;; R1-7: named-function correlation with :layouter keyword
(fn no-setters-flags-correlated-named-layouter []
  "A file with a Layout constructor containing :layouter my-layouter
  should correlate the named function via the call form, flagging
  forbidden setters inside it."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "my-layouter"
                                             :top-level? true
                                             :line 10 :column 1
                                             :length 200
                                             :form "(fn my-layouter [ctx child]
  (child:set-position 10 20))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:layouter my-layouter})"
                                       :enclosing-fn nil}
                                      {:callee "child:set-position"
                                       :receiver nil :method nil
                                       :line 11 :column 1
                                       :form "(child:set-position 10 20)"
                                       :enclosing-fn "my-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag correlated named layouter with setter")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should flag correlated named layouter"))

;; R1-8: name-only layouter with NO :layouter call in file
(fn no-setters-flags-name-only-layouter-no-call []
  "A file with a function named my-layouter but no :layouter calls
  at all should still accept it as a layouter (backwards compatibility
  with existing name-based detection)."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  ;; No :layouter call at all — name-only detection should still work
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "my-layouter"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn my-layouter [ctx child]
  (child:set-position 5 5))"}]
                              :calls [{:callee "child:set-position"
                                       :receiver nil :method nil
                                       :line 6 :column 1
                                       :form "(child:set-position 5 5)"
                                       :enclosing-fn "my-layouter"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag name-only layouter with setter (no :layouter call)")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should flag name-only layouter"))


(fn no-setters-allows-unrelated-anonymous-far-from-layouter []
  "A file with layouter context at line 10 but a separate unrelated
  anonymous function with a forbidden setter at line 100 (90 lines away)
  should NOT flag the unrelated anonymous function."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  ;; Layouter context at line 10 via call form text
  ;; Unrelated anonymous fn at line 100 with setter
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 100 :column 1
                                             :length 100
                                             :form "(fn [obj] (obj:set-size 50 50))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(Layout {:layouter (fn [self] (self:set-flex 1))})"
                                       :enclosing-fn nil}
                                      {:callee "obj:set-size"
                                       :receiver nil :method nil
                                       :line 101 :column 1
                                       :form "(obj:set-size 50 50)"
                                       :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "unrelated anonymous function far from layouter should pass"))

;; R4-2: unrelated anonymous setter within 5-line proximity of layouter
(fn no-setters-allows-unrelated-anonymous-near-layouter []
  "A file with :layouter Layout call on line 10 and an unrelated anonymous
  callback with obj:set-size on line 12 (within the 5-line proximity window)
  should NOT flag the unrelated anonymous function."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  ;; Layouter context at line 10 via call form text
  ;; Unrelated anonymous fn at line 12 with setter
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 12 :column 1
                                             :length 100
                                             :form "(fn [obj] (obj:set-size 50 50))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(Layout {:layouter (fn [ctx] (ctx:set-flex 1))})"
                                       :enclosing-fn nil}
                                      {:callee "obj:set-size"
                                       :receiver nil :method nil
                                       :line 13 :column 1
                                       :form "(obj:set-size 50 50)"
                                       :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "unrelated anonymous setter near layouter should not be flagged"))

;; R5-1 adjudicated fix: long inline Layout form >10 lines from call start
(fn no-setters-flags-long-inline-layouter-beyond-10-lines []
  "A long multi-line Layout form starting at line 1 with :layouter (fn ...)
  at line 15 containing a forbidden setter should still be flagged. The
  anonymous function form is unambiguously contained in the Layout call form
  text, so correlation does not need a fixed line-distance cutoff."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  ;; Simulate a long Layout call form. The call starts at line 1,
  ;; the anonymous :layouter fn is at line 15 (> 10 lines from start),
  ;; but the form text is unambiguously contained in the call form.
  (local anon-form "(fn [self] (self:set-size 10 20))")
  (local layout-call-form (.. "(Layout {:id :my-widget\n"
                              "         :foo 1\n"
                              "         :bar 2\n"
                              "         :baz 3\n"
                              "         :qux 4\n"
                              "         :quux 5\n"
                              "         :corge 6\n"
                              "         :grault 7\n"
                              "         :garply 8\n"
                              "         :waldo 9\n"
                              "         :fred 10\n"
                              "         :plugh 11\n"
                              "         :xyzzy 12\n"
                              "         :thud 13\n"
                              "         :layouter " anon-form "})"))
  (local ff (make-file-fact {:path "/src/long-widget.fnl"
                              :module "long-widget"
                              :definitions [{:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 15 :column 20
                                             :length 100
                                             :form anon-form}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 1 :column 1
                                       :form layout-call-form
                                       :enclosing-fn nil}
                                      {:callee "self:set-size"
                                       :receiver nil :method nil
                                       :line 16 :column 1
                                       :form "(self:set-size 10 20)"
                                       :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for inline :layouter setter >10 lines from call start")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.no-setters-in-layouters")
          "diagnostic should flag inline layouter setter in long form")
  (assert (<= d.line 20) "setter line should be within the inline layouter def"))

;; R4-1: duplicate anonymous form same as inline layouter
(fn no-setters-allows-unrelated-anonymous-with-duplicate-form []
  "A file with an inline :layouter (fn [obj] (obj:set-size 50 50)) and a
  separate unrelated anonymous function with the same form/body should NOT
  flag the unrelated anonymous's setter call. When form texts are identical
  and correlation by form alone is ambiguous, the rule conservatively skips
  all duplicates rather than guessing by distance to the outer call start."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local anon-form "(fn [obj] (obj:set-size 50 50))")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                              :name "<anonymous>"
                                              :top-level? false
                                              :line 5 :column 20
                                              :length 100
                                              :form anon-form}
                                             {:kind :fn
                                              :name "<anonymous>"
                                              :top-level? false
                                              :line 60 :column 1
                                              :length 100
                                              :form anon-form}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form (.. "(Layout {:layouter " anon-form "})")
                                       :enclosing-fn nil}
                                       ;; setter from the INLINE layouter (line 6, near def line 5)
                                       {:callee "obj:set-size"
                                        :receiver nil :method nil
                                        :line 6 :column 1
                                        :form "(obj:set-size 50 50)"
                                        :enclosing-fn "<anonymous>"}
                                       ;; setter from UNRELATED anonymous (line 61, near def line 60)
                                       {:callee "obj:set-size"
                                        :receiver nil :method nil
                                        :line 61 :column 1
                                        :form "(obj:set-size 50 50)"
                                        :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  ;; Conservative skip: when duplicate same-form anonymous defs are present,
  ;; the rule cannot reliably distinguish the layouter callback from the
  ;; unrelated one, so it skips all of them rather than risk flagging the
  ;; wrong (non-layouter) callback.
  (assert (= result nil)
          (.. "duplicate same-form anonymous defs should be skipped "
              "conservatively — expected nil, got diagnostics")))
;; R5-1: duplicate anonymous form same as inline layouter — when ambiguous,
;; the rule conservatively skips all duplicates (see R6-1 fix).
(fn no-setters-skips-inline-layouter-setter-when-duplicate-anonymous-present []
  "When duplicate same-form anonymous defs are present, the rule
  conservatively skips all of them — the inline layouter's setter is a
  false negative but this avoids false positives on the unrelated copy."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local anon-form "(fn [obj] (obj:set-size 50 50))")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                              :name "<anonymous>"
                                              :top-level? false
                                              :line 5 :column 20
                                              :length 100
                                              :form anon-form}
                                             {:kind :fn
                                              :name "<anonymous>"
                                              :top-level? false
                                              :line 60 :column 1
                                              :length 100
                                              :form anon-form}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form (.. "(Layout {:layouter " anon-form "})")
                                       :enclosing-fn nil}
                                       {:callee "obj:set-size"
                                        :receiver nil :method nil
                                        :line 6 :column 1
                                        :form "(obj:set-size 50 50)"
                                        :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  ;; Conservative skip: duplicate same-form anonymous defs make correlation
  ;; ambiguous, so the rule skips all duplicates rather than guessing wrong.
  (assert (= result nil)
          (.. "ambiguous duplicate same-form anonymous defs should be skipped "
              "conservatively — expected nil, got diagnostics")))
;; R6-1: duplicate anonymous forms inside same Layout call with different keys
(fn no-setters-skips-ambiguous-duplicate-callbacks-in-same-call []
  "When a long Layout call form contains both :measurer and :layouter with
  identical anonymous callback forms, the rule should NOT pick the wrong
  non-layouter callback (the :measurer) by distance to the outer Layout call
  start.  Conservative behavior: skip ambiguous duplicates so no false positive
  is produced on the :measurer's forbidden setter."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.no-setters-in-layouters"))
  (assert rule "rule should be in rules list")
  (local anon-form "(fn [obj] (obj:set-size 50 50))")
  ;; A long Layout call with :measurer first (near call start) and
  ;; :layouter later (farther from call start).  Both anonymous callbacks
  ;; have the same form text containing the forbidden setter :set-size.
  (local layout-call-form (.. "(Layout {:measurer " anon-form "\n"
                              "         :some-attr 1\n"
                              "         :other-attr 2\n"
                              "         :yet-another 3\n"
                              "         :and-another 4\n"
                              "         :still-more 5\n"
                              "         :even-more 6\n"
                              "         :getting-there 7\n"
                              "         :almost 8\n"
                              "         :finally 9\n"
                              "         :more-keys 10\n"
                              "         :still-going 11\n"
                              "         :one-more 12\n"
                              "         :last-one 13\n"
                              "         :layouter " anon-form "})"))
  ;; The :measurer's anonymous def is near the call start (line 2 inside the
  ;; multi-line call form starting at line 1).  The :layouter's anonymous def
  ;; is much farther down (line 15 from the call form newlines).
  (local ff (make-file-fact {:path "/src/long-widget.fnl"
                              :module "long-widget"
                              :definitions [{:kind :fn
                                              :name "<anonymous>"
                                              :top-level? false
                                              :line 2 :column 20
                                              :length 100
                                              :form anon-form}
                                             {:kind :fn
                                              :name "<anonymous>"
                                              :top-level? false
                                              :line 15 :column 20
                                              :length 100
                                              :form anon-form}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 1 :column 1
                                       :form layout-call-form
                                       :enclosing-fn nil}
                                      ;; Setter from the :measurer (NOT a layouter) — near call start
                                      {:callee "obj:set-size"
                                       :receiver nil :method nil
                                       :line 3 :column 1
                                       :form "(obj:set-size 50 50)"
                                       :enclosing-fn "<anonymous>"}
                                      ;; Setter from the actual :layouter — farther from call start
                                      {:callee "obj:set-size"
                                       :receiver nil :method nil
                                       :line 16 :column 1
                                       :form "(obj:set-size 50 50)"
                                       :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  ;; Conservative: when duplicate same-form anonymous callbacks make
  ;; correlation ambiguous, skip them rather than guessing by distance
  ;; to the outer Layout call start.  The measurer at line 2 must NOT be
  ;; falsely flagged as a layouter violation.
  (assert (= result nil)
          (.. "ambiguous duplicate callbacks in same Layout call should be "
              "skipped conservatively — expected nil, got diagnostics"))
  ;; Document: this is a deliberate false-negative tradeoff.  When
  ;; identical anonymous callback forms appear under different keys in
  ;; the same Layout call, the rule conservatively skips all of them
  ;; rather than risk flagging the wrong (non-layouter) callback.
  )

;; Register all no-setters tests
;; layout.no-setters-in-layouters
(table.insert tests {:name "no-setters allows file without layouter"
                     :fn no-setters-allows-file-without-layouter})
(table.insert tests {:name "no-setters allows layouter without setter calls"
                     :fn no-setters-allows-layouter-without-setter-calls})
(table.insert tests {:name "no-setters flags set-position in layouter"
                     :fn no-setters-flags-set-position-in-layouter})
(table.insert tests {:name "no-setters flags set-rotation in layouter"
                     :fn no-setters-flags-set-rotation-in-layouter})
(table.insert tests {:name "no-setters flags set-size in layouter"
                     :fn no-setters-flags-set-size-in-layouter})
(table.insert tests {:name "no-setters flags mark-layout-dirty in layouter"
                     :fn no-setters-flags-mark-layout-dirty-in-layouter})
(table.insert tests {:name "no-setters flags mark-measure-dirty in layouter"
                     :fn no-setters-flags-mark-measure-dirty-in-layouter})
(table.insert tests {:name "no-setters allows setters in non-layouter"
                     :fn no-setters-allows-setters-in-non-layouter})
(table.insert tests {:name "no-setters flags multiple setter calls in layouter"
                     :fn no-setters-flags-multiple-setter-calls-in-layouter})
(table.insert tests {:name "no-setters flags layouter name at end"
                     :fn no-setters-flags-layouter-name-at-end})
;; R1-1: inline :layouter via call form text
(table.insert tests {:name "no-setters flags inline layouter via call form"
                     :fn no-setters-flags-inline-layouter-via-call-form})
;; R1-6: method call does NOT trigger false positive
(table.insert tests {:name "no-setters allows layouter method call (false-positive fix)"
                     :fn no-setters-allows-layouter-method-call})
;; R1-7: named-function correlation
(table.insert tests {:name "no-setters flags correlated named layouter"
                     :fn no-setters-flags-correlated-named-layouter})
;; R1-8: name-only layouter (no :layouter call)
(table.insert tests {:name "no-setters flags name-only layouter no call"
                     :fn no-setters-flags-name-only-layouter-no-call})
(table.insert tests {:name "no-setters allows unrelated anonymous far from layouter"
                     :fn no-setters-allows-unrelated-anonymous-far-from-layouter})
(table.insert tests {:name "no-setters allows unrelated anonymous near layouter"
                     :fn no-setters-allows-unrelated-anonymous-near-layouter})
(table.insert tests {:name "no-setters flags long inline layouter beyond 10 lines"
                     :fn no-setters-flags-long-inline-layouter-beyond-10-lines})
(table.insert tests {:name "no-setters allows unrelated anonymous with duplicate form"
                     :fn no-setters-allows-unrelated-anonymous-with-duplicate-form})
(table.insert tests {:name "no-setters skips inline layouter setter when duplicate anonymous present"
                     :fn no-setters-skips-inline-layouter-setter-when-duplicate-anonymous-present})
(table.insert tests {:name "no-setters skips ambiguous duplicate callbacks in same call"
                     :fn no-setters-skips-ambiguous-duplicate-callbacks-in-same-call})

{:tests tests}
