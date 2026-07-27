;; Tests for Layout/Rendering constraint rules.
;; Follows TDD: these tests must FAIL before layout.fnl is implemented.

(local tests [])

;; --- Helpers for constructing synthetic fact DBs ---

(fn make-file-fact [opts]
  "Create a synthetic file-fact record for testing rule functions."
  (local o (or opts {}))
  {:target (or o.target {:kind :repo :name :test})
   :path (or o.path "/test/module.fnl")
   :module (or o.module "test-module")
   :requires (or o.requires [])
   :definitions (or o.definitions [])
   :exports (or o.exports [])
   :calls (or o.calls [])
   :accesses (or o.accesses [])
   :mutations (or o.mutations [])
   :metrics (or o.metrics {:module-lines 0
                           :max-nesting-depth 0
                           :max-anonymous-callback-depth 0
                           :max-table-literal-size 0
                           :functions []})})

(fn make-fact-db [file-facts]
  "Create a synthetic fact-db from a list of file-fact records."
  (let [by-file {}]
    (each [_ ff (ipairs file-facts)]
      (tset by-file ff.path ff))
    {:files file-facts
     :by-file by-file}))

(fn make-ctx [file-facts]
  "Create a context table for rule execution."
  {:target {:kind :repo :name :test}
   :facts (make-fact-db file-facts)
   :files []})

(fn find-rule-by-id [rules id]
  "Find a rule in a rules list by its :id field."
  (var found nil)
  (each [_ r (ipairs rules)]
    (when (= r.id id)
      (set found r)))
  found)

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

;; ======================================================================
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
  "A file creating Layout with a drop function should pass."
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
  (assert (= result nil) "file with Layout and drop fn should pass"))

(fn child-drop-allows-layoutroot-with-drop-method []
  "A file creating LayoutRoot with a :drop method call should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
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
  (assert (= result nil) "file with LayoutRoot and :drop method should pass"))

(fn child-drop-allows-scene-children-with-clear-children []
  "A file with :scene-children and clear-children call should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              ;; Access to :scene-children triggers the child-creation check
                              :accesses [{:path ["self" "scene-children"]
                                          :text "self.scene-children"
                                          :line 10 :column 1
                                          :form "self.scene-children"}]
                              :calls [{:callee "clear-children"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(clear-children)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with scene-children and clear-children should pass"))

(fn child-drop-allows-scene-objects-with-drop-children []
  "A file with :scene-objects access and drop-children call should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :accesses [{:path ["self" "scene-objects"]
                                          :text "self.scene-objects"
                                          :line 10 :column 1
                                          :form "self.scene-objects"}]
                              :calls [{:callee "drop-children"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(drop-children)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with scene-objects and drop-children should pass"))

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
                                          :form "self.scene-children"}]}))
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
                                          :form "self.scene-terrains"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for scene-terrains without drop")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn child-drop-allows-renderer-child-field-with-drop []
  "A file with renderer child field (e.g. renderer.children) and drop method should pass."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :accesses [{:path ["renderer" "children"]
                                          :text "renderer.children"
                                          :line 10 :column 1
                                          :form "renderer.children"}]
                              :calls [{:callee "renderer:drop"
                                       :receiver nil :method nil
                                       :line 15 :column 1
                                       :form "(renderer:drop)"
                                       :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with renderer.children and :drop should pass"))

;; ======================================================================
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

(fn interactive-assertion-allows-clickables-with-assert []
  "A function using clickables with assert should pass."
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
  (let [clickables (assert ctx.clickables \"missing clickables\")]
    (set-clickables clickables))"}]
                              :accesses [{:path ["ctx" "clickables"]
                                          :text "ctx.clickables"
                                          :line 6 :column 1
                                          :form "ctx.clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with clickables and assert should pass"))

(fn interactive-assertion-allows-hoverables-with-assert []
  "A function using hoverables with assert should pass."
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
  (let [hoverables (assert ctx.hoverables \"missing hoverables\")]
    (set-hoverables hoverables))"}]
                              :accesses [{:path ["ctx" "hoverables"]
                                          :text "ctx.hoverables"
                                          :line 6 :column 1
                                          :form "ctx.hoverables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with hoverables and assert should pass"))

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
  "A function guarding clickables with when/or/if silently (no assert) should be flagged."
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

(fn interactive-assertion-allows-bare-clickables-with-assert []
  "A function using 'clickables' (not ctx.clickables) with assert should pass."
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
  (let [cs (assert clickables \"missing clickables\")]
    (process cs))"}]
                              :accesses [{:path ["clickables"]
                                          :text "clickables"
                                          :line 6 :column 1
                                          :form "clickables"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "bare clickables with assert in same function should pass"))

(fn interactive-assertion-flags-hoverables-with-when-no-assert []
  "A function silently guarding hoverables with when without assert should be flagged."
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

;; ======================================================================
;; Structure tests
;; ======================================================================

(fn layout-rules-returns-table-with-three-rules []
  "Layout.rules() should return a table with exactly 3 rules."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (assert (= (type rules) :table) "rules should be a table")
  (assert (= (length rules) 3) (.. "expected 3 rules, got " (length rules))))

(fn layout-rules-have-required-structure []
  "Each layout rule should have :id, :family, :targets, :kind, :run, and :fn."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) (.. "rule should have string :id, got " (tostring rule.id)))
    (assert (= rule.family "layout-rendering") (.. "rule should have family layout-rendering, got " (tostring rule.family)))
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (= rule.kind :static) (.. "rule should be kind static, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) (.. "rule should have :run function for id " (tostring rule.id)))
    (assert (= (type rule.fn) :function) (.. "rule should have :fn function for id " (tostring rule.id)))
    (assert (= rule.fn rule.run) (.. ":fn should alias :run for id " (tostring rule.id)))))

;; ======================================================================
;; Runner integration tests
;; ======================================================================

(fn layout-runner-executable []
  "Layout.rules() entries must be executable by constraints.runner.run."
  (local Layout (require :constraints.rules.layout))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (Layout.rules))
  (local target {:kind :repo :name :test
                 :facts (make-fact-db [(make-file-fact {:path "/test/clean.fnl"
                                                         :module "test-clean"
                                                         :accesses []
                                                         :calls []
                                                         :definitions []})])
                 :files []})
  (local result (ConstraintRunner.run {:rules rules :target target
                                        :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (= result.status :pass) (.. "expected :pass status, got " result.status))
  (assert (= (length result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (length result.diagnostics))))

;; ======================================================================
;; Register all tests
;; ======================================================================

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

;; layout.owned-child-drop
(table.insert tests {:name "child-drop allows file without retained children"
                     :fn child-drop-allows-file-without-retained-children})
(table.insert tests {:name "child-drop allows Layout with drop fn"
                     :fn child-drop-allows-layout-with-drop-fn})
(table.insert tests {:name "child-drop allows LayoutRoot with drop method"
                     :fn child-drop-allows-layoutroot-with-drop-method})
(table.insert tests {:name "child-drop allows scene-children with clear-children"
                     :fn child-drop-allows-scene-children-with-clear-children})
(table.insert tests {:name "child-drop allows scene-objects with drop-children"
                     :fn child-drop-allows-scene-objects-with-drop-children})
(table.insert tests {:name "child-drop flags Layout without drop"
                     :fn child-drop-flags-layout-without-drop})
(table.insert tests {:name "child-drop flags LayoutRoot without drop"
                     :fn child-drop-flags-layoutroot-without-drop})
(table.insert tests {:name "child-drop flags scene-children without drop"
                     :fn child-drop-flags-scene-children-without-drop})
(table.insert tests {:name "child-drop flags scene-terrains without drop"
                     :fn child-drop-flags-scene-terrains-without-drop})
(table.insert tests {:name "child-drop allows renderer child field with drop"
                     :fn child-drop-allows-renderer-child-field-with-drop})

;; layout.interactive-context-assertion
(table.insert tests {:name "interactive-assertion allows file without clickables"
                     :fn interactive-assertion-allows-file-without-clickables})
(table.insert tests {:name "interactive-assertion allows clickables with assert"
                     :fn interactive-assertion-allows-clickables-with-assert})
(table.insert tests {:name "interactive-assertion allows hoverables with assert"
                     :fn interactive-assertion-allows-hoverables-with-assert})
(table.insert tests {:name "interactive-assertion flags clickables without assert"
                     :fn interactive-assertion-flags-clickables-without-assert})
(table.insert tests {:name "interactive-assertion flags hoverables without assert"
                     :fn interactive-assertion-flags-hoverables-without-assert})
(table.insert tests {:name "interactive-assertion flags assert in different function"
                     :fn interactive-assertion-flags-assert-in-different-function})
(table.insert tests {:name "interactive-assertion flags silent guard clickables"
                     :fn interactive-assertion-flags-silent-guard-clickables})
(table.insert tests {:name "interactive-assertion allows bare clickables with assert"
                     :fn interactive-assertion-allows-bare-clickables-with-assert})
(table.insert tests {:name "interactive-assertion flags hoverables with when no assert"
                     :fn interactive-assertion-flags-hoverables-with-when-no-assert})

;; Structure tests
(table.insert tests {:name "layout rules returns table with three rules"
                     :fn layout-rules-returns-table-with-three-rules})
(table.insert tests {:name "layout rules have required structure"
                     :fn layout-rules-have-required-structure})

;; Runner integration
(table.insert tests {:name "layout rules executable by runner"
                     :fn layout-runner-executable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-layout"
                        :tests tests})))

{:name "constraints-rules-layout"
 :tests tests
 :main main}
