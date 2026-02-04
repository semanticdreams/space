(local glm (require :glm))
(local GraphViewLabels (require :graph/view/labels))
(local BuildContext (require :build-context))
(local {:GraphNode GraphNode} (require :graph/node-base))

(local tests [])

(fn make-ctx []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn labels-create-span-with-defaults []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 0)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local node (GraphNode {:key "a" :label "Alpha"}))
    (local point {:position (glm.vec3 0 0 0) :size 6})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Labels should create text span for visible node")
    (assert span.layout "Label span should expose a layout")
    (assert (= span.style.scale 3)
            (string.format "LOD0 label should use scale 3 (got %s)" span.style.scale))
    (assert (= span.layout.depth-offset-index 1.0)
            "Label depth offset should default to 1.0")
    (assert span.layout.position "Label layout should assign a position")
    (labels:drop-all))

(fn labels-move-reassigns-span []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 0)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local first (GraphNode {:key "first" :label "First"}))
    (local second (GraphNode {:key "second" :label "Second"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {first point})
    (labels:update points [first] {:force? true})
    (local span (. labels.labels first))
    (assert span "Labels should create span for first node")
    (labels:move-label first second)
    (assert (not (. labels.labels first)) "Move should clear old label entry")
    (assert (= (. labels.labels second) span)
            "Move should reassign span to replacement node")
    (labels:update points [second] {:force? true})
    (labels:drop-node second)
    (assert (not (. labels.labels second)) "Drop-node should clear reassigned span")
    (labels:drop-all))

(table.insert tests {:name "GraphView labels create spans with defaults" :fn labels-create-span-with-defaults})
(table.insert tests {:name "GraphView labels move and drop reassigned spans" :fn labels-move-reassigns-span})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-labels"
                       :tests tests})))

{:name "graph-view-labels"
 :tests tests
 :main main}
