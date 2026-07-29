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

(table.insert tests {:name "interactive-assertion allows grandparent asserted clickables make-row pattern"
                     :fn interactive-assertion-allows-grandparent-asserted-clickables-make-row})
(table.insert tests {:name "interactive-assertion allows grandparent separate local assert graph view pattern"
                     :fn interactive-assertion-allows-grandparent-separate-local-assert-graph-view})
(table.insert tests {:name "interactive-assertion flags grandparent assert with intervening shadow"
                     :fn interactive-assertion-flags-grandparent-assert-with-intervening-shadow})

{:tests tests}
