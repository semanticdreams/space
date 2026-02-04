(local glm (require :glm))
(local ScrollArea (require :scroll-area))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec3-approx= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn bounds-within? [bounds parent]
  (local pos (or (and bounds bounds.position) (glm.vec3 0 0 0)))
  (local size (or (and bounds bounds.size) (glm.vec3 0 0 0)))
  (local parent-pos (or (and parent parent.position) (glm.vec3 0 0 0)))
  (local parent-size (or (and parent parent.size) (glm.vec3 0 0 0)))
  (local epsilon 1e-5)
  (and (>= pos.x (- parent-pos.x epsilon))
       (>= pos.y (- parent-pos.y epsilon))
       (>= pos.z (- parent-pos.z epsilon))
       (<= (+ pos.x size.x) (+ parent-pos.x parent-size.x epsilon))
       (<= (+ pos.y size.y) (+ parent-pos.y parent-size.y epsilon))
       (<= (+ pos.z size.z) (+ parent-pos.z parent-size.z epsilon))))

(fn make-test-child []
  (local state {:last-position nil
                :last-rotation nil
                :last-clip-region nil
                :last-size nil})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "scroll-area-child"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 6 4 0)))
               :layouter (fn [self]
                           (set state.last-position self.position)
                           (set state.last-rotation self.rotation)
                           (set state.last-clip-region self.clip-region)
                           (set state.last-size self.size))}))
    (local child {:layout layout :state state})
    (set child.drop (fn [_self]))
    child)
  {:builder builder :state state})

(fn scroll-area-assigns-clip-region []
  (local child (make-test-child))
  (local scroll ((ScrollArea {:child child.builder}) {}))
  (scroll.layout:measurer)
  (set scroll.layout.size (glm.vec3 5 3 0))
  (set scroll.layout.position (glm.vec3 2 4 6))
  (set scroll.layout.rotation (glm.quat 1 0 0 0))
  (scroll.layout:layouter)
  (local clip scroll.layout.clip-region)
  (assert clip "ScrollArea layout should produce a clip region")
  (assert (= clip child.state.last-clip-region))
  (assert (= clip.layout scroll.layout))
  (assert (vec3-approx= clip.bounds.size scroll.layout.size))
  (assert (vec3-approx= clip.bounds.position scroll.layout.position))
  (scroll:drop))

(fn scroll-area-scroll-offset-adjusts-child []
  (local child (make-test-child))
  (local scroll ((ScrollArea {:child child.builder}) {}))
  (scroll.layout:measurer)
  (set scroll.layout.size (glm.vec3 8 8 0))
  (set scroll.layout.position (glm.vec3 4 5 6))
  (set scroll.layout.rotation (glm.quat 1 0 0 0))
  (scroll.layout:layouter)
  (assert (vec3-approx= child.state.last-position scroll.layout.position))
  (local clip scroll.layout.clip-region)
  (scroll:set-scroll-offset (glm.vec3 1 2 0))
  (scroll.layout:layouter)
  (assert (approx child.state.last-position.x (- scroll.layout.position.x 1)))
  (assert (approx child.state.last-position.y (- scroll.layout.position.y 2)))
  (assert (approx child.state.last-position.z scroll.layout.position.z))
  (scroll.layout:layouter)
  (assert (= clip scroll.layout.clip-region)
          "Clip region should be stable between layouts")
  (scroll:drop))

(fn scroll-area-root-clip-parent-remains-nil []
  (local child (make-test-child))
  (local scroll ((ScrollArea {:child child.builder}) {}))
  (scroll.layout:measurer)
  (set scroll.layout.size (glm.vec3 4 4 0))
  (set scroll.layout.position (glm.vec3 0 0 0))
  (scroll.layout:layouter)
  (local clip scroll.layout.clip-region)
  (assert clip)
  (assert (= clip.parent nil))
  (scroll.layout:layouter)
  (assert (= clip scroll.layout.clip-region))
  (assert (= clip.parent nil))
  (scroll:drop))

(fn scroll-area-expands-child-width-to-viewport []
  (local child (make-test-child))
  (local scroll ((ScrollArea {:child child.builder}) {}))
  (scroll.layout:measurer)
  (set scroll.layout.size (glm.vec3 10 2 0))
  (scroll.layout:layouter)
  (assert (approx child.state.last-size.x scroll.layout.size.x)
          "Child width should stretch to the viewport width when larger")
  (assert (approx child.state.last-size.y 4)
          "Child height should stay measured to preserve scrollable content")
  (scroll:drop))

(fn scroll-area-clamps-to-parent-clip []
  (local child (make-test-child))
  (local scroll ((ScrollArea {:child child.builder}) {}))
  (scroll.layout:measurer)
  (set scroll.layout.size (glm.vec3 10 8 0))
  (set scroll.layout.position (glm.vec3 0 0 0))
  (set scroll.layout.rotation (glm.quat 1 0 0 0))
  (local parent-bounds {:position (glm.vec3 1 2 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 3 2 0)})
  (set scroll.layout.clip-region {:bounds parent-bounds})
  (scroll.layout:layouter)
  (local clip scroll.layout.clip-region)
  (assert clip "ScrollArea should preserve clip region")
  (assert (vec3-approx= clip.bounds.size parent-bounds.size))
  (assert (vec3-approx= clip.bounds.position parent-bounds.position))
  (scroll:drop))

(fn scroll-area-clamp-respects-rotated-child []
  (local child (make-test-child))
  (local scroll ((ScrollArea {:child child.builder}) {}))
  (scroll.layout:measurer)
  (set scroll.layout.size (glm.vec3 6 2 0))
  (set scroll.layout.position (glm.vec3 1 1 0))
  (set scroll.layout.rotation (glm.quat (math.rad 45) (glm.vec3 0 0 1)))
  (local parent-bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 4 4 0)})
  (set scroll.layout.clip-region {:bounds parent-bounds})
  (scroll.layout:layouter)
  (local clip scroll.layout.clip-region)
  (assert clip "ScrollArea should clamp rotated child clip")
  (assert (bounds-within? clip.bounds parent-bounds))
  (scroll:drop))

(table.insert tests {:name "ScrollArea assigns a clip region" :fn scroll-area-assigns-clip-region})
(table.insert tests {:name "ScrollArea scroll offset repositions child" :fn scroll-area-scroll-offset-adjusts-child})
(table.insert tests {:name "ScrollArea root clip parent remains nil" :fn scroll-area-root-clip-parent-remains-nil})
(table.insert tests {:name "ScrollArea expands child width to viewport" :fn scroll-area-expands-child-width-to-viewport})
(table.insert tests {:name "ScrollArea clamps clip to parent bounds" :fn scroll-area-clamps-to-parent-clip})
(table.insert tests {:name "ScrollArea clamp handles rotated child" :fn scroll-area-clamp-respects-rotated-child})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scroll-area"
                       :tests tests})))

{:name "scroll-area"
 :tests tests
 :main main}
