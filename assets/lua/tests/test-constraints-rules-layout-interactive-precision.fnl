;; Precision tests for layout.interactive-context-assertion closure-helper bypass.
;; V12: scope-safe parent-has-asserted-local-before-child? predicate tests.
;; Split from test-constraints-rules-layout-interactive.fnl to stay under 1200 lines.

(local H (require :tests.constraints-layout-helpers))
(local make-file-fact H.make-file-fact)
(local make-ctx H.make-ctx)
(local find-rule-by-id H.find-rule-by-id)
(local tests [])

;; ==== precision fix V12: scope-safe closure-helper bypass ====

(fn interactive-assertion-allows-button-clickables-pattern []
  "Button-like parent build with (local clickables (assert ...)) before a
  nested register-clickables helper that uses bare clickables should pass.
  Models the button.fnl closure-helper false-positive: build asserts
  ctx.clickables into a local, and register-clickables captures it via closure."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local register-form "(fn register-clickables []
  (clickables:register button)
  (clickables:register-right-click button))")
  (local build-form (.. "(fn build [ctx]
  (local clickables (assert ctx.clickables \"missing\"))
  (local hoverables (assert ctx.hoverables \"missing\"))
  " register-form "
  (register-clickables))"))
  (local ff (make-file-fact {:path "/src/button.fnl"
                              :module "button"
                              :definitions [{:kind :fn
                                             :name "Button"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length (.. "(fn Button [] " build-form ")"))
                                             :form (.. "(fn Button [] " build-form ")")}
                                            {:kind :fn
                                             :name "build"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "register-clickables"
                                             :top-level? false
                                             :line 5 :column 3
                                             :length (length register-form)
                                             :form register-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 4 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "build"}
                                      {:callee "assert"
                                       :receiver nil :method nil
                                       :line 5 :column 16
                                       :form "(assert ctx.hoverables \"missing\")"
                                       :enclosing-fn "build"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 4 :column 16
                                          :form "ctx.clickables"}
                                         {:path ["ctx" "hoverables"]
                                          :text "ctx.hoverables"
                                          :line 5 :column 16
                                          :form "ctx.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged-register-clickables false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "register-clickables")
      (set flagged-register-clickables true)))
  (assert (not flagged-register-clickables)
          "register-clickables using bare clickables from parent's asserted local should pass"))

(fn interactive-assertion-allows-button-hoverables-pattern []
  "Button-like parent build with (local hoverables (assert ...)) before a
  nested register-hoverables helper that uses bare hoverables should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local register-form "(fn register-hoverables []
  (hoverables:register button))")
  (local build-form (.. "(fn build [ctx]
  (local clickables (assert ctx.clickables \"missing\"))
  (local hoverables (assert ctx.hoverables \"missing\"))
  " register-form "
  (register-hoverables))"))
  (local ff (make-file-fact {:path "/src/button.fnl"
                              :module "button"
                              :definitions [{:kind :fn
                                             :name "Button"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length (.. "(fn Button [] " build-form ")"))
                                             :form (.. "(fn Button [] " build-form ")")}
                                            {:kind :fn
                                             :name "build"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "register-hoverables"
                                             :top-level? false
                                             :line 6 :column 3
                                             :length (length register-form)
                                             :form register-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 4 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "build"}
                                      {:callee "assert"
                                       :receiver nil :method nil
                                       :line 5 :column 16
                                       :form "(assert ctx.hoverables \"missing\")"
                                       :enclosing-fn "build"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 4 :column 16
                                          :form "ctx.clickables"}
                                         {:path ["ctx" "hoverables"]
                                          :text "ctx.hoverables"
                                          :line 5 :column 16
                                          :form "ctx.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged-register-hoverables false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "register-hoverables")
      (set flagged-register-hoverables true)))
  (assert (not flagged-register-hoverables)
          "register-hoverables using bare hoverables from parent's asserted local should pass"))

(fn interactive-assertion-flags-assert-in-sibling-not-parent []
  "A nested helper using bare clickables should still be flagged when
  the (local clickables (assert ...)) is only inside a sister nested
  function, not in the parent scope directly.  The assert must be in the
  immediate parent scope for the closure bypass to apply."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local prepare-form "(fn prepare-context [ctx]
  (local clickables (assert ctx.clickables \"missing\")))")
  (local register-form "(fn register-clickables []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local build-form (.. "(fn build [ctx]
  " prepare-form "
  " register-form "
  (register-clickables))"))
  (local ff (make-file-fact {:path "/src/button.fnl"
                              :module "button"
                              :definitions [{:kind :fn
                                             :name "Button"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length (.. "(fn Button [] " build-form ")"))
                                             :form (.. "(fn Button [] " build-form ")")}
                                            {:kind :fn
                                             :name "build"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "prepare-context"
                                             :top-level? false
                                             :line 2 :column 3
                                             :length (length prepare-form)
                                             :form prepare-form}
                                            {:kind :fn
                                             :name "register-clickables"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length register-form)
                                             :form register-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 2 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "prepare-context"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 2 :column 16
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag register-clickables when assert is only in sibling fn")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-register-clickables false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "register-clickables")
      (set flagged-register-clickables true)))
  (assert flagged-register-clickables
          "register-clickables should be flagged when assert is only in sibling function"))

(fn interactive-assertion-flags-asserted-local-after-helper []
  "A nested helper using bare clickables should still be flagged when
  the (local clickables (assert ...)) appears AFTER the helper definition
  in the parent scope.  Only asserted locals before the child count."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local register-form "(fn register-clickables []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local build-form (.. "(fn build [ctx]
  " register-form "
  (local clickables (assert ctx.clickables \"missing\"))
  (register-clickables))"))
  (local ff (make-file-fact {:path "/src/button.fnl"
                              :module "button"
                              :definitions [{:kind :fn
                                             :name "Button"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length (.. "(fn Button [] " build-form ")"))
                                             :form (.. "(fn Button [] " build-form ")")}
                                            {:kind :fn
                                             :name "build"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "register-clickables"
                                             :top-level? false
                                             :line 2 :column 3
                                             :length (length register-form)
                                             :form register-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 3 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "build"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 3 :column 16
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag register-clickables when assert is after helper")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-register-clickables false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "register-clickables")
      (set flagged-register-clickables true)))
  (assert flagged-register-clickables
          "register-clickables should be flagged when assert comes after helper definition"))

;; V12: scope-safe closure-helper bypass for button.fnl pattern
(table.insert tests {:name "interactive-assertion allows button clickables pattern"
                     :fn interactive-assertion-allows-button-clickables-pattern})
(table.insert tests {:name "interactive-assertion allows button hoverables pattern"
                     :fn interactive-assertion-allows-button-hoverables-pattern})
(table.insert tests {:name "interactive-assertion flags assert in sibling not parent"
                     :fn interactive-assertion-flags-assert-in-sibling-not-parent})
(table.insert tests {:name "interactive-assertion flags asserted local after helper"
                     :fn interactive-assertion-flags-asserted-local-after-helper})

{:tests tests}
