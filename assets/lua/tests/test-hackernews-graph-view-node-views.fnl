(local glm (require :glm))
(local BuildContext (require :build-context))
(local GraphViewNodeViews (require :graph/view/node-views))
(local HackerNewsRootNode (require :graph/nodes/hackernews-root))
(local {: Layout} (require :layout))

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph
                             4242 glyph}})
    (local stub {:font font
                 :codepoints {:close 4242}})
    (set stub.get
         (fn [self name]
             (local value (. self.codepoints name))
             (assert value (.. "Missing icon " name))
             value))
    (set stub.resolve
         (fn [self name]
             (local code (self:get name))
             {:type :font
              :codepoint code
              :font self.font}))
    stub)

(fn make-ctx []
    (local ctx
      (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                     :hoverables (assert app.hoverables "test requires app.hoverables")}))
    (set ctx.icons (make-icons-stub))
    ctx)

(fn make-view-target [ctx]
    (local target {:build-context ctx :children []})
    (set target.add-panel-child
         (fn [self opts]
             (local builder (and opts opts.builder))
             (assert builder "builder required")
             (local element (builder self.build-context {}))
             (table.insert self.children element)
             element))
    target)

(fn make-simple-view []
    (local layout
      (Layout {:name "nested-view"
               :measurer (fn [self]
                             (set self.measure (glm.vec3 0 0 0)))
               :layouter (fn [_self] nil)}))
    {:layout layout
     :drop (fn [_self] (layout:drop))})

(local tests [{:name "graph view node-views build hackernews root dialog"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          (local views (GraphViewNodeViews {:ctx ctx
                                            :view-target target}))
          (local node (HackerNewsRootNode))
          ;; should build the hackernews root view without throwing
          (views:open node)
          (assert (= (length target.children) 1)
                  "graph view node-views should attach one dialog for the selected node")
          (local dialog (. target.children 1))
          (assert (and dialog dialog.layout)
                  "dialog should expose a layout for HUD attachment")
          (when dialog.drop
            (dialog:drop)))}
 {:name "graph view node-views unwrap nested builder functions"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          ;; node view returns a builder that returns another builder instead of a widget
          (local nested {:key "nested"
                         :label "nested"
                         :view (fn [_node]
                                   (fn [_builder-ctx _opts]
                                       (fn [_inner-ctx _inner-opts]
                                           (make-simple-view))))})
          (local views (GraphViewNodeViews {:ctx ctx
                                            :view-target target}))
          (views:open nested)
          (assert (= (length target.children) 1)
                  "graph view node-views should attach dialog even when view builder is nested")
          (local dialog (. target.children 1))
          (assert (and dialog dialog.layout)
                  "dialog should expose a layout even when unwrapped from nested builders")
          (when dialog.drop
            (dialog:drop)))}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hackernews-graph-view-node-views"
                       :tests tests})))

{:name "hackernews-graph-view-node-views"
 :tests tests
 :main main}
