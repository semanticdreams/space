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
                 :codepoints {:close 4242
                              :table 4242
                              :code 4242}})
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
             (set element.__test_panel_opts opts)
             (table.insert self.children element)
             (set self.last-add-panel-opts opts)
             element))
    (set target.remove-panel-child
         (fn [self element]
             (var removed false)
             (local kept [])
             (each [_ existing (ipairs self.children)]
                 (if (and (not removed) (= existing element))
                     (set removed true)
                     (table.insert kept existing)))
             (set self.children kept)
             removed))
    (set target.capture-panel-element-state
         (fn [_self element]
             (and element element.__test_panel_state)))
    (set target.register-panel-restorer
         (fn [self kind restorer owner]
             (set self.restorer {:kind kind :restorer restorer :owner owner})
             true))
    (set target.unregister-panel-restorer
         (fn [self _kind owner]
             (when (or (= owner nil)
                       (and self.restorer (= self.restorer.owner owner)))
                 (set self.restorer nil))
             true))
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
            (dialog:drop)))}
 {:name "graph view node-views persist panel placement and restore"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          (local node {:key "persist-node"
                       :label "Persist node"
                       :view (fn [_node]
                                 (fn [_builder-ctx _opts]
                                     (make-simple-view)))})
          (local graph {:nodes {}})
          (set (. graph.nodes node.key) node)
          (set graph.lookup (fn [_self key] (. graph.nodes key)))
          (set graph.load-by-key (fn [_self key] (. graph.nodes key)))
          (local views (GraphViewNodeViews {:ctx ctx
                                            :graph graph
                                            :view-target target}))
          (views:open node)
          (local dialog (. target.children 1))
          (set dialog.__test_panel_state {:layer "float"
                                          :position [1 2 3]
                                          :rotation [1 0 0 0]
                                          :size [7 8 9]})
          (local state (views:capture-state))
          (assert (= (length (or state.open-views [])) 1)
                  "capture-state should record one open node view")
          (local captured (. state.open-views 1))
          (assert (= captured.node-key node.key))
          (assert (= (and captured.panel captured.panel.layer) "float")
                  "capture-state should include panel placement")
          (views:drop-all)
          (target:remove-panel-child dialog)
          (views:restore-state {:open-views [{:node-key node.key
                                              :panel {:layer "tiles"
                                                      :align-x :end
                                                      :align-y :start}}]})
          (assert (= (length target.children) 1)
                  "restore-state should reopen persisted node view")
          (assert (= (and target.last-add-panel-opts target.last-add-panel-opts.location) :tiles))
          (assert (= (and target.last-add-panel-opts target.last-add-panel-opts.align-x) :end))
          (assert (= (and target.last-add-panel-opts target.last-add-panel-opts.align-y) :start))
          (assert (= (and target.last-add-panel-opts
                          target.last-add-panel-opts.persistence
                          target.last-add-panel-opts.persistence.kind)
                     "graph-node-view")))}
 {:name "graph view node-views restore skips unresolved nodes"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          (local graph {:lookup (fn [_self _key] nil)
                        :load-by-key (fn [_self _key] nil)})
          (local views (GraphViewNodeViews {:ctx ctx
                                            :graph graph
                                            :view-target target}))
          (views:restore-state {:open-views [{:node-key "terrain-tool:world-1:apply-perlin"}]})
          (assert (= (length target.children) 0)
                  "restore-state should skip unresolved node views")
          (local state (views:capture-state))
          (assert (= (length (or state.open-views [])) 1)
                  "capture-state should preserve unresolved restored node views")
          (assert (= (and (. state.open-views 1) (. (. state.open-views 1) :node-key))
                     "terrain-tool:world-1:apply-perlin"))
          (views:drop-all))}
 {:name "graph view node-views panel restorer skips unresolved nodes"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          (local graph {:lookup (fn [_self _key] nil)
                        :load-by-key (fn [_self _key] nil)})
          (local views (GraphViewNodeViews {:ctx ctx
                                            :graph graph
                                            :view-target target}))
          (assert (and target.restorer target.restorer.restorer)
                  "expected graph node views to register panel restorer")
          ((. target.restorer :restorer) {:node-key "terrain:world-1:node-a"
                                          :layer "float"})
          (assert (= (length target.children) 0)
                  "panel restorer should skip unresolved node views")
          (local state (views:capture-state))
          (assert (= (length (or state.open-views [])) 1)
                  "capture-state should preserve unresolved node views from panel restore")
          (assert (= (and (. state.open-views 1) (. (. state.open-views 1) :node-key))
                     "terrain:world-1:node-a"))
          (views:drop-all))}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hackernews-graph-view-node-views"
                       :tests tests})))

{:name "hackernews-graph-view-node-views"
 :tests tests
 :main main}
