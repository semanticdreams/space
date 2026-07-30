;; Ancestor-chain precision tests for layout.interactive-context-assertion
;; closure-helper bypass. Tests extended coverage where the asserted local
;; is in a named lexical ancestor (grandparent), not the immediate parent.
;;
;; Production patterns covered:
;;   preset-list.fnl, session-list.fnl: build→make-row→anonymous-drop
;;   graph/view/init.fnl: GraphView→handle-nodes-removed→anonymous-callback

(local H (require :tests.constraints-layout-helpers))
(local make-file-fact H.make-file-fact)
(local make-ctx H.make-ctx)
(local find-rule-by-id H.find-rule-by-id)
(local tests [])

;; ==== positive: grandparent asserted local covers nested child ====

(fn interactive-assertion-allows-grandparent-asserted-clickables-make-row []
  "Models preset-list.fnl and session-list.fnl: grandparent build asserts
  (local clickables (assert ...)), intermediate make-row has no assert,
  nested anonymous drop uses bare clickables via closure → allowed."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule)
  (local drop-form "(fn [self] (clickables:unregister self))")
  (local make-row-form (.. "(fn make-row [row child-ctx] (local row-widget {})"
                           "(set row-widget.drop " drop-form ") row-widget)"))
  (local build-form (.. "(fn build [ctx]\n"
                        "  (local clickables (assert ctx.clickables \"missing\"))\n"
                        "  (fn inner [])\n"
                        "  " make-row-form ")"))
  (local outer-form (.. "(fn AgentPresetList [controller] " build-form ")"))
  (local ff (make-file-fact
    {:path "/src/preset-list.fnl" :module "preset-list"
     :definitions [{:kind :fn :name "AgentPresetList" :top-level? true
                    :line 1 :column 1
                    :length (length outer-form) :form outer-form}
                   {:kind :fn :name "build" :top-level? false
                    :enclosing-fn "AgentPresetList"
                    :line 2 :column 3
                    :length (length build-form) :form build-form}
                   {:kind :fn :name "make-row" :top-level? false
                    :enclosing-fn "build"
                    :line 10 :column 5
                    :length (length make-row-form) :form make-row-form}
                   {:kind :fn :name "<anonymous>" :top-level? false
                    :enclosing-fn "make-row"
                    :line 12 :column 7
                    :length (length drop-form) :form drop-form}]
     :calls [{:callee "assert" :receiver nil :method nil
              :line 3 :column 16
              :form "(assert ctx.clickables \"missing\")"
              :enclosing-fn "build"}]
     :accesses [{:text "ctx.clickables" :path ["ctx" "clickables"]
                 :line 3 :column 16 :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (= d.line 12) (set flagged true)))
  (assert (not flagged)
    "anonymous drop using bare clickables from grandparent's asserted local should pass"))

(fn interactive-assertion-allows-grandparent-separate-local-assert-graph-view []
  "Models graph/view/init.fnl: grandparent GraphView has (local clickables ...)
  then (assert clickables ...), intermediate handle-nodes-removed has no assert,
  nested anonymous before-remove callback uses bare clickables → allowed."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule)
  (local callback-form "(fn [node point] (when (and clickables point) (clickables:unregister point) (when clickables.unregister-right-click (clickables:unregister-right-click point))))")
  (local handler-form (.. "(fn handle-nodes-removed [payload] (local nodes-to-remove payload.nodes) (registry:remove-nodes nodes-to-remove {:before-remove " callback-form "}))"))
  (local gv-form (.. "(fn GraphView [opts]\n"
                     "  (local clickables (and ctx ctx.clickables))\n"
                     "  ...\n"
                     "  (assert clickables \"GraphView requires clickables\")\n"
                     "  ...\n"
                     "  " handler-form ")"))
  (local ff (make-file-fact
    {:path "/src/graph-view.fnl" :module "graph.view.init"
     :definitions [{:kind :fn :name "GraphView" :top-level? true
                    :line 1 :column 1
                    :length (length gv-form) :form gv-form}
                   {:kind :fn :name "handle-nodes-removed" :top-level? false
                    :enclosing-fn "GraphView"
                    :line 20 :column 3
                    :length (length handler-form) :form handler-form}
                   {:kind :fn :name "<anonymous>" :top-level? false
                    :enclosing-fn "handle-nodes-removed"
                    :line 22 :column 5
                    :length (length callback-form) :form callback-form}]
     :calls [{:callee "assert" :receiver nil :method nil
              :line 5 :column 3
              :form "(assert clickables \"GraphView requires clickables\")"
              :enclosing-fn "GraphView"}]
     :accesses []}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (= d.line 22) (set flagged true)))
  (assert (not flagged)
    "anonymous callback using bare clickables from grandparent's separate local+assert should pass"))

;; ==== negative: intervening parent shadows keyword ====

(fn interactive-assertion-flags-grandparent-assert-with-intervening-shadow []
  "Grandparent build asserts (local clickables (assert ...)), but intermediate
  make-row shadows clickables with (local clickables [...]). Nested anonymous
  drop should still be flagged — intervening shadowing invalidates closure bypass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule)
  (local drop-form "(fn [self] (clickables:unregister self))")
  (local make-row-form (.. "(fn make-row [row child-ctx]"
                           "(local clickables [{:name :stub}])"
                           "(local row-widget {})"
                           "(set row-widget.drop " drop-form ") row-widget)"))
  (local build-form (.. "(fn build [ctx]\n"
                        "  (local clickables (assert ctx.clickables \"missing\"))\n"
                        "  " make-row-form ")"))
  (local outer-form (.. "(fn AgentPresetList [controller] " build-form ")"))
  (local ff (make-file-fact
    {:path "/src/preset-list.fnl" :module "preset-list"
     :definitions [{:kind :fn :name "AgentPresetList" :top-level? true
                    :line 1 :column 1
                    :length (length outer-form) :form outer-form}
                   {:kind :fn :name "build" :top-level? false
                    :enclosing-fn "AgentPresetList"
                    :line 2 :column 3
                    :length (length build-form) :form build-form}
                   {:kind :fn :name "make-row" :top-level? false
                    :enclosing-fn "build"
                    :line 10 :column 5
                    :length (length make-row-form) :form make-row-form}
                   {:kind :fn :name "<anonymous>" :top-level? false
                    :enclosing-fn "make-row"
                    :line 14 :column 7
                    :length (length drop-form) :form drop-form}]
     :calls [{:callee "assert" :receiver nil :method nil
              :line 3 :column 16
              :form "(assert ctx.clickables \"missing\")"
              :enclosing-fn "build"}]
     :accesses [{:text "ctx.clickables" :path ["ctx" "clickables"]
                 :line 3 :column 16 :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (= d.line 14) (set flagged true)))
  (assert flagged
    "intermediate parent shadows clickables, anonymous drop should still be flagged"))

;; ==== R1-1 regression: intervening ancestor binds kw as parameter ====

(fn interactive-assertion-flags-grandparent-assert-with-intervening-param []
  "Grandparent build asserts (local clickables (assert ...)), but intermediate
  make-row receives clickables as a parameter (fn make-row [clickables] ...).
  The nested anonymous drop uses the parameterized clickables, not the
  grandparent's asserted local. Should still be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule)
  (local drop-form "(fn [self] (clickables:unregister self))")
  ;; make-row has [clickables] as parameter — shadows grandparent's local
  (local make-row-form (.. "(fn make-row [clickables]"
                           "(local row-widget {})"
                           "(set row-widget.drop " drop-form ") row-widget)"))
  (local build-form (.. "(fn build [ctx]\n"
                        "  (local clickables (assert ctx.clickables \"missing\"))\n"
                        "  " make-row-form ")"))
  (local outer-form (.. "(fn AgentPresetList [controller] " build-form ")"))
  (local ff (make-file-fact
    {:path "/src/preset-list.fnl" :module "preset-list"
     :definitions [{:kind :fn :name "AgentPresetList" :top-level? true
                    :line 1 :column 1
                    :length (length outer-form) :form outer-form}
                   {:kind :fn :name "build" :top-level? false
                    :enclosing-fn "AgentPresetList"
                    :line 2 :column 3
                    :length (length build-form) :form build-form}
                   {:kind :fn :name "make-row" :top-level? false
                    :enclosing-fn "build"
                    :line 10 :column 5
                    :length (length make-row-form) :form make-row-form}
                   {:kind :fn :name "<anonymous>" :top-level? false
                    :enclosing-fn "make-row"
                    :line 13 :column 7
                    :length (length drop-form) :form drop-form}]
     :calls [{:callee "assert" :receiver nil :method nil
              :line 3 :column 16
              :form "(assert ctx.clickables \"missing\")"
              :enclosing-fn "build"}]
     :accesses [{:text "ctx.clickables" :path ["ctx" "clickables"]
                 :line 3 :column 16 :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (= d.line 13) (set flagged true)))
  (assert flagged
    "intervening fn param shadows clickables, anonymous drop should still be flagged"))

;; ==== R1-2 regression: duplicate-name helpers do not cross-contaminate ====

(fn interactive-assertion-flags-duplicate-name-ancestor-mismatch []
  "Two sibling build functions each contain a make-row definition. build-a has
  assert; build-b does not. The anonymous drop is inside build-b's make-row.
  The ancestor walk must use byte/form containment to select the correct
  make-row (build-b's), not the first-by-name make-row (build-a's)."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.interactive-context-assertion"))
  (assert rule)
  (local drop-form "(fn [self] (clickables:unregister self))")
  ;; build-b's make-row: no assert in enclosing build-b
  (local make-row-b-form (.. "(fn make-row [row child-ctx]"
                             "(local row-widget {})"
                             "(set row-widget.drop " drop-form ") row-widget)"))
  (local build-b-form (.. "(fn build-b [ctx]\n"
                          "  (local theme ctx.theme)\n"
                          "  " make-row-b-form ")"))
  ;; build-a's make-row: has assert
  (local make-row-a-form "(fn make-row [row child-ctx] (local row-widget {}) row-widget)")
  (local build-a-form (.. "(fn build-a [ctx]\n"
                          "  (local clickables (assert ctx.clickables \"missing\"))\n"
                          "  " make-row-a-form ")"))
  (local outer-form (.. "(fn AgentPresetList [controller] " build-a-form " " build-b-form ")"))
  ;; Place build-a's make-row FIRST in all-defs (it will be picked by name-first
  ;; if containment is not checked). build-b's make-row is the correct one.
  (local ff (make-file-fact
    {:path "/src/preset-list.fnl" :module "preset-list"
     :definitions [{:kind :fn :name "AgentPresetList" :top-level? true
                    :line 1 :column 1
                    :length (length outer-form) :form outer-form}
                   {:kind :fn :name "build-a" :top-level? false
                    :enclosing-fn "AgentPresetList"
                    :line 2 :column 3
                    :length (length build-a-form) :form build-a-form}
                   ;; build-a's make-row (FIRST in all-defs — wrong ancestor)
                   {:kind :fn :name "make-row" :top-level? false
                    :enclosing-fn "build-a"
                    :line 4 :column 5
                    :length (length make-row-a-form) :form make-row-a-form}
                   {:kind :fn :name "build-b" :top-level? false
                    :enclosing-fn "AgentPresetList"
                    :line 7 :column 3
                    :length (length build-b-form) :form build-b-form}
                   ;; build-b's make-row (correct ancestor — contains the child)
                   {:kind :fn :name "make-row" :top-level? false
                    :enclosing-fn "build-b"
                    :line 9 :column 5
                    :length (length make-row-b-form) :form make-row-b-form}
                   {:kind :fn :name "<anonymous>" :top-level? false
                    :enclosing-fn "make-row" ;; ambiguous by name
                    :line 11 :column 7
                    :length (length drop-form) :form drop-form}]
     :calls [{:callee "assert" :receiver nil :method nil
              :line 3 :column 16
              :form "(assert ctx.clickables \"missing\")"
              :enclosing-fn "build-a"}]
     :accesses [{:text "ctx.clickables" :path ["ctx" "clickables"]
                 :line 3 :column 16 :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (var flagged false)
  (each [_ d (ipairs (or result []))]
    (when (= d.line 11) (set flagged true)))
  (assert flagged
    "duplicate-name sibling should not cross-contaminate; anonymous drop should still be flagged"))

(fn interactive-assertion-allows-saved-app-state-restore []
  "Cleanup restore functions may assign saved nil interaction services back
  to app state; they are restoration, not required context use."
  (local Layout (require :constraints.rules.layout))
  (local rule (find-rule-by-id (Layout.rules) "layout.interactive-context-assertion"))
  (assert rule)
  (local restore-form "(fn restore-app-state [saved]
  (set app.clickables saved.clickables)
  (set app.hoverables saved.hoverables)
  (set app.scene saved.scene))")
  (local setup-form "(fn setup-app-stubs []
  (local clickables {})
  (assert clickables.register \"missing\")
  (set app.clickables clickables))")
  (local ff (make-file-fact
    {:path "/src/tests/test-panel-transfer.fnl" :module "tests.test-panel-transfer"
     :definitions [{:kind :fn :name "restore-app-state" :top-level? true
                    :line 10 :column 1 :length (length restore-form) :form restore-form}
                   {:kind :fn :name "setup-app-stubs" :top-level? true
                    :line 20 :column 1 :length (length setup-form) :form setup-form}]
     :calls [{:callee "assert" :receiver nil :method nil
              :line 22 :column 3 :form "(assert clickables.register \"missing\")"
              :enclosing-fn "setup-app-stubs"}]
     :accesses [{:text "app.clickables" :path ["app" "clickables"] :line 11 :column 8 :form "app.clickables"}
                {:text "saved.clickables" :path ["saved" "clickables"] :line 11 :column 23 :form "saved.clickables"}
                {:text "app.hoverables" :path ["app" "hoverables"] :line 12 :column 8 :form "app.hoverables"}
                {:text "saved.hoverables" :path ["saved" "hoverables"] :line 12 :column 23 :form "saved.hoverables"}
                {:text "app.clickables" :path ["app" "clickables"] :line 23 :column 8 :form "app.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (each [_ d (ipairs (or result []))]
    (assert (not (= d.evidence.function-name "restore-app-state"))
            "restore-app-state exact saved-field restore should not be flagged")))

(table.insert tests {:name "interactive-assertion allows grandparent asserted clickables make-row pattern"
                     :fn interactive-assertion-allows-grandparent-asserted-clickables-make-row})
(table.insert tests {:name "interactive-assertion allows grandparent separate local assert graph view pattern"
                     :fn interactive-assertion-allows-grandparent-separate-local-assert-graph-view})
(table.insert tests {:name "interactive-assertion flags grandparent assert with intervening shadow"
                     :fn interactive-assertion-flags-grandparent-assert-with-intervening-shadow})
(table.insert tests {:name "interactive-assertion-flags-grandparent-assert-with-intervening-param"
                     :fn interactive-assertion-flags-grandparent-assert-with-intervening-param})
(table.insert tests {:name "interactive-assertion-flags-duplicate-name-ancestor-mismatch"
                      :fn interactive-assertion-flags-duplicate-name-ancestor-mismatch})
(table.insert tests {:name "interactive-assertion allows saved app state restore"
                     :fn interactive-assertion-allows-saved-app-state-restore})

{:tests tests}
