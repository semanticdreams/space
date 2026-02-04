(local glm (require :glm))
(local {: Layout : LayoutRoot} (require :layout))
(local BuildContext (require :build-context))
(local Rectangle (require :rectangle))
(local MathUtils (require :math-utils))

(local tests [])

(local approx (. MathUtils :approx))

(fn layout-hierarchy []
  (local root (LayoutRoot))
  (local l2 (Layout {:name "l2"}))
  (local l1 (Layout {:name "l1" :children [l2]}))
  (assert (= l1.name "l1"))
  (assert (= (length l1.children) 1))
  (assert (= (. l1.children 1) l2))
  (l1:clear-children)
  (assert (= (length l1.children) 0))
  (l1:add-child l2)
  (assert (= (. l1.children 1) l2))
  (assert (= l1.layout-dirty false))
  (l1:set-position (glm.vec3 10 0 0))
  (assert (= l1.layout-dirty true))
  (assert (= l1.position.x 10))
  (assert (= l1.position.y 0))
  (l1:set-root root)
  (assert (. root.layout-dirt.lookup l1))
  (root:update)
  (assert (not (. root.layout-dirt.lookup l1)))
  (l1:drop)
  (l2:drop))

(table.insert tests {:name "layout hierarchy and dirt tracking" :fn layout-hierarchy})

(fn layout-intersect-axis-aligned []
  (local layout (Layout {:name "hit-test"}))
  (set layout.size (glm.vec3 2 2 2))
  (set layout.position (glm.vec3 0 0 0))
  (set layout.rotation (glm.quat 1 0 0 0))
  (local ray {:origin (glm.vec3 1 1 -5) :direction (glm.vec3 0 0 1)})
  (let [(hit point distance) (layout:intersect ray)]
    (assert hit)
    (assert point)
    (assert (approx distance 5))
    (assert (approx point.x 1))
    (assert (approx point.y 1))
    (assert (approx point.z 0))))

(fn layout-intersect-miss []
  (local layout (Layout {:name "miss-test"}))
  (set layout.size (glm.vec3 1 1 1))
  (set layout.position (glm.vec3 10 0 0))
  (local ray {:origin (glm.vec3 0 0 -5) :direction (glm.vec3 0 0 1)})
  (let [(hit _point _distance) (layout:intersect ray)]
    (assert (not hit))))

(fn layout-intersect-rotated []
  (local layout (Layout {:name "rotated-hit"}))
  (set layout.size (glm.vec3 1 1 1))
  (set layout.position (glm.vec3 0 0 0))
  (set layout.rotation (glm.quat (math.rad 90) (glm.vec3 0 1 0)))
  (local ray {:origin (glm.vec3 -5 0.5 -0.5) :direction (glm.vec3 1 0 0)})
  (let [(hit point distance) (layout:intersect ray)]
    (assert hit)
    (assert point)
    (assert (approx distance 5))
    (assert (approx point.y 0.5))))

(fn layout-intersect-with-clip []
  (local layout (Layout {:name "clip-hit"}))
  (set layout.size (glm.vec3 4 4 4))
  (set layout.position (glm.vec3 0 0 0))
  (local clip {:bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 2 2 4)}})
  (set layout.clip-region clip)
  (local ray {:origin (glm.vec3 1 1 -5) :direction (glm.vec3 0 0 1)})
  (let [(hit point distance) (layout:intersect ray)]
    (assert hit)
    (assert point)
    (assert (approx distance 5))
    (assert (approx point.x 1))
    (assert (approx point.y 1))))

(fn layout-intersect-rejected-by-clip []
  (local layout (Layout {:name "clip-miss"}))
  (set layout.size (glm.vec3 4 4 4))
  (set layout.position (glm.vec3 0 0 0))
  (local clip {:bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 1 4 4)}})
  (set layout.clip-region clip)
  (local ray {:origin (glm.vec3 3 0 -5) :direction (glm.vec3 0 0 1)})
  (let [(hit _point _distance) (layout:intersect ray)]
    (assert (not hit))))

(table.insert tests {:name "layout intersect axis aligned" :fn layout-intersect-axis-aligned})
(table.insert tests {:name "layout intersect misses" :fn layout-intersect-miss})
(table.insert tests {:name "layout intersect rotated" :fn layout-intersect-rotated})
(table.insert tests {:name "layout intersect respects clip" :fn layout-intersect-with-clip})
(table.insert tests {:name "layout intersect rejects clipped hit" :fn layout-intersect-rejected-by-clip})

(fn layout-culls-when-outside-clip []
  (local clip {:bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 2 2 2)}})
  (var run-count 0)
  (local layout (Layout {:name "culled-layout"
                         :layouter (fn [_self]
                                     (set run-count (+ run-count 1)))}))
  (set layout.size (glm.vec3 1 1 1))
  (set layout.position (glm.vec3 3 0 0))
  (set layout.clip-region clip)
  (layout:layouter)
  (assert (= run-count 1) "Layouter should run once when newly culled")
  (assert layout.culled?)
  (assert (= layout.clip-visibility :outside))
  (set layout.position (glm.vec3 0.5 0.5 0.5))
  (layout:layouter)
  (assert (= run-count 2))
  (assert (not layout.culled?))
  (assert (or (= layout.clip-visibility :inside)
              (= layout.clip-visibility :partial))))

(fn layout-culling-propagates-to-children []
  (local clip {:bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 2 2 2)}})
  (var child-count 0)
  (local child (Layout {:name "culled-child"
                        :layouter (fn [_self]
                                    (set child-count (+ child-count 1)))}))
  (set child.size (glm.vec3 0.5 0.5 0.5))
  (var parent-count 0)
  (local parent (Layout {:name "culled-parent"
                         :children [child]
                         :layouter (fn [self]
                                     (set parent-count (+ parent-count 1))
                                     (each [_ c (ipairs self.children)]
                                       (c:layouter)))}))
  (set parent.clip-region clip)
  (set parent.size (glm.vec3 1 1 1))
  (set parent.position (glm.vec3 0 0 0))
  (parent:layouter)
  (assert (= parent-count 1))
  (assert (= child-count 1))
  (set parent.position (glm.vec3 3 0 0))
  (parent:layouter)
  (assert (= parent-count 2) "Parent layouter should run once when culling activates")
  (assert (= child-count 2))
  (assert parent.culled?)
  (assert child.parent-culled?)
  (child:layouter)
  (assert (= child-count 2) "Child layouter should be skipped while parent-culled")
  (assert (= child.clip-visibility :culled))
  (set parent.position (glm.vec3 0 0 0))
  (parent:layouter)
  (assert (= parent-count 3))
  (assert (= child-count 3))
  (assert (not child.parent-culled?))
  (child:layouter)
  (assert (= child-count 4)))

(fn layout-layouter-runs-on-cull-transitions []
  (local clip {:bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 1 1 1)}})
  (var run-count 0)
  (local layout (Layout {:layouter (fn [_self]
                                     (set run-count (+ run-count 1)))}))
  (set layout.size (glm.vec3 1 1 1))
  (set layout.clip-region clip)
  (layout:layouter)
  (assert (= run-count 1))
  (set layout.position (glm.vec3 2 0 0))
  (layout:layouter)
  (assert (= run-count 2))
  (layout:layouter)
  (assert (= run-count 2))
  (set layout.position (glm.vec3 0 0 0))
  (layout:layouter)
  (assert (= run-count 3))
  (layout:drop))

(fn layout-culling-hides-rectangle-widget []
  (local ctx (BuildContext {}))
  (local rect ((Rectangle {}) ctx))
  (local layout rect.layout)
  (local clip {:bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 1 1 1)}})
  (set layout.clip-region clip)
  (set layout.size (glm.vec3 1 1 0))
  (set layout.position (glm.vec3 0 0 0))
  (layout:layouter)
  (assert rect.render-visible?)
  (set layout.position (glm.vec3 5 0 0))
  (layout:layouter)
  (assert (not rect.render-visible?))
  (layout:layouter)
  (assert (not rect.render-visible?))
  (set layout.position (glm.vec3 0 0 0))
  (layout:layouter)
  (assert rect.render-visible?)
  (rect:drop))

(fn layout-root-records-stats []
  (local root (LayoutRoot))
  (local child (Layout {:name "stats-child"}))
  (child:set-root root)
  (child:mark-measure-dirty)
  (set app.engine.frame-id 42)
  (root:update)
  (local records root.stats.records)
  (assert (= (length records) 1))
  (local entry (. records 1))
  (assert (= entry.frame-id 42))
  (assert (= entry.measure-dirt 1))
  (assert (= entry.layout-dirt 1))
  (assert (>= entry.measure-delta 0))
  (assert (>= entry.layout-delta 0))
  (set root.stats.max-records 3)
  (for [i 1 5]
    (child:mark-measure-dirty)
    (set app.engine.frame-id (+ 42 i))
    (root:update))
  (assert (= (length root.stats.records) 3))
  (local oldest (. root.stats.records 1))
  (assert (= oldest.frame-id 45)))

(fn layout-root-buckets-measure-dirt-by-depth []
  (local root (LayoutRoot))
  (local calls [])
  (var child-calls 0)
  (local child (Layout {:name "bucket-child"
                        :measurer (fn [_]
                                    (set child-calls (+ child-calls 1)))}))
  (local parent (Layout {:name "bucket-parent"
                         :children [child]
                         :measurer (fn [_]
                                     (table.insert calls "parent")
                                     (each [_ c (ipairs (or _.children []))]
                                       (c:measurer)))}))

  (parent:set-root root)
  (parent:mark-measure-dirty)
  (child:mark-measure-dirty)

  (assert (= (length root.measure-dirt.depths) 2))
  (assert (= (. root.measure-dirt.depths 1) 0))
  (assert (= (. root.measure-dirt.depths 2) 1))

  (root:update)
  (assert (= (length calls) 1))
  (assert (= child-calls 1))

  (parent:drop)
  (child:drop))

(fn layout-root-removals-dont-skip-other-dirt []
  (local root (LayoutRoot))
  (var parent-a-calls 0)
  (var child-a-calls 0)
  (var parent-b-calls 0)
  (var child-b-calls 0)

  (local child-a (Layout {:name "child-a"
                          :measurer (fn [_]
                                      (set child-a-calls (+ child-a-calls 1)))}))
  (local parent-a (Layout {:name "parent-a"
                           :children [child-a]
                           :measurer (fn [self]
                                       (set parent-a-calls (+ parent-a-calls 1))
                                       (each [_ c (ipairs self.children)]
                                         (c:measurer)))}))

  (local child-b (Layout {:name "child-b"
                          :measurer (fn [_]
                                      (set child-b-calls (+ child-b-calls 1)))}))
  (local parent-b (Layout {:name "parent-b"
                           :children [child-b]
                           :measurer (fn [self]
                                       (set parent-b-calls (+ parent-b-calls 1))
                                       (each [_ c (ipairs self.children)]
                                         (c:measurer)))}))

  (parent-a:set-root root)
  (parent-b:set-root root)

  (child-a:mark-measure-dirty)
  (parent-b:mark-measure-dirty)

  (root:update)

  (assert (= parent-a-calls 1))
  (assert (= child-a-calls 1))
  (assert (= parent-b-calls 1))
  (assert (= child-b-calls 1))

  (parent-a:drop)
  (child-a:drop)
  (parent-b:drop)
  (child-b:drop))

(table.insert tests {:name "Layout culls subtree when outside clip" :fn layout-culls-when-outside-clip})
(table.insert tests {:name "Layout culling propagates to children" :fn layout-culling-propagates-to-children})
(table.insert tests {:name "Layout layouter runs on cull transitions" :fn layout-layouter-runs-on-cull-transitions})
(table.insert tests {:name "Rectangle hides renderer when culled" :fn layout-culling-hides-rectangle-widget})
(table.insert tests {:name "LayoutRoot tracks stats with retention" :fn layout-root-records-stats})
(table.insert tests {:name "LayoutRoot processes shallow measure dirt first" :fn layout-root-buckets-measure-dirt-by-depth})
(table.insert tests {:name "LayoutRoot keeps processing other dirty nodes when removing" :fn layout-root-removals-dont-skip-other-dirt})

(fn layout-tracks-depth-when-rooted []
  (local root (LayoutRoot))
  (local grandchild (Layout {:name "grandchild"}))
  (local child (Layout {:name "child" :children [grandchild]}))
  (local parent (Layout {:name "parent" :children [child]}))

  (assert (not parent.depth))
  (assert (not child.depth))
  (assert (not grandchild.depth))

  (parent:set-root root)
  (assert (= parent.depth 0))
  (assert (= child.depth 1))
  (assert (= grandchild.depth 2))

  (parent:remove-child 1)
  (assert (not child.depth))
  (assert (not grandchild.depth))
  (assert (not child.root))
  (assert (not grandchild.root))

  (parent:add-child child)
  (assert (= child.depth 1))
  (assert (= grandchild.depth 2))

  (parent:set-root nil)
  (assert (not parent.depth))
  (assert (not child.depth))
  (assert (not grandchild.depth))

  (parent:drop)
  (child:drop)
  (grandchild:drop))

(table.insert tests {:name "Layout tracks depth when rooted" :fn layout-tracks-depth-when-rooted})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "layout"
                       :tests tests})))

{:name "layout"
 :tests tests
 :main main}
