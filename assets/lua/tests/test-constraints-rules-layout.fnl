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
;; R1-1: inline :layouter via call form text
(table.insert tests {:name "no-setters flags inline layouter via call form"
                     :fn no-setters-flags-inline-layouter-via-call-form})

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
(table.insert tests {:name "no-setters allows unrelated anonymous far from layouter"
                     :fn no-setters-allows-unrelated-anonymous-far-from-layouter})
;; R4-2: unrelated anonymous near layouter (within 5-line window)
(table.insert tests {:name "no-setters allows unrelated anonymous near layouter"
                     :fn no-setters-allows-unrelated-anonymous-near-layouter})
;; R3-F3: cross-anonymous-function assert
(table.insert tests {:name "interactive-assertion flags second anonymous without own assert"
                     :fn interactive-assertion-flags-second-anonymous-without-own-assert})
;; R4-1: comment-only clickables
(table.insert tests {:name "interactive-assertion allows comment-only clickables"
                     :fn interactive-assertion-allows-comment-only-clickables})
;; R5-1 adjudicated: long inline layouter beyond 10 lines from call start
(table.insert tests {:name "no-setters flags long inline layouter beyond 10 lines"
                     :fn no-setters-flags-long-inline-layouter-beyond-10-lines})
;; R5-1: duplicate anonymous form same as inline layouter
(table.insert tests {:name "no-setters allows unrelated anonymous with duplicate form"
                     :fn no-setters-allows-unrelated-anonymous-with-duplicate-form})
;; R5-1b: duplicate same-form — conservative skip (R6-1)
(table.insert tests {:name "no-setters skips inline layouter setter when duplicate anonymous present"
                     :fn no-setters-skips-inline-layouter-setter-when-duplicate-anonymous-present})
;; R6-1: duplicate same-form callbacks in same Layout call under different keys
(table.insert tests {:name "no-setters skips ambiguous duplicate callbacks in same call"
                     :fn no-setters-skips-ambiguous-duplicate-callbacks-in-same-call})
;; R4-3: comment-only assert in anonymous
(table.insert tests {:name "interactive-assertion flags comment-only assert in anonymous"
                     :fn interactive-assertion-flags-comment-only-assert-in-anonymous})

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
