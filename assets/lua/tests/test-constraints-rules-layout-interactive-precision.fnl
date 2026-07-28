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

;; R1-1: anonymous parent must NOT cover child helper via closure bypass
(fn interactive-assertion-flags-anonymous-parent-asserted-local []
  "A nested helper using bare clickables inside an anonymous parent that
  asserts (local clickables (assert ...)) should still be flagged.  The
  closure-helper bypass requires a named parent; anonymous parents cannot
  prove scope-safe coverage."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local anon-form (.. "(fn [ctx]
  (local clickables (assert ctx.clickables \"missing\"))
  " helper-form "
  (helper))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length (.. "(fn make-widget [] " anon-form ")"))
                                             :form (.. "(fn make-widget [] " anon-form ")")}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 2 :column 3
                                             :length (length anon-form)
                                             :form anon-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 2 :column 16
                                       :form "(assert ctx.clickables \"missing\")"
                                       :enclosing-fn "<anonymous>"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 2 :column 16
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag helper when parent is anonymous")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-helper false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "helper")
      (set flagged-helper true)))
  (assert flagged-helper
          "helper should be flagged when anonymous parent has asserted local"))

;; ==== Task 11: separate-local-then-assert pattern ====

(fn interactive-assertion-allows-separate-local-clickables-assert-pattern []
  "Models menu-manager.fnl pattern: (local clickables (or options.clickables ...))
  then (assert clickables ...) in the same parent, with a nested drop helper
  using bare clickables.  Should pass because the local is asserted before child."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local drop-form "(fn drop [self]
  (when clickables
    (clickables:unregister cb)))")
  (local build-form (.. "(fn MenuManager [opts]
  (local options (or opts {}))
  (local clickables (or options.clickables app.clickables))
  (assert clickables \"MenuManager requires clickables\")
  (var active-menu nil)
  " drop-form "
  (drop self))"))
  (local ff (make-file-fact {:path "/src/menu-manager.fnl"
                              :module "menu-manager"
                              :definitions [{:kind :fn
                                             :name "MenuManager"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "drop"
                                             :top-level? false
                                             :line 7 :column 3
                                             :length (length drop-form)
                                             :form drop-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 4 :column 3
                                       :form "(assert clickables \"MenuManager requires clickables\")"
                                       :enclosing-fn "MenuManager"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged-drop false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "drop")
      (set flagged-drop true)))
  (assert (not flagged-drop)
          "drop using bare clickables from parent's separate local+assert should pass"))

(fn interactive-assertion-allows-separate-local-clickables-graph-view-pattern []
  "Models graph/view/init.fnl pattern: (local clickables (and ctx ctx.clickables))
  then (assert clickables ...) in the same parent, with nested helpers
  detach-presentation and install-presentation using bare clickables. Should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local detach-form "(fn detach-presentation [node presentation]
  (when clickables
    (clickables:unregister presentation)))")
  (local install-form "(fn install-presentation [node previous presentation]
  (clickables:register presentation))")
  (local build-form (.. "(fn GraphView [opts]
  (local clickables (and ctx ctx.clickables))
  (assert clickables \"GraphView requires clickables\")
  " detach-form "
  " install-form "
  (detach-presentation node pres)
  (install-presentation node prev pres))"))
  (local ff (make-file-fact {:path "/src/graph/view/init.fnl"
                              :module "graph.view.init"
                              :definitions [{:kind :fn
                                             :name "GraphView"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "detach-presentation"
                                             :top-level? false
                                             :line 4 :column 3
                                             :length (length detach-form)
                                             :form detach-form}
                                            {:kind :fn
                                             :name "install-presentation"
                                             :top-level? false
                                             :line 5 :column 3
                                             :length (length install-form)
                                             :form install-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 3 :column 3
                                       :form "(assert clickables \"GraphView requires clickables\")"
                                       :enclosing-fn "GraphView"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (or (= d.evidence.function-name "detach-presentation")
              (= d.evidence.function-name "install-presentation"))
      (set flagged true)))
  (assert (not flagged)
          "helpers using bare clickables from parent's separate local+assert should pass"))

(fn interactive-assertion-flags-separate-local-clickables-no-assert []
  "A nested helper using bare clickables should still be flagged when
  the parent binds (local clickables ...) but there is NO assert call
  fact for clickables in the parent scope."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local build-form (.. "(fn make-widget [opts]
  (local options (or opts {}))
  (local clickables (or options.clickables app.clickables))
  " helper-form "
  (helper))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls []
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag helper when separate local has no assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-helper false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "helper")
      (set flagged-helper true)))
  (assert flagged-helper
          "helper should be flagged when separate local has no assert call"))

(fn interactive-assertion-flags-separate-local-with-assert-after-helper []
  "A nested helper using bare clickables should be flagged when the
  parent binds (local clickables ...) then defines the helper, then
  (assert clickables ...) AFTER the helper.  Assert must dominate."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local build-form (.. "(fn make-widget [opts]
  (local options (or opts {}))
  (local clickables (or options.clickables app.clickables))
  " helper-form "
  (assert clickables \"required\")
  (helper))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 5 :column 3
                                       :form "(assert clickables \"required\")"
                                       :enclosing-fn "make-widget"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag helper when assert is after helper definition")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-helper false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "helper")
      (set flagged-helper true)))
  (assert flagged-helper
          "helper should be flagged when assert is after helper definition"))

(fn interactive-assertion-flags-separate-local-with-assert-in-sibling []
  "A nested helper using bare clickables should be flagged when the
  parent binds (local clickables ...) but the assert is only inside
  a sister nested function, not the parent scope directly."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local prepare-form "(fn prepare [ctx]
  (assert clickables \"required\"))")
  (local helper-form "(fn helper []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local build-form (.. "(fn make-widget [opts]
  (local options (or opts {}))
  (local clickables (or options.clickables app.clickables))
  " prepare-form "
  " helper-form "
  (prepare ctx)
  (helper))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "prepare"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length prepare-form)
                                             :form prepare-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 4 :column 3
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 3 :column 10
                                       :form "(assert clickables \"required\")"
                                       :enclosing-fn "prepare"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag helper when assert is only in sibling fn")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-helper false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "helper")
      (set flagged-helper true)))
  (assert flagged-helper
          "helper should be flagged when assert is only in sibling function"))

(fn interactive-assertion-flags-guarded-options-clickables-only []
  "A nested helper using bare clickables from a guarded (options.clickables ...)
  without assert should still be flagged.  Only explicit assert bypasses."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (when clickables
    (clickables:register node)))")
  (local build-form (.. "(fn make-widget [opts]
  (local options (or opts {}))
  (local clickables options.clickables)
  " helper-form "
  (helper))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 3 :column 3
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls []
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag helper when only guarded options.clickables, no assert")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-helper false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "helper")
      (set flagged-helper true)))
  (assert flagged-helper
          "helper should be flagged when only guarded options.clickables without assert"))

;; R1-1 regression: unrelated assert does not cover helper
(fn interactive-assertion-flags-unrelated-assert []
  "A nested helper using bare clickables should be flagged when the parent
  binds (local clickables options.clickables) and has an unrelated assert
  (assert ctx.theme ...) before the child.  Only asserts targeting the exact
  keyword clickables prove the local safe for the closure bypass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local helper-form "(fn helper []
  (each [_ c (ipairs clickables)]
    (register c)))")
  (local build-form (.. "(fn make-widget [opts ctx]
  (local options (or opts {}))
  (local clickables options.clickables)
  (assert ctx.theme \"theme required\")
  " helper-form "
  (helper))"))
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length (length build-form)
                                             :form build-form}
                                            {:kind :fn
                                             :name "helper"
                                             :top-level? false
                                             :line 4 :column 3
                                             :length (length helper-form)
                                             :form helper-form}]
                              :calls [{:callee "assert"
                                       :receiver nil :method nil
                                       :line 3 :column 3
                                       :form "(assert ctx.theme \"theme required\")"
                                       :enclosing-fn "make-widget"}]
                              :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag helper when only unrelated assert, not clickables")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var flagged-helper false)
  (each [_ d (ipairs (or result []))]
    (when (= d.evidence.function-name "helper")
      (set flagged-helper true)))
  (assert flagged-helper
          "helper should be flagged when unrelated assert does not cover clickables"))

;; Task 11: separate-local-then-assert pattern
(table.insert tests {:name "interactive-assertion allows separate local clickables assert pattern"
                     :fn interactive-assertion-allows-separate-local-clickables-assert-pattern})
(table.insert tests {:name "interactive-assertion allows separate local clickables graph view pattern"
                     :fn interactive-assertion-allows-separate-local-clickables-graph-view-pattern})
(table.insert tests {:name "interactive-assertion flags separate local clickables no assert"
                     :fn interactive-assertion-flags-separate-local-clickables-no-assert})
(table.insert tests {:name "interactive-assertion flags separate local with assert after helper"
                     :fn interactive-assertion-flags-separate-local-with-assert-after-helper})
(table.insert tests {:name "interactive-assertion flags separate local with assert in sibling"
                     :fn interactive-assertion-flags-separate-local-with-assert-in-sibling})
(table.insert tests {:name "interactive-assertion flags guarded options clickables only"
                     :fn interactive-assertion-flags-guarded-options-clickables-only})
;; R1-1: unrelated assert does not enable bypass
(table.insert tests {:name "interactive-assertion flags unrelated assert"
                     :fn interactive-assertion-flags-unrelated-assert})

;; ==== Task 11: interaction-router router-owned collections ====

(fn interactive-assertion-allows-router-owned-clickables []
  "Methods on InteractionRouter in next-app.interaction-router module that
  access router.clickables (an internally owned array initialized in
  InteractionRouter.new) should NOT be flagged.  These are receiver-owned
  infrastructure collections, not external routing ctx/app services."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  ;; Model register-clickable: (fn [router node] (table.insert router.clickables node) node)
  (local register-form "(fn [router node]
  (table.insert router.clickables node)
  node)")
  ;; Model dispatch-click: (fn [router x y event] (local target (pick-topmost router.clickables x y)) target)
  (local dispatch-form "(fn [router x y event]
  (local target (pick-topmost router.clickables x y))
  target)")
  (local ff (make-file-fact {:path "/src/next-app/interaction-router.fnl"
                              :module "next-app.interaction-router"
                              :definitions [{:kind :fn
                                             :name "InteractionRouter.new"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 500
                                             :form "(fn InteractionRouter.new []
  (local self (setmetatable {:clickables [] :hoverables []} InteractionRouter))
  self)"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 5 :column 3
                                             :length (length register-form)
                                             :form register-form}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 10 :column 3
                                             :length (length dispatch-form)
                                             :form dispatch-form}]
                              :accesses [{:path ["router" "clickables"]
                                          :text "router.clickables"
                                          :line 5 :column 14
                                          :form "router.clickables"}
                                         {:path ["router" "clickables"]
                                          :text "router.clickables"
                                          :line 10 :column 17
                                          :form "router.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (string.find (or d.file "") "interaction-router" 1 true)
      (set flagged true)))
  (assert (not flagged) "router.clickables in interaction-router module should pass"))

(fn interactive-assertion-allows-router-owned-hoverables []
  "Methods on InteractionRouter accessing router.hoverables should NOT be
  flagged.  Same rationale as router.clickables — internally owned
  infrastructure collections."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  ;; Model register-hoverable: (fn [router node] (table.insert router.hoverables node) node)
  (local register-form "(fn [router node]
  (table.insert router.hoverables node)
  node)")
  ;; Model dispatch-hover: (fn [router x y] (local target (pick-topmost router.hoverables x y)) target)
  (local dispatch-form "(fn [router x y]
  (local target (pick-topmost router.hoverables x y))
  target)")
  (local ff (make-file-fact {:path "/src/next-app/interaction-router.fnl"
                              :module "next-app.interaction-router"
                              :definitions [{:kind :fn
                                             :name "InteractionRouter.new"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 500
                                             :form "(fn InteractionRouter.new []
  (local self (setmetatable {:clickables [] :hoverables []} InteractionRouter))
  self)"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 5 :column 3
                                             :length (length register-form)
                                             :form register-form}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 9 :column 3
                                             :length (length dispatch-form)
                                             :form dispatch-form}]
                              :accesses [{:path ["router" "hoverables"]
                                          :text "router.hoverables"
                                          :line 5 :column 14
                                          :form "router.hoverables"}
                                         {:path ["router" "hoverables"]
                                          :text "router.hoverables"
                                          :line 9 :column 17
                                          :form "router.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (string.find (or d.file "") "interaction-router" 1 true)
      (set flagged true)))
  (assert (not flagged) "router.hoverables in interaction-router module should pass"))

;; Regression: router.clickables in non-interaction-router file still flags
(fn interactive-assertion-flags-router-clickables-outside-interaction-router []
  "Accessing router.clickables in a file that is NOT next-app.interaction-router
  should still be flagged.  Only the specific interaction-router module gets
  the exemption for its internally owned collections."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/non-router-widget.fnl"
                              :module "non-router-widget"
                              :definitions [{:kind :fn
                                             :name "use-router"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 120
                                             :form "(fn use-router [router]
  (each [_ c (ipairs router.clickables)]
    (register c)))"}]
                              :accesses [{:path ["router" "clickables"]
                                          :text "router.clickables"
                                          :line 2 :column 13
                                          :form "router.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "router.clickables outside interaction-router should flag")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "should flag router.clickables in non-router file"))

;; Regression: app.clickables still flags
(fn interactive-assertion-flags-app-clickables []
  "Accessing app.clickables should still be flagged.  The interaction-router
  exemption must not bleed into app-level context routing."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/app-widget.fnl"
                              :module "app-widget"
                              :definitions [{:kind :fn
                                             :name "render-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn render-widget []
  (let [cs app.clickables]
    (process cs)))"}]
                              :accesses [{:path ["app" "clickables"]
                                          :text "app.clickables"
                                          :line 6 :column 1
                                          :form "app.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "app.clickables should still be flagged")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.interactive-context-assertion")
          "should flag app.clickables"))

;; V12: scope-safe closure-helper bypass for button.fnl pattern
(table.insert tests {:name "interactive-assertion allows button clickables pattern"
                     :fn interactive-assertion-allows-button-clickables-pattern})
(table.insert tests {:name "interactive-assertion allows button hoverables pattern"
                     :fn interactive-assertion-allows-button-hoverables-pattern})
(table.insert tests {:name "interactive-assertion flags assert in sibling not parent"
                     :fn interactive-assertion-flags-assert-in-sibling-not-parent})
(table.insert tests {:name "interactive-assertion flags asserted local after helper"
                     :fn interactive-assertion-flags-asserted-local-after-helper})
;; R1-1: anonymous parent must NOT cover child helper
(table.insert tests {:name "interactive-assertion flags anonymous parent asserted local"
                     :fn interactive-assertion-flags-anonymous-parent-asserted-local})

;; Task 11: interaction-router router-owned collections
(table.insert tests {:name "interactive-assertion allows router-owned clickables"
                     :fn interactive-assertion-allows-router-owned-clickables})
(table.insert tests {:name "interactive-assertion allows router-owned hoverables"
                     :fn interactive-assertion-allows-router-owned-hoverables})
(table.insert tests {:name "interactive-assertion flags router-clickables outside interaction-router"
                     :fn interactive-assertion-flags-router-clickables-outside-interaction-router})
(table.insert tests {:name "interactive-assertion flags app clickables"
                     :fn interactive-assertion-flags-app-clickables})

{:tests tests}
