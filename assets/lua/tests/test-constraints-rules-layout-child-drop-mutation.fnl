;; Mutation-correlation tests for layout.owned-child-drop.
;; Split out to keep the main child-drop suite under structure limits.

(local H (require :tests.constraints-layout-helpers))
(local make-file-fact H.make-file-fact)
(local make-ctx H.make-ctx)
(local find-rule-by-id H.find-rule-by-id)
(local tests [])

(fn child-drop-allows-read-only-entity-children []
  "Read-only entity.children access should not count as retained child creation."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule layout.owned-child-drop should be in rules list")
  (local ff (make-file-fact {:path "/src/query.fnl"
                              :module "query"
                              :accesses [{:path ["entity" "children"]
                                          :text "entity.children"
                                          :line 10 :column 3
                                          :form "entity.children"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "read-only entity.children access should pass"))

(fn child-drop-allows-read-only-scene-children []
  "Read-only scene.scene-children access should not count as retained child creation."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule layout.owned-child-drop should be in rules list")
  (local ff (make-file-fact {:path "/src/scene-query.fnl"
                              :module "scene-query"
                              :accesses [{:path ["scene" "scene-children"]
                                          :text "scene.scene-children"
                                          :line 12 :column 5
                                          :form "scene.scene-children"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "read-only scene.scene-children access should pass"))

(fn child-drop-flags-mutated-children-without-drop []
  "A write to entity.children without drop/cleanup still indicates retained children."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule layout.owned-child-drop should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-children.fnl"
                              :module "bad-children"
                              :accesses [{:path ["entity" "children"]
                                          :text "entity.children"
                                          :line 8 :column 3
                                          :form "entity.children"}]
                              :mutations [{:op :set
                                           :path ["entity" "children"]
                                           :line 8 :column 3
                                           :form "(set entity.children [])"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "mutated entity.children without drop should flag")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn child-drop-flags-mutated-scene-children-without-drop []
  "A write to scene.scene-children without drop/cleanup still indicates retained children."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule layout.owned-child-drop should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-scene-children.fnl"
                              :module "bad-scene-children"
                              :accesses [{:path ["scene" "scene-children"]
                                          :text "scene.scene-children"
                                          :line 9 :column 3
                                          :form "scene.scene-children"}]
                              :mutations [{:op :tset
                                           :path ["scene" "scene-children"]
                                           :line 9 :column 3
                                           :form "(tset scene :scene-children [])"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "mutated scene.scene-children without drop should flag")
  (assert (> (length result) 0) "should have at least one diagnostic"))

(fn child-drop-still-flags-layout-and-layoutroot-constructors []
  "Layout and LayoutRoot constructor evidence must remain independent of access-path mutation."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule layout.owned-child-drop should be in rules list")
  (local layout-ff (make-file-fact {:path "/src/bad-layout.fnl"
                                    :module "bad-layout"
                                    :calls [{:callee "Layout"
                                             :receiver nil :method nil
                                             :line 10 :column 1
                                             :form "(Layout {:child child})"
                                             :enclosing-fn nil}]}))
  (local layout-root-ff (make-file-fact {:path "/src/bad-layout-root.fnl"
                                         :module "bad-layout-root"
                                         :calls [{:callee "LayoutRoot"
                                                  :receiver nil :method nil
                                                  :line 20 :column 1
                                                  :form "(LayoutRoot {:child child})"
                                                  :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [layout-ff layout-root-ff])))
  (assert result "Layout/LayoutRoot constructors without drop should still flag")
  (assert (>= (length result) 2) "both constructor-based creators should flag"))

(fn child-drop-allows-method-clear-children-cleanup []
  "A valid public drop path with (self:clear-children) should satisfy child cleanup evidence."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn :name "drop" :top-level? true
                                             :line 20 :column 1 :length 80
                                             :form "(fn drop [self]
  (self:clear-children))"}]
                              :accesses [{:path ["self" "children"] :text "self.children"
                                          :line 10 :column 1 :form "self.children"}]
                              :mutations [{:op :set :path ["self" "children"]
                                           :line 10 :column 1
                                           :form "(set self.children [])"}]
                              :calls [{:callee "self:clear-children"
                                       :receiver "self" :method "clear-children"
                                       :line 21 :column 1
                                       :form "(self:clear-children)"
                                       :enclosing-fn "drop"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "method-style self:clear-children should satisfy cleanup evidence"))

(fn child-drop-allows-method-drop-children-cleanup []
  "A valid public drop path with (root:drop-children) should satisfy child cleanup evidence."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn :name "drop" :top-level? true
                                             :line 20 :column 1 :length 80
                                             :form "(fn drop [root]
  (root:drop-children))"}]
                              :accesses [{:path ["root" "scene-objects"] :text "root.scene-objects"
                                          :line 10 :column 1 :form "root.scene-objects"}]
                              :mutations [{:op :set :path ["root" "scene-objects"]
                                           :line 10 :column 1
                                           :form "(set root.scene-objects [])"}]
                              :calls [{:callee "root:drop-children"
                                       :receiver "root" :method "drop-children"
                                       :line 21 :column 1
                                       :form "(root:drop-children)"
                                       :enclosing-fn "drop"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "method-style root:drop-children should satisfy cleanup evidence"))

(fn child-drop-still-flags-public-drop-without-cleanup []
  "A valid public drop path must still report missing child cleanup when no cleanup call exists."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn :name "drop" :top-level? true
                                             :line 20 :column 1 :length 80
                                             :form "(fn drop [self]
  (set self.children []))"}]
                              :accesses [{:path ["self" "children"] :text "self.children"
                                          :line 10 :column 1 :form "self.children"}]
                              :mutations [{:op :set :path ["self" "children"]
                                           :line 10 :column 1
                                           :form "(set self.children [])"}]
                              :calls []}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "public drop without child cleanup should still report diagnostics")
  (var found-missing-cleanup false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "child drop evidence")
      (set found-missing-cleanup true)))
  (assert found-missing-cleanup "should still flag missing child drop evidence"))

(fn child-drop-flags-dotted-cleanup-like-call []
  "A valid public drop path with only a dotted metrics.drop-children call should still report missing cleanup."
  (local Layout (require :constraints.rules.layout))
  (local rules (Layout.rules))
  (local rule (find-rule-by-id rules "layout.owned-child-drop"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/widget.fnl"
                              :module "widget"
                              :definitions [{:kind :fn :name "drop" :top-level? true
                                             :line 20 :column 1 :length 80
                                             :form "(fn drop [self]
  (metrics.drop-children))"}]
                              :accesses [{:path ["self" "children"] :text "self.children"
                                          :line 10 :column 1 :form "self.children"}]
                              :mutations [{:op :set :path ["self" "children"]
                                           :line 10 :column 1
                                           :form "(set self.children [])"}]
                              :calls [{:callee "metrics.drop-children"
                                       :receiver "metrics" :method "drop-children"
                                       :line 21 :column 1
                                       :form "(metrics.drop-children)"
                                       :enclosing-fn "drop"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "dotted cleanup-like call should not satisfy child cleanup")
  (var found-missing-cleanup false)
  (each [_ d (ipairs result)]
    (when (= d.evidence.missing "child drop evidence")
      (set found-missing-cleanup true)))
  (assert found-missing-cleanup "should flag missing cleanup for dotted cleanup-like call"))

(table.insert tests {:name "child-drop allows read-only entity children"
                     :fn child-drop-allows-read-only-entity-children})
(table.insert tests {:name "child-drop allows read-only scene children"
                     :fn child-drop-allows-read-only-scene-children})
(table.insert tests {:name "child-drop flags mutated children without drop"
                     :fn child-drop-flags-mutated-children-without-drop})
(table.insert tests {:name "child-drop flags mutated scene children without drop"
                     :fn child-drop-flags-mutated-scene-children-without-drop})
(table.insert tests {:name "child-drop still flags Layout and LayoutRoot constructors"
                     :fn child-drop-still-flags-layout-and-layoutroot-constructors})
(table.insert tests {:name "child-drop allows method clear-children cleanup"
                     :fn child-drop-allows-method-clear-children-cleanup})
(table.insert tests {:name "child-drop allows method drop-children cleanup"
                     :fn child-drop-allows-method-drop-children-cleanup})
(table.insert tests {:name "child-drop still flags public drop without cleanup"
                     :fn child-drop-still-flags-public-drop-without-cleanup})
(table.insert tests {:name "child-drop flags dotted cleanup-like call"
                     :fn child-drop-flags-dotted-cleanup-like-call})

(local main
  (fn []
    (local runner (require :tests.runner))
    (runner.run-tests {:name "constraints-rules-layout-child-drop-mutation"
                       :tests tests})))

{:name "constraints-rules-layout-child-drop-mutation"
 :tests tests
 :main main}
