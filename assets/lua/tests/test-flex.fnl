(local glm (require :glm))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local {: Flex : FlexChild} (require :flex))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-test-child [measure]
  (local state {:measure-calls 0
                :layouter-calls 0
                :dropped false
                :last-size nil
                :last-position nil
                :last-rotation nil})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "test-flex-child"
               :measurer (fn [self]
                           (set state.measure-calls (+ state.measure-calls 1))
                           (set self.measure measure))
               :layouter (fn [self]
                           (set state.layouter-calls (+ state.layouter-calls 1))
                           (set state.last-size self.size)
                           (set state.last-position self.position)
                           (set state.last-rotation self.rotation))}))
    (local child {:layout layout})
    (set child.drop (fn [_self]
                      (set state.dropped true)))
    (set state.layout layout)
    child)
  {:builder builder :state state})

(fn flex-measurer-respects-axis-and-spacing []
  (local child-a (make-test-child (glm.vec3 1 2 3)))
  (local child-b (make-test-child (glm.vec3 2 4 1)))
  (local flex ((Flex {:axis "y"
                      :yspacing 2.0
                      :children [(FlexChild child-a.builder 0)
                                 (FlexChild child-b.builder 0)]}) {}))
  (flex.layout:measurer)
  (assert (= flex.layout.measure.x 2))
  (assert (= flex.layout.measure.y 8))
  (assert (= flex.layout.measure.z 3))
  (flex:drop))

(fn flex-layouter-distributes-flex-space []
  (local child-a (make-test-child (glm.vec3 2 2 2)))
  (local child-b (make-test-child (glm.vec3 1 6 2)))
  (local child-c (make-test-child (glm.vec3 1 3 4)))
  (local flex ((Flex {:axis "x"
                      :spacing 1.0
                      :yalign :largest
                      :zalign :center
                      :children [(FlexChild child-a.builder 0)
                                 (FlexChild child-b.builder 1)
                                 (FlexChild child-c.builder 2)]}) {}))
  (flex.layout:measurer)
  (set flex.layout.size (glm.vec3 12 10 6))
  (set flex.layout.position (glm.vec3 0 0 0))
  (set flex.layout.rotation (glm.quat 1 0 0 0))
  (flex.layout:layouter)

  (assert (= child-a.state.last-size.x 2))
  (assert (= child-a.state.last-size.y 6))
  (assert (= child-a.state.last-size.z 2))
  (assert (= child-a.state.last-position.x 0))
  (assert (= child-a.state.last-position.y 0))
  (assert (= child-a.state.last-position.z 2))

  (assert (approx child-b.state.last-size.x (/ 8 3)))
  (assert (= child-b.state.last-size.y 6))
  (assert (= child-b.state.last-size.z 2))
  (assert (approx child-b.state.last-position.x 3))
  (assert (= child-b.state.last-position.y 0))
  (assert (= child-b.state.last-position.z 2))

  (assert (approx child-c.state.last-size.x (* 2 (/ 8 3))))
  (assert (= child-c.state.last-size.y 6))
  (assert (= child-c.state.last-size.z 4))
  (assert (approx child-c.state.last-position.x (+ 3 (/ 8 3) 1)))
  (assert (= child-c.state.last-position.y 0))
  (assert (= child-c.state.last-position.z 1))

  (flex:drop))

(fn flex-stretch-align-stretches-cross-axes []
  (local child-a (make-test-child (glm.vec3 1 2 3)))
  (local child-b (make-test-child (glm.vec3 2 1 1)))
  (local flex ((Flex {:axis :x
                      :spacing 0
                      :yalign :stretch
                      :zalign :stretch
                      :children [(FlexChild child-a.builder 0)
                                 (FlexChild child-b.builder 1)]}) {}))
  (flex.layout:measurer)
  (set flex.layout.size (glm.vec3 8 5 7))
  (set flex.layout.position (glm.vec3 0 0 0))
  (set flex.layout.rotation (glm.quat 1 0 0 0))
  (flex.layout:layouter)

  (assert (= child-a.state.last-size.y 5))
  (assert (= child-a.state.last-size.z 7))
  (assert (= child-b.state.last-size.y 5))
  (assert (= child-b.state.last-size.z 7))

  (flex:drop))

(fn flex-respects-reverse-and-cross-alignments []
  (local child-a (make-test-child (glm.vec3 1 1 1)))
  (local child-b (make-test-child (glm.vec3 1 1 1)))
  (local flex ((Flex {:axis :z
                      :zspacing 0.5
                      :reverse true
                      :xalign :end
                      :yalign :center
                      :children [(FlexChild child-a.builder 0)
                                 (FlexChild child-b.builder 1)]}) {}))
  (flex.layout:measurer)
  (set flex.layout.size (glm.vec3 4 6 5))
  (set flex.layout.position (glm.vec3 1 2 3))
  (set flex.layout.rotation (glm.quat 1 0 0 0))
  (flex.layout:layouter)

  (assert (= child-a.state.last-size.z 1))
  (assert (= child-b.state.last-size.z 3.5))
  (assert (= child-a.state.last-size.x 1))
  (assert (= child-b.state.last-size.x 1))

  (assert (approx child-a.state.last-position.z (+ 3 4)))
  (assert (approx child-b.state.last-position.z 3))
  (assert (= child-a.state.last-position.x (+ 1 (- 4 1))))
  (assert (= child-b.state.last-position.x (+ 1 (- 4 1))))
  (assert (= child-a.state.last-position.y (+ 2 (/ (- 6 1) 2))))
  (assert (= child-b.state.last-position.y (+ 2 (/ (- 6 1) 2))))

  (flex:drop))

(fn flex-propagates-rotation-to-offsets []
  (local child-a (make-test-child (glm.vec3 1 1 1)))
  (local child-b (make-test-child (glm.vec3 1 1 1)))
  (local flex ((Flex {:axis :x
                      :spacing 0
                      :children [(FlexChild child-a.builder 0)
                                 (FlexChild child-b.builder 0)]}) {}))
  (flex.layout:measurer)
  (set flex.layout.size (glm.vec3 4 1 1))
  (set flex.layout.position (glm.vec3 0 0 0))
  (local rotation (glm.quat (math.rad 90) (glm.vec3 0 0 1)))
  (set flex.layout.rotation rotation)
  (flex.layout:layouter)

  (local expected-offset (rotation:rotate (glm.vec3 1 0 0)))
  (assert (approx child-b.state.last-position.x expected-offset.x))
  (assert (approx child-b.state.last-position.y expected-offset.y))
  (assert (approx child-b.state.last-position.z expected-offset.z))
  (assert (approx child-b.state.last-rotation.w rotation.w))
  (assert (approx child-b.state.last-rotation.x rotation.x))
  (assert (approx child-b.state.last-rotation.y rotation.y))
  (assert (approx child-b.state.last-rotation.z rotation.z))

  (flex:drop))

(fn flex-clamps-children-when-constrained []
  (local child-a (make-test-child (glm.vec3 5 1 0)))
  (local child-b (make-test-child (glm.vec3 3 1 0)))
  (local flex ((Flex {:axis :x
                      :spacing 0.5
                      :children [(FlexChild child-a.builder 0)
                                 (FlexChild child-b.builder 0)]}) {}))
  (flex.layout:measurer)
  (set flex.layout.size (glm.vec3 4 2 0))
  (set flex.layout.position (glm.vec3 0 0 0))
  (flex.layout:layouter)

  (local total-spacing 0.5)
  (local available (- flex.layout.size.x total-spacing))
  (local sum-sizes (+ child-a.state.last-size.x child-b.state.last-size.x))
  (assert (approx sum-sizes available))
  (assert (<= (+ child-b.state.last-position.x child-b.state.last-size.x) (+ flex.layout.position.x flex.layout.size.x 1e-4)))

  (flex:drop))

(fn flex-prefers-shrinking-flex-children []
  (local fixed (make-test-child (glm.vec3 3 1 1)))
  (local flex-child (make-test-child (glm.vec3 5 1 1)))
  (local flex ((Flex {:axis :x
                      :spacing 0
                      :children [(FlexChild fixed.builder 0)
                                 (FlexChild flex-child.builder 1)]}) {}))
  (flex.layout:measurer)
  (set flex.layout.size (glm.vec3 5 1 1))
  (set flex.layout.position (glm.vec3 0 0 0))
  (set flex.layout.rotation (glm.quat 1 0 0 0))
  (flex.layout:layouter)

  (assert (approx fixed.state.last-size.x 3))
  (assert (approx flex-child.state.last-size.x 2))

  (flex:drop))

(table.insert tests {:name "Flex measurer respects axis and spacing" :fn flex-measurer-respects-axis-and-spacing})
(table.insert tests {:name "Flex layouter distributes flex space" :fn flex-layouter-distributes-flex-space})
(table.insert tests {:name "Flex stretch alignment stretches cross axes" :fn flex-stretch-align-stretches-cross-axes})
(table.insert tests {:name "Flex respects reverse and cross-axis alignment" :fn flex-respects-reverse-and-cross-alignments})
(table.insert tests {:name "Flex propagates rotation to offsets" :fn flex-propagates-rotation-to-offsets})
(table.insert tests {:name "Flex clamps child sizes when engine is constrained" :fn flex-clamps-children-when-constrained})
(table.insert tests {:name "Flex prefers shrinking flex children" :fn flex-prefers-shrinking-flex-children})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "flex"
                       :tests tests})))

{:name "flex"
 :tests tests
 :main main}
