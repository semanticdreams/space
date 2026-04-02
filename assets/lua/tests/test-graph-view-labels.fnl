(local glm (require :glm))
(local GraphViewLabels (require :graph/view/labels))
(local BuildContext (require :build-context))
(local Camera (require :camera))
(local Scene (require :scene))
(local {:GraphNode GraphNode} (require :graph/node-base))

(local tests [])

(fn make-ctx []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn make-perspective-surface [opts]
    (local options (or opts {}))
    (local viewport (or options.viewport {:x 0 :y 0 :width 100 :height 100}))
    (local position (or options.position (glm.vec3 0 0 170)))
    (local camera (Camera {:position position}))
    (local scene (Scene {:camera camera
                         :position (glm.vec3 0 0 0)
                         :rotation (glm.quat 1 0 0 0)}))
    (scene:on-viewport-changed viewport)
    (when options.projection
        (set scene.projection options.projection)
        (set scene.projection-version (+ (or scene.projection-version 0) 1)))
    {:camera camera
     :surface scene})

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

(fn labels-update-when-camera-moves-without-debounced-signal []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 900)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local node (GraphNode {:key "camera-move" :label "Camera Move"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (assert (not (. labels.labels node))
            "Node should start hidden when camera is far enough for LOD3")
    (set camera.position (glm.vec3 0 0 0))
    (labels:update points [node] nil)
    (assert (. labels.labels node)
            "Label should appear when camera moves close, even without debounced camera signal")
    (labels:drop-all))

(fn labels-update-when-orthographic-surface-scale-changes []
    (local ctx (make-ctx))
    (local surface {:world-units-per-pixel 1.0})
    (local labels (GraphViewLabels {:ctx ctx :surface surface}))
    (local node (GraphNode {:key "canvas-scale" :label "Canvas Scale"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Label should appear at the default orthographic canvas scale")
    (assert (= span.style.scale 5)
            (string.format "Default orthographic LOD should use scale 5 (got %s)" span.style.scale))
    (set surface.world-units-per-pixel 0.1)
    (labels:update points [node] nil)
    (assert (= span.style.scale 3)
            (string.format "Zoomed-in orthographic LOD should use scale 3 (got %s)" span.style.scale))
    (set surface.world-units-per-pixel 4.0)
    (labels:update points [node] nil)
    (assert (not (. labels.labels node))
            "Label should hide when orthographic zoom is far enough out")
    (labels:drop-all))

(fn labels-update-when-perspective-surface-camera-moves-small-distance []
    (local ctx (make-ctx))
    (local {:camera camera :surface surface}
           (make-perspective-surface {:position (glm.vec3 0 0 81)}))
    (local labels (GraphViewLabels {:ctx ctx :camera camera :surface surface}))
    (local node (GraphNode {:key "scene-small-move" :label "Scene Small Move"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Label should be visible just outside the highest-detail threshold")
    (assert (= span.style.scale 5)
            (string.format "Initial perspective LOD should use scale 5 (got %s)" span.style.scale))
    (camera:set-position (glm.vec3 0 0 79.5))
    (labels:update points [node] nil)
    (assert (= span.style.scale 3)
            (string.format "Small perspective camera move should promote to scale 3 (got %s)"
                           span.style.scale))
    (labels:drop-all)
    (surface:drop)
    (camera:drop))

(fn labels-update-when-perspective-projection-changes []
    (local ctx (make-ctx))
    (local {:camera camera :surface surface}
           (make-perspective-surface {:position (glm.vec3 0 0 170)}))
    (local labels (GraphViewLabels {:ctx ctx :camera camera :surface surface}))
    (local node (GraphNode {:key "scene-projection" :label "Scene Projection"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Label should be visible at the default perspective projection")
    (assert (= span.style.scale 8)
            (string.format "Default perspective LOD should use scale 8 (got %s)" span.style.scale))
    (set surface.projection (glm.perspective (/ math.pi 6) 1.0 1.0 10000.0))
    (set surface.projection-version (+ (or surface.projection-version 0) 1))
    (labels:update points [node] nil)
    (assert (= span.style.scale 5)
            (string.format "Projection change should promote perspective LOD to scale 5 (got %s)"
                           span.style.scale))
    (labels:drop-all)
    (surface:drop)
    (camera:drop))

(table.insert tests {:name "GraphView labels create spans with defaults" :fn labels-create-span-with-defaults})
(table.insert tests {:name "GraphView labels move and drop reassigned spans" :fn labels-move-reassigns-span})
(table.insert tests {:name "GraphView labels update when camera moves without debounce signal"
                     :fn labels-update-when-camera-moves-without-debounced-signal})
(table.insert tests {:name "GraphView labels update when orthographic surface scale changes"
                     :fn labels-update-when-orthographic-surface-scale-changes})
(table.insert tests {:name "GraphView labels update when perspective surface camera moves a small distance"
                     :fn labels-update-when-perspective-surface-camera-moves-small-distance})
(table.insert tests {:name "GraphView labels update when perspective projection changes"
                     :fn labels-update-when-perspective-projection-changes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-labels"
                       :tests tests})))

{:name "graph-view-labels"
 :tests tests
 :main main}
