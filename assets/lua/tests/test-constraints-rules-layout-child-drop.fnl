;; Tests for layout.owned-child-drop rule.
;; Auto-split from test-constraints-rules-layout.fnl.

(local H (require :tests.constraints-layout-helpers))
(local make-file-fact H.make-file-fact)
(local make-ctx H.make-ctx)
(local find-rule-by-id H.find-rule-by-id)
(local mutation-tests (require :tests.test-constraints-rules-layout-child-drop-mutation))
(local tests [])

(each [_ t (ipairs mutation-tests.tests)]
  (table.insert tests t))

;; layout.owned-child-drop
;; ======================================================================

(fn child-drop-allows-file-without-retained-children []
  "A file with no retained child creation should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule layout.owned-child-drop should be in rules list")
  (local ff (make-file-fact {:path "/src/clean-module.fnl"
                              :module "clean-module"
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file without retained children should pass"))

(fn child-drop-allows-layout-with-drop-fn []
  "A file creating Layout with a drop function and :drop cleanup should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "drop"
                                             :top-level? true
                                             :line 20 :column 1
                                             :length 80
                                             :form "(fn drop [self]
  (self.child:drop))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}
                                      {:callee "self.child:drop"
                                       :receiver nil :method nil
                                       :line 21 :column 1
                                       :form "(self.child:drop)"
                                       :enclosing-fn "drop"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with Layout, drop fn, and :drop cleanup should pass"))

;; R1-3: local drop definition
(fn child-drop-allows-layout-with-local-drop []
  "A file creating Layout with (local drop (fn ...)) should be accepted as a
  public drop path — Task-4 emits local definitions with kind :local."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :local
                                             :name "drop"
                                             :top-level? true
                                             :line 20 :column 1
                                             :length 8
                                             :form "(local drop (fn [self] (self.child:drop)))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}
                                      {:callee "self.child:drop"
                                       :receiver nil :method nil
                                       :line 21 :column 1
                                       :form "(self.child:drop)"
                                       :enclosing-fn "<anonymous>"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with Layout and local drop should pass"))

(fn child-drop-flags-layoutroot-without-public-drop []
  "A file creating LayoutRoot with a :drop method call but no drop definition
  or export key 'drop' should be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :calls [{:callee "LayoutRoot"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(LayoutRoot {:child child})"
                                       :enclosing-fn nil}
                                      {:callee "root:drop"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(root:drop)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for LayoutRoot without public drop path")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path"))

(fn child-drop-allows-layoutroot-with-exported-drop []
  "A file creating LayoutRoot with an export key 'drop' and :drop cleanup should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :exports [{:key "drop"
                                         :line 20 :column 1
                                         :form "(fn drop [self] (self.root:drop))"}]
                              :definitions [{:kind :fn
                                             :name "drop"
                                             :top-level? true
                                             :line 20 :column 1
                                             :length 80
                                             :form "(fn drop [self] (self.root:drop))"}]
                              :calls [{:callee "LayoutRoot"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(LayoutRoot {:child child})"
                                       :enclosing-fn nil}
                                      {:callee "self.root:drop"
                                       :receiver nil :method nil
                                       :line 21 :column 1
                                       :form "(self.root:drop)"
                                       :enclosing-fn "drop"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with LayoutRoot, export :drop, and cleanup should pass"))

(fn child-drop-flags-scene-children-without-public-drop []
  "A file with :scene-children and clear-children but no drop fn/export should
  be flagged for missing public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                               :accesses [{:path ["self" "scene-children"]
                                           :text "self.scene-children"
                                           :line 10 :column 1
                                           :form "self.scene-children"}]
                               :mutations [{:op :set
                                            :path ["self" "scene-children"]
                                            :line 10 :column 1
                                            :form "(set self.scene-children [])"}]
                               :calls [{:callee "clear-children"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(clear-children)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for missing public drop path")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path"))

(fn child-drop-allows-scene-children-with-drop-export-and-clear []
  "A file with :scene-children and clear-children call plus a drop export should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "drop"
                                             :top-level? true
                                             :line 20 :column 1
                                             :length 80
                                             :form "(fn drop [self] (clear-children))"}]
                               :accesses [{:path ["self" "scene-children"]
                                           :text "self.scene-children"
                                           :line 10 :column 1
                                           :form "self.scene-children"}]
                               :mutations [{:op :set
                                            :path ["self" "scene-children"]
                                            :line 10 :column 1
                                            :form "(set self.scene-children [])"}]
                               :calls [{:callee "clear-children"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(clear-children)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with scene-children, drop fn, and clear-children should pass"))

(fn child-drop-allows-scene-objects-with-drop-export []
  "A file with :scene-objects access and drop-children call plus a drop export should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :exports [{:key "drop"
                                         :line 20 :column 1
                                         :form "(fn drop [self] ...)"}]
                              :definitions [{:kind :fn
                                             :name "drop"
                                             :top-level? true
                                             :line 20 :column 1
                                             :length 80
                                             :form "(fn drop [self] (drop-children))"}]
                               :accesses [{:path ["self" "scene-objects"]
                                           :text "self.scene-objects"
                                           :line 10 :column 1
                                           :form "self.scene-objects"}]
                               :mutations [{:op :set
                                            :path ["self" "scene-objects"]
                                            :line 10 :column 1
                                            :form "(set self.scene-objects [])"}]
                               :calls [{:callee "drop-children"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(drop-children)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with scene-objects, drop export, and drop-children should pass"))

(fn child-drop-flags-layout-without-drop []
  "A file creating Layout without any drop evidence should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for Layout without drop")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.owned-child-drop")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "layout-rendering") "diagnostic should have family layout-rendering")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence"))

(fn child-drop-flags-layoutroot-without-drop []
  "A file creating LayoutRoot without any drop evidence should produce a diagnostic."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                              :calls [{:callee "LayoutRoot"
                                       :receiver nil :method nil
                                       :line 10 :column 1
                                       :form "(LayoutRoot {:child child})"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for LayoutRoot without drop")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.owned-child-drop")
          "diagnostic should have correct constraint-id"))

(fn child-drop-flags-scene-children-without-drop []
  "A file accessing :scene-children without drop evidence should be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                               :accesses [{:path ["self" "scene-children"]
                                           :text "self.scene-children"
                                           :line 10 :column 1
                                           :form "self.scene-children"}]
                               :mutations [{:op :set
                                            :path ["self" "scene-children"]
                                            :line 10 :column 1
                                            :form "(set self.scene-children [])"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for scene-children without drop")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "layout.owned-child-drop")
          "diagnostic should have correct constraint-id"))

(fn child-drop-flags-scene-terrains-without-drop []
  "A file accessing :scene-terrains without drop evidence should be flagged."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                               :accesses [{:path ["self" "scene-terrains"]
                                           :text "self.scene-terrains"
                                           :line 10 :column 1
                                           :form "self.scene-terrains"}]
                               :mutations [{:op :set
                                            :path ["self" "scene-terrains"]
                                            :line 10 :column 1
                                            :form "(set self.scene-terrains [])"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for scene-terrains without drop")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn child-drop-flags-renderer-child-without-public-drop []
  "A file with renderer.children and a :drop call but no drop fn/export should
  be flagged for missing public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-widget.fnl"
                              :module "bad-widget"
                               :accesses [{:path ["renderer" "children"]
                                           :text "renderer.children"
                                           :line 10 :column 1
                                           :form "renderer.children"}]
                               :mutations [{:op :set
                                            :path ["renderer" "children"]
                                            :line 10 :column 1
                                            :form "(set renderer.children [])"}]
                               :calls [{:callee "renderer:drop"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(renderer:drop)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for renderer children without public drop path")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path"))

;; R2-1: set-based drop assignment counts as public drop path
(fn child-drop-allows-set-drop-assignment []
  "A file creating Layout with (set obj.drop (fn ...)) should be
  accepted as providing a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}
                                      {:callee "button:drop"
                                       :receiver nil :method nil
                                       :line 12 :column 1
                                       :form "(button:drop)"
                                       :enclosing-fn nil}]
                              :mutations [{:op :set
                                           :path ["button" "drop"]
                                           :line 10 :column 1
                                           :form "(set button.drop (fn [] (print :cleanup)))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with set-based drop assignment should pass"))

;; R2-2: tset-based drop assignment counts as public drop path
(fn child-drop-allows-tset-drop-assignment []
  "A file creating Layout with (tset obj :drop (fn ...)) should be
  accepted as providing a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}
                                      {:callee "widget:drop"
                                       :receiver nil :method nil
                                       :line 12 :column 1
                                       :form "(widget:drop)"
                                       :enclosing-fn nil}]
                              :mutations [{:op :tset
                                           :path ["widget" "drop"]
                                           :line 10 :column 1
                                           :form "(tset widget :drop (fn [] (clear-children)))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with tset-based drop assignment should pass"))

;; R2-3: mutation on non-final path segment is not recognized as drop
(fn child-drop-flags-non-final-drop-mutation []
  "A file with a mutation whose path ends differently (e.g., ['drop' 'inner'])
  should NOT count as a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}]
                              :mutations [{:op :set
                                           :path ["drop" "inner"]
                                           :line 10 :column 1
                                           :form "(set drop.inner 42)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag retained Layout without public drop path")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path for non-final drop mutation"))

;; R2-4: non-function set/tset .drop does not count as public drop path
(fn child-drop-flags-non-fn-drop-assignment []
  "A file creating Layout with (set x.drop nil) or (set x.drop false)
  should NOT be accepted as providing a public drop path.  Only function
  assignments (set x.drop (fn ...)) count as a public drop API."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  ;; (set options.drop false) is not a public drop function
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}]
                              :mutations [{:op :set
                                           :path ["options" "drop"]
                                           :line 10 :column 1
                                           :form "(set options.drop false)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag retained Layout with non-fn drop assignment")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path for non-fn drop assignment"))

;; R2-5: set x.drop nil does not count as public drop
(fn child-drop-flags-nil-drop-assignment []
  "A file creating Layout with (set x.drop nil) should NOT count nil
  assignment as a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :calls [{:callee "Layout" :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}]
                              :mutations [{:op :set
                                           :path ["widget" "drop"]
                                           :line 10 :column 1
                                           :form "(set widget.drop nil)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag retained Layout with nil drop assignment")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path for nil drop assignment"))

;; R2-6: set x.drop some-symbol does not count as public drop
(fn child-drop-flags-symbol-drop-assignment []
  "A file creating Layout with (set x.drop some-fn) where some-fn is a symbol
  (not a function literal) should NOT count as a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :calls [{:callee "Layout" :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}]
                              :mutations [{:op :set
                                           :path ["widget" "drop"]
                                           :line 10 :column 1
                                           :form "(set widget.drop some-fn)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag retained Layout with symbol drop assignment")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path for symbol drop assignment"))

;; R2-7: tset x :drop false does not count as public drop
(fn child-drop-flags-tset-false-drop-assignment []
  "A file creating Layout with (tset obj :drop false) should NOT count
  as a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :calls [{:callee "Layout" :receiver nil :method nil
                                       :line 5 :column 1
                                       :form "(Layout {:child child})"
                                       :enclosing-fn nil}]
                              :mutations [{:op :tset
                                           :path ["obj" "drop"]
                                           :line 10 :column 1
                                           :form "(tset obj :drop false)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag retained Layout with tset false drop assignment")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop path for tset false drop assignment"))

;; R3-1: returned table :drop (fn ...) satisfies public drop path
(fn child-drop-allows-returned-table-drop-fn []
  "A file creating Layout and returning {:layout layout :drop (fn [_] ...)}
  should satisfy the public drop path requirement."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 200
                                             :form "(fn make-widget []
  (let [layout (Layout {:child child})]
    {:layout layout :drop (fn [_]
                            (layout:drop))}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "make-widget"}
                                      {:callee "layout:drop"
                                       :receiver nil :method nil
                                       :line 5 :column 5
                                       :form "(layout:drop)"
                                       :enclosing-fn "make-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "returned table :drop (fn ...) should satisfy public drop path"))

(fn child-drop-allows-anonymous-builder-returned-table-drop-fn []
  "Anonymous retained builder with nested callbacks returns inline :drop."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local builder-form "(fn [ctx]
  (var root-layout nil)
  (set root-layout (Layout {:children []}))
  (when root-layout.children
    (print :has-children))
  (set changed-handler (events:connect
                         (fn [_payload]
                           (request-rebuild!))))
  {:layout root-layout
   :update (fn [_self]
             (request-rebuild!))
   :drop (fn [_self]
           (root-layout:drop))})")
  (local callback-form "(fn [_payload]
  (request-rebuild!))")
  (local update-form "(fn [_self]
  (request-rebuild!))")
  (local drop-form "(fn [_self]
  (root-layout:drop))")
  (local ff (make-file-fact {:path "/src/activity-dock-view.fnl"
                              :module "activity-dock-view"
                              :definitions [{:kind :local
                                             :name "build"
                                             :top-level? false
                                             :line 2 :column 3
                                             :length 250
                                             :form (.. "(local build\n  " builder-form ")")
                                             :enclosing-fn "ActivityDockView"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 3 :column 5
                                             :length 240
                                             :form builder-form
                                             :enclosing-fn "ActivityDockView"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 6 :column 26
                                             :length 40
                                             :form callback-form
                                             :enclosing-fn "<anonymous>"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 10 :column 12
                                             :length 35
                                             :form update-form
                                             :enclosing-fn "<anonymous>"}
                                            {:kind :fn
                                             :name "<anonymous>"
                                             :top-level? false
                                             :line 12 :column 10
                                             :length 45
                                             :form drop-form
                                             :enclosing-fn "<anonymous>"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 5 :column 20
                                       :form "(Layout {:children []})"
                                       :enclosing-fn "<anonymous>"}
                                      {:callee "root-layout:drop"
                                       :receiver "root-layout" :method "drop"
                                       :line 13 :column 12
                                       :form "(root-layout:drop)"
                                       :enclosing-fn "<anonymous>"}]
                              :accesses [{:path ["root-layout" "children"] :text "root-layout.children"
                                          :line 6 :column 9 :form "root-layout.children"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "anonymous builder returned table :drop fn should satisfy public drop"))

(fn child-drop-allows-returned-table-drop-lambda []
  "Returned {:drop (lambda [_] ...)} satisfies public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 150
                                             :form "(fn make-widget []
  (let [root-layout (Layout {:children []})]
    {:layout root-layout :drop (lambda [_]
                                 (root-layout:drop))}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 22
                                       :form "(Layout {:children []})"
                                       :enclosing-fn "make-widget"}
                                      {:callee "root-layout:drop"
                                       :receiver "root-layout" :method "drop"
                                       :line 4 :column 34
                                       :form "(root-layout:drop)"
                                       :enclosing-fn "make-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "returned table :drop (lambda ...) should satisfy public drop path"))

;; R3-2-negative: returned table :drop symbol is NOT accepted
;; Symbolic :drop <symbol> resolution is not reliably available from
;; file-facts. Only inline (fn ...)/(lambda ...) is accepted.
(fn child-drop-flags-returned-table-drop-symbol []
  "A returned table {:drop cleanup} where cleanup is a same-scope
  function-valued local should NOT satisfy the public drop path —
  symbolic resolution is not supported."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 250
                                             :form "(fn make-widget []
  (let [layout (Layout {:child child})
        cleanup (fn []
                  (layout:drop))]
    {:layout layout :drop cleanup}))"}
                                            {:kind :local
                                             :name "cleanup"
                                             :top-level? false
                                             :line 3 :column 9
                                             :length 60
                                             :form "(local cleanup (fn []
  (layout:drop))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "make-widget"}
                                      {:callee "layout:drop"
                                       :receiver nil :method nil
                                       :line 4 :column 7
                                       :form "(layout:drop)"
                                       :enclosing-fn "make-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "returned table :drop symbol should flag missing public drop")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop for symbolic :drop"))

;; V12-1: other-scope function-valued symbol regression
;; make-widget returns {:drop cleanup} but cleanup is defined in an
;; unrelated function/scope. Symbolic resolution must not accept the
;; other-scope definition.
(fn child-drop-flags-other-scope-drop-symbol []
  "A child-creating function returning {:drop cleanup} where cleanup is
  a function-valued local in a different scope should be flagged.
  Symbolic :drop must not resolve across scopes."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "setup-cleanup"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 100
                                             :form "(fn setup-cleanup []
  (local cleanup (fn []
    (print :cleaning-up))))"}
                                            {:kind :local
                                             :name "cleanup"
                                             :top-level? false
                                             :line 2 :column 3
                                             :length 50
                                             :form "(local cleanup (fn []
  (print :cleaning-up)))"}
                                            {:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 100
                                             :form "(fn make-widget []
  (let [layout (Layout {:child child})]
    {:layout layout :drop cleanup}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 6 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "make-widget"}
                                      {:callee "layout:drop"
                                       :receiver nil :method nil
                                       :line 7 :column 5
                                       :form "(layout:drop)"
                                       :enclosing-fn "make-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "other-scope :drop symbol should flag missing public drop")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop for other-scope symbol"))

;; R3-3: returned table :drop false/nil does NOT satisfy public drop path
(fn child-drop-flags-returned-table-drop-false []
  "A returned table {:drop false} should NOT count as a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 150
                                             :form "(fn make-widget []
  (let [layout (Layout {:child child})]
    {:layout layout :drop false}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "make-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "returned :drop false should still flag missing public drop")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop for :drop false"))

;; R3-4: returned table :drop nil does NOT satisfy public drop path
(fn child-drop-flags-returned-table-drop-nil []
  "A returned table {:drop nil} should NOT count as a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 150
                                             :form "(fn make-widget []
  (let [layout (Layout {:child child})]
    {:layout layout :drop nil}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "make-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "returned :drop nil should still flag missing public drop")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop for :drop nil"))

;; R9-1: returned :drop in one function does NOT exempt creation in another
(fn child-drop-flags-unrelated-returned-drop []
  "Returned :drop in A must not cover same-line B's same-text child access."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "helper-with-drop"
                                              :top-level? true
                                              :line 1 :column 1
                                              :length 100
                                              :form "(fn helper-with-drop [] (let [root (Layout {:children []})] (when root.children (print :owned)) {:layout root :drop (fn [] (root:drop))}))"}
                                             {:kind :fn
                                              :name "make-widget"
                                              :top-level? true
                                              :line 1 :column 150
                                              :length 100
                                              :form "(fn make-widget [] (when root.children (print :leaked)))"}]
                               :calls [{:callee "Layout" :receiver nil :method nil :line 1 :column 36
                                        :form "(Layout {:children []})" :enclosing-fn "helper-with-drop"}
                                       {:callee "root:drop" :receiver "root" :method "drop" :line 1 :column 121
                                        :form "(root:drop)" :enclosing-fn "helper-with-drop"}]
                               :accesses [{:path ["root" "children"] :text "root.children" :line 1 :column 70 :form "root.children"}
                                           {:path ["root" "children"] :text "root.children" :line 1 :column 174 :form "root.children"}]
                               :mutations [{:op :set :path ["root" "children"] :line 1 :column 174
                                            :form "(set root.children [])"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "unrelated returned :drop should not exempt access-only child creator")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop for unrelated access"))

(fn child-drop-flags-returned-drop-non-fn-symbol []
  "A returned table {:drop x} where x is a local bound to non-function
  should NOT count as a public drop path."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 200
                                             :form "(fn make-widget []
  (let [layout (Layout {:child child})
        cleanup false]
    {:layout layout :drop cleanup}))"}
                                            {:kind :local
                                             :name "cleanup"
                                             :top-level? false
                                             :line 3 :column 9
                                             :length 20
                                             :form "(local cleanup false)"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "make-widget"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "returned :drop non-fn symbol should still flag")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop for non-fn symbol"))

;; R9-3: valid public drop path but missing cleanup evidence
(fn child-drop-flags-missing-cleanup-with-returned-drop []
  "A file with valid returned :drop but no :drop/clear-children/drop-children
  call should still report missing cleanup evidence."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "make-widget"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 150
                                             :form "(fn make-widget []
  (let [layout (Layout {:child child})]
    {:layout layout :drop (fn [_]
                            (layout:drop))}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "make-widget"}]
                              ;; No :drop/clear-children/drop-children call
                              }))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should report missing cleanup despite valid returned :drop")
  (var found-missing-cleanup false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "child drop evidence")
      (set found-missing-cleanup true)))
  (assert found-missing-cleanup "should flag missing child drop evidence"))

;; V11-1: two child-creating functions, only one has returned :drop
(fn child-drop-flags-two-creators-one-drop []
  "File has two child-creating functions; only one returns :drop (fn ...).
  The other must still report missing public drop."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn
                                             :name "widget-a"
                                             :top-level? true
                                             :line 1 :column 1
                                             :length 100
                                             :form "(fn widget-a []
  (Layout {:child child}))"}
                                            {:kind :fn
                                             :name "widget-b"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 150
                                             :form "(fn widget-b []
  (let [layout (Layout {:child child})]
    {:layout layout :drop (fn [_] (layout:drop))}))"}]
                              :calls [{:callee "Layout"
                                       :receiver nil :method nil
                                       :line 2 :column 3
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "widget-a"}
                                      {:callee "Layout"
                                       :receiver nil :method nil
                                       :line 6 :column 15
                                       :form "(Layout {:child child})"
                                       :enclosing-fn "widget-b"}
                                      {:callee "layout:drop"
                                       :receiver nil :method nil
                                       :line 8 :column 5
                                       :form "(layout:drop)"
                                       :enclosing-fn "widget-b"}]}))
  (var result (rule.run (make-ctx [ff])))
  (assert result "should report missing drop for widget-a")
  (var found-missing-drop false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "drop definition or returned table :drop")
      (set found-missing-drop true)))
  (assert found-missing-drop "should flag missing public drop for unreturned def"))


;; Register all child-drop tests
;; layout.owned-child-drop
(table.insert tests {:name "child-drop allows file without retained children"
                      :fn child-drop-allows-file-without-retained-children})
(table.insert tests {:name "child-drop allows Layout with drop fn"
                      :fn child-drop-allows-layout-with-drop-fn})
;; R1-3: local drop
(table.insert tests {:name "child-drop allows Layout with local drop"
                     :fn child-drop-allows-layout-with-local-drop})
(table.insert tests {:name "child-drop flags LayoutRoot without public drop"
                     :fn child-drop-flags-layoutroot-without-public-drop})
(table.insert tests {:name "child-drop allows LayoutRoot with exported drop"
                     :fn child-drop-allows-layoutroot-with-exported-drop})
(table.insert tests {:name "child-drop flags scene-children without public drop"
                     :fn child-drop-flags-scene-children-without-public-drop})
(table.insert tests {:name "child-drop allows scene-children with drop export and clear"
                     :fn child-drop-allows-scene-children-with-drop-export-and-clear})
(table.insert tests {:name "child-drop allows scene-objects with drop export"
                     :fn child-drop-allows-scene-objects-with-drop-export})
(table.insert tests {:name "child-drop flags Layout without drop"
                     :fn child-drop-flags-layout-without-drop})
(table.insert tests {:name "child-drop flags LayoutRoot without drop"
                     :fn child-drop-flags-layoutroot-without-drop})
(table.insert tests {:name "child-drop flags scene-children without drop"
                     :fn child-drop-flags-scene-children-without-drop})
(table.insert tests {:name "child-drop flags scene-terrains without drop"
                     :fn child-drop-flags-scene-terrains-without-drop})
(table.insert tests {:name "child-drop flags renderer child without public drop"
                     :fn child-drop-flags-renderer-child-without-public-drop})
;; R2-1: set-based drop assignment
(table.insert tests {:name "child-drop allows set drop assignment"
                     :fn child-drop-allows-set-drop-assignment})
;; R2-2: tset-based drop assignment
(table.insert tests {:name "child-drop allows tset drop assignment"
                     :fn child-drop-allows-tset-drop-assignment})
;; R2-3: non-final drop mutation still flags
(table.insert tests {:name "child-drop flags non-final drop mutation"
                     :fn child-drop-flags-non-final-drop-mutation})
;; R2-4: non-fn drop assignment does not count as public drop
(table.insert tests {:name "child-drop flags non-fn drop assignment"
                     :fn child-drop-flags-non-fn-drop-assignment})
;; R2-5: nil drop assignment does not count
(table.insert tests {:name "child-drop flags nil drop assignment"
                     :fn child-drop-flags-nil-drop-assignment})
;; R2-6: symbol drop assignment does not count
(table.insert tests {:name "child-drop flags symbol drop assignment"
                     :fn child-drop-flags-symbol-drop-assignment})
;; R2-7: tset false drop assignment does not count
(table.insert tests {:name "child-drop flags tset false drop assignment"
                     :fn child-drop-flags-tset-false-drop-assignment})
;; R3-1: returned table :drop (fn ...)
(table.insert tests {:name "child-drop allows returned table drop fn"
                      :fn child-drop-allows-returned-table-drop-fn})
;; R11-precision: anonymous builder with nested callbacks still passes
(table.insert tests {:name "child-drop allows anonymous builder returned table drop fn"
                      :fn child-drop-allows-anonymous-builder-returned-table-drop-fn})
(table.insert tests {:name "child-drop allows returned table drop lambda"
                      :fn child-drop-allows-returned-table-drop-lambda})
;; R3-2-negative: returned table :drop symbol is NOT accepted
(table.insert tests {:name "child-drop flags returned table drop symbol"
                      :fn child-drop-flags-returned-table-drop-symbol})
;; V12-1: other-scope function-valued symbol regression
(table.insert tests {:name "child-drop flags other-scope drop symbol"
                     :fn child-drop-flags-other-scope-drop-symbol})
;; R3-3: returned table :drop false does not count
(table.insert tests {:name "child-drop flags returned table drop false"
                     :fn child-drop-flags-returned-table-drop-false})
;; R3-4: returned table :drop nil does not count
(table.insert tests {:name "child-drop flags returned table drop nil"
                     :fn child-drop-flags-returned-table-drop-nil})
;; R9-1: unrelated returned :drop does not exempt
(table.insert tests {:name "child-drop flags unrelated returned drop"
                     :fn child-drop-flags-unrelated-returned-drop})
;; R9-2: :drop symbol where symbol is non-function
(table.insert tests {:name "child-drop flags returned drop non-fn symbol"
                      :fn child-drop-flags-returned-drop-non-fn-symbol})
;; R9-3: valid :drop but missing cleanup
(table.insert tests {:name "child-drop flags missing cleanup with returned drop"
                      :fn child-drop-flags-missing-cleanup-with-returned-drop})
;; V11-1: two child-creating functions, only one has returned :drop
(table.insert tests {:name "child-drop flags two creators one drop"
                     :fn child-drop-flags-two-creators-one-drop})

(local main
  (fn []
    (local runner (require :tests.runner))
    (runner.run-tests {:name "constraints-rules-layout-child-drop"
                       :tests tests})))

{:name "constraints-rules-layout-child-drop"
 :tests tests
 :main main}
