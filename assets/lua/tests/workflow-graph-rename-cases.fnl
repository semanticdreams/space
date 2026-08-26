(fn definition-node [GraphMap runtime seeded id]
  (local map (GraphMap.GraphMap {:graph runtime.graph :id id}))
  (local node (map:load-by-key (.. "workflow-definition:" seeded.definition.id)))
  (values map node))

(fn workflow-definition-node-exposes-rename-and-view-case [deps runtime]
  (local seeded (deps.seed-definition-with-run runtime))
  (local (map node) (definition-node deps.GraphMap runtime seeded "definition-rename-node-map"))
  (assert node "workflow definition node should load")
  (assert node.update-name "workflow definition node should expose update-name")
  (assert node.view "workflow definition node should expose full view")
  (node:update-name "  Renamed Help Desk  ")
  (local definition (runtime.store:get-definition seeded.definition.id))
  (assert (= definition.name "Renamed Help Desk")
          "update-name should trim and persist workflow definition name")
  (assert (= node.label "Renamed Help Desk")
          "update-name should refresh node label")
  (map:drop))

(fn workflow-definition-rename-rejects-blank-case [deps runtime]
  (local seeded (deps.seed-definition-with-run runtime))
  (local (map node) (definition-node deps.GraphMap runtime seeded "definition-blank-rename-map"))
  (local (ok err) (pcall (fn [] (node:update-name "   "))))
  (assert (not ok) "blank workflow definition name should fail loudly")
  (assert (string.find (tostring err) "requires a non-empty name" 1 true)
          "blank workflow definition name failure should explain validation")
  (local after-definition (runtime.store:get-definition seeded.definition.id))
  (assert (= after-definition.name seeded.definition.name)
          "blank workflow definition name should not mutate stored name")
  (assert (= node.label seeded.definition.name)
          "blank workflow definition name should not mutate node label")
  (map:drop))

(fn workflow-definition-view-renames-definition-case [deps runtime]
  (local seeded (deps.seed-definition-with-run runtime))
  (local (map node) (definition-node deps.GraphMap runtime seeded "definition-view-rename-map"))
  (local View (require :graph/view/views/workflow-definition))
  (deps.assert-missing-build-context-with-fallbacks
    View
    node
    "workflow definition full view should not fall back to opts.ctx or graph.ctx")
  (local builder (View node {:node node}))
  (deps.assert-missing-build-context builder
                                     "workflow definition full view should assert on missing build context")
  (local widget (builder (deps.make-preview-ctx)))
  (assert widget.name-input "workflow definition full view should expose name input")
  (assert widget.title "workflow definition full view should expose title")
  (assert widget.help-text "workflow definition full view should expose help text")
  (assert widget.flex "workflow definition full view should expose flex")
  (assert (= (widget.name-input:get-text) seeded.definition.name)
          "workflow definition full view should initialize input from current definition name")
  (widget.name-input:set-text "Updated From Panel")
  (local after-definition (runtime.store:get-definition seeded.definition.id))
  (assert (= after-definition.name "Updated From Panel")
          "workflow definition full view input changes should persist workflow definition name")
  (assert (= node.label "Updated From Panel")
          "workflow definition full view input changes should update node label")
  (widget:drop)
  (map:drop))

(fn workflow-definition-view-drops-owned-children-case [deps runtime]
  (local seeded (deps.seed-definition-with-run runtime))
  (local (map node) (definition-node deps.GraphMap runtime seeded "definition-view-drop-map"))
  (local View (require :graph/view/views/workflow-definition))
  (local widget ((View node {:node node}) (deps.make-preview-ctx)))
  (local dropped {:title 0 :help 0 :name-input 0 :flex 0})
  (local original-title-drop widget.title.drop)
  (local original-help-drop widget.help-text.drop)
  (local original-name-drop widget.name-input.drop)
  (local original-flex-drop widget.flex.drop)
  (set widget.title.drop
       (fn [self]
         (set dropped.title (+ dropped.title 1))
         (original-title-drop self)))
  (set widget.help-text.drop
       (fn [self]
         (set dropped.help (+ dropped.help 1))
         (original-help-drop self)))
  (set widget.name-input.drop
       (fn [self]
         (set dropped.name-input (+ dropped.name-input 1))
         (original-name-drop self)))
  (set widget.flex.drop
       (fn [self]
         (set dropped.flex (+ dropped.flex 1))
         (original-flex-drop self)))
  (widget:drop)
  (assert (> dropped.title 0) "workflow definition full view should drop title")
  (assert (> dropped.help 0) "workflow definition full view should drop help text")
  (assert (> dropped.name-input 0) "workflow definition full view should drop name input")
  (assert (> dropped.flex 0) "workflow definition full view should drop flex")
  (map:drop))

(fn run-case [deps test-case runtime]
  (test-case deps runtime))

(fn runtime-test [deps test-case]
  (fn []
    (deps.with-runtime (fn [runtime] (run-case deps test-case runtime)))))

(fn cases [deps]
  [{:name "workflow-definition-node-exposes-rename-and-view"
    :fn (runtime-test deps workflow-definition-node-exposes-rename-and-view-case)}
   {:name "workflow-definition-rename-rejects-blank"
    :fn (runtime-test deps workflow-definition-rename-rejects-blank-case)}
   {:name "workflow-definition-view-renames-definition"
    :fn (runtime-test deps workflow-definition-view-renames-definition-case)}
   {:name "workflow-definition-view-drops-owned-children"
    :fn (runtime-test deps workflow-definition-view-drops-owned-children-case)}])

cases
