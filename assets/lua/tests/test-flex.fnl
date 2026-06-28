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

(fn make-constrained-child [measure clamp-axis]
  "Creates a child that reports `measure` and clamps its constrained result on
`clamp-axis` (1=X, 2=Y, 3=Z). Defaults to axis 1 (X) for backward compat."
  (local axis (or clamp-axis 1))
  (local state {:measure-calls 0
                :layouter-calls 0
                :dropped false
                :last-size nil
                :last-position nil
                :last-rotation nil
                :last-constraint nil})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "test-flex-constrained-child"
               :measurer (fn [self]
                           (set state.measure-calls (+ state.measure-calls 1))
                           (set self.measure measure))
               :constrained-measurer (fn [self constraints]
                                       (set state.measure-calls (+ state.measure-calls 1))
                                       (set state.last-constraint constraints)
                                       (local max-axis (and constraints constraints.max (. constraints.max axis)))
                                       (if max-axis
                                           (let [clamped (math.min (. measure axis) max-axis)
                                                 result (glm.vec3 measure.x measure.y measure.z)]
                                             (tset result axis clamped)
                                             (set self.measure result))
                                           (set self.measure measure)))
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

(fn flex-keeps-non-flex-child-sizes-when-constrained []
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

  (assert (approx child-a.state.last-size.x 5))
  (assert (approx child-b.state.last-size.x 3))
  (assert (approx child-b.state.last-position.x 5.5))
  (assert (> (+ child-b.state.last-position.x child-b.state.last-size.x)
             (+ flex.layout.position.x flex.layout.size.x)))

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

(fn flex-constrained-measure-respects-fixed-siblings []
  (local fixed (make-constrained-child (glm.vec3 4 1 1)))
  (local flex-a (make-constrained-child (glm.vec3 5 1 1)))
  (local flex-b (make-constrained-child (glm.vec3 5 1 1)))
  (local flex ((Flex {:axis :x
                      :spacing 0.5
                      :children [(FlexChild fixed.builder 0)
                                 (FlexChild flex-a.builder 1)
                                 (FlexChild flex-b.builder 1)]}) {}))
  (flex.layout:measure-constrained {:max (glm.vec3 10 5 0)})
  ;; Fixed child gets full constraint width, so its measure stays at 4
  (assert (approx fixed.state.layout.measure.x 4)
          (.. "Fixed child should get full width, got " (tostring fixed.state.layout.measure.x)))
  ;; Flex children share remaining: remaining = 10 - 4 - 2*0.5 = 5
  ;; Each flex child weight 1 out of 2 total: share = 5 * 1/2 = 2.5
  (assert (approx flex-a.state.layout.measure.x 2.5)
          (.. "Flex child a should get ~2.5 width, got " (tostring flex-a.state.layout.measure.x)))
  (assert (approx flex-b.state.layout.measure.x 2.5)
          (.. "Flex child b should get ~2.5 width, got " (tostring flex-b.state.layout.measure.x)))
  (flex:drop))

(fn flex-constrained-measure-falls-back-when-no-constraint []
  (local child-a (make-constrained-child (glm.vec3 2 3 1)))
  (local child-b (make-constrained-child (glm.vec3 4 2 1)))
  (local flex ((Flex {:axis :x
                      :spacing 1
                      :children [(FlexChild child-a.builder 0)
                                 (FlexChild child-b.builder 1)]}) {}))
  ;; Pass nil for constraints: flex falls back to unconstrained child measurement
  (flex.layout:measure-constrained nil)
  (assert (approx flex.layout.measure.x 7)
          (.. "Nil constraint should sum unconstrained child measures: got " (tostring flex.layout.measure.x)))
  (assert (approx child-a.state.layout.measure.x 2)
          "Nil constraint: child a should keep natural width")
  (assert (approx child-b.state.layout.measure.x 4)
          "Nil constraint: child b should keep natural width")
  (flex:drop))

(fn flex-constrained-measure-uses-axis-not-hardcoded-x []
  (local fixed (make-constrained-child (glm.vec3 2 4 1) 2))
  (local flex-c (make-constrained-child (glm.vec3 2 6 1) 2))
  (local flex ((Flex {:axis :y
                      :spacing 0.5
                      :children [(FlexChild fixed.builder 0)
                                 (FlexChild flex-c.builder 1)]}) {}))
  (flex.layout:measure-constrained {:max (glm.vec3 10 12 5)})
  ;; Fixed child gets full constraint, keeps natural Y = 4
  (assert (approx fixed.state.layout.measure.y 4)
          (.. "Fixed child Y should stay 4, got " (tostring fixed.state.layout.measure.y)))
  ;; Flex child share: remaining = 12 - 4 - 0.5 = 7.5, weight=1 sum=1 -> Y share = 7.5
  ;; The helper now clamps axis 2 (Y), so measure.y = min(6, 7.5) = 6
  (assert (approx flex-c.state.layout.measure.y 6)
          (.. "Flex child Y should be clamped to natural 6, got " (tostring flex-c.state.layout.measure.y)))
  ;; Flex layout total Y = 4 + 6 + 0.5 = 10.5
  (assert (approx flex.layout.measure.y 10.5)
          (.. "Flex Y should be 10.5 (4 + 6 + 0.5), got " (tostring flex.layout.measure.y)))
  ;; Cross-axis (X) should NOT have been applied as primary axis
  (assert (approx flex.layout.measure.x 2)
          (.. "Flex X (cross axis) should be max of children' X = 2, got " (tostring flex.layout.measure.x)))
  (flex:drop))

(table.insert tests {:name "Flex measurer respects axis and spacing" :fn flex-measurer-respects-axis-and-spacing})
(table.insert tests {:name "Flex layouter distributes flex space" :fn flex-layouter-distributes-flex-space})
(table.insert tests {:name "Flex stretch alignment stretches cross axes" :fn flex-stretch-align-stretches-cross-axes})
(table.insert tests {:name "Flex respects reverse and cross-axis alignment" :fn flex-respects-reverse-and-cross-alignments})
(table.insert tests {:name "Flex propagates rotation to offsets" :fn flex-propagates-rotation-to-offsets})
(table.insert tests {:name "Flex keeps non-flex child sizes when engine is constrained" :fn flex-keeps-non-flex-child-sizes-when-constrained})
(table.insert tests {:name "Flex prefers shrinking flex children" :fn flex-prefers-shrinking-flex-children})
(table.insert tests {:name "Flex constrained measure respects fixed siblings" :fn flex-constrained-measure-respects-fixed-siblings})
(table.insert tests {:name "Flex constrained measure falls back when no axis constraint" :fn flex-constrained-measure-falls-back-when-no-constraint})
(table.insert tests {:name "Flex constrained measure uses axis not hardcoded X" :fn flex-constrained-measure-uses-axis-not-hardcoded-x})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "flex"
                       :tests tests})))

{:name "flex"
 :tests tests
 :main main}
