(local glm (require :glm))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local {: Grid} (require :grid))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-test-child [measure]
  (local state {:measure-calls 0
                :layouter-calls 0
                :last-size nil
                :last-position nil
                :dropped false})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "grid-child"
               :measurer (fn [self]
                           (set state.measure-calls (+ state.measure-calls 1))
                           (set self.measure measure))
               :layouter (fn [self]
                           (set state.layouter-calls (+ state.layouter-calls 1))
                           (set state.last-size self.size)
                           (set state.last-position self.position))}))
    (local child {:layout layout})
    (set child.drop (fn [_self]
                      (set state.dropped true)))
    (set state.layout layout)
    child)
  {:builder builder :state state})

(fn grid-measurer-uses-rows-columns-and-spacing []
  (local child-a (make-test-child (glm.vec3 1 2 3)))
  (local child-b (make-test-child (glm.vec3 3 1 1)))
  (local grid ((Grid {:rows 2
                      :columns 3
                      :xspacing 1.0
                      :yspacing 0.25
                      :children [{:widget child-a.builder}
                                 {:widget child-b.builder}]}) {}))
  (grid.layout:measurer)
  (assert (approx grid.layout.measure.x 11.0))
  (assert (approx grid.layout.measure.y 4.25))
  (assert (= grid.layout.measure.z 3))
  (grid:drop))

(fn grid-layouter-fills-column-major []
  (local child-a (make-test-child (glm.vec3 1 1 0)))
  (local child-b (make-test-child (glm.vec3 1 1 0)))
  (local child-c (make-test-child (glm.vec3 1 1 0)))
  (local grid ((Grid {:rows 2
                      :columns 2
                      :xspacing 0
                      :yspacing 0
                      :children [{:widget child-a.builder}
                                 {:widget child-b.builder}
                                 {:widget child-c.builder}]}) {}))
  (grid.layout:measurer)
  (set grid.layout.size (glm.vec3 4 4 0))
  (set grid.layout.position (glm.vec3 0 0 0))
  (set grid.layout.rotation (glm.quat 1 0 0 0))
  (grid.layout:layouter)

  (assert (= child-a.state.last-size.x 2))
  (assert (= child-a.state.last-size.y 2))
  (assert (= child-a.state.last-position.x 0))
  (assert (= child-a.state.last-position.y 2))
  (assert (= child-b.state.last-position.x 0))
  (assert (= child-b.state.last-position.y 0))
  (assert (= child-c.state.last-position.x 2))
  (assert (= child-c.state.last-position.y 2))
  (grid:drop))

(fn grid-layouter-rotates-offsets []
  (local child-a (make-test-child (glm.vec3 1 1 0)))
  (local child-b (make-test-child (glm.vec3 1 1 0)))
  (local rotation (glm.quat (math.rad 90) (glm.vec3 0 0 1)))
  (local grid ((Grid {:rows 1
                      :columns 2
                      :xspacing 0
                      :yspacing 0
                      :children [{:widget child-a.builder}
                                 {:widget child-b.builder}]}) {}))
  (grid.layout:measurer)
  (set grid.layout.size (glm.vec3 4 2 0))
  (set grid.layout.position (glm.vec3 0 0 0))
  (set grid.layout.rotation rotation)
  (grid.layout:layouter)

  (assert (approx child-b.state.last-position.x 0))
  (assert (approx child-b.state.last-position.y 2))
  (grid:drop))

(fn grid-tight-measures-columns []
  (local child-a (make-test-child (glm.vec3 1 2 0)))
  (local child-b (make-test-child (glm.vec3 3 2 0)))
  (local grid ((Grid {:rows 1
                      :columns 2
                      :xmode :tight
                      :xspacing 0.5
                      :yspacing 0.1
                      :children [{:widget child-a.builder}
                                 {:widget child-b.builder}]}) {}))
  (grid.layout:measurer)
  (assert (approx grid.layout.measure.x 4.5))
  (assert (approx grid.layout.measure.y 2))
  (grid:drop))

(fn grid-column-flex-distributes-space []
  (local child-a (make-test-child (glm.vec3 1 1 0)))
  (local child-b (make-test-child (glm.vec3 3 1 0)))
  (local grid ((Grid {:rows 1
                      :columns 2
                      :xmode :tight
                      :xspacing 0.5
                      :column-specs [{:flex 0}
                                     {:flex 1}]
                      :children [{:widget child-a.builder}
                                 {:widget child-b.builder}]}) {}))
  (grid.layout:measurer)
  (set grid.layout.size (glm.vec3 10 2 0))
  (set grid.layout.position (glm.vec3 0 0 0))
  (set grid.layout.rotation (glm.quat 1 0 0 0))
  (grid.layout:layouter)
  (assert (approx child-a.state.last-size.x 1))
  (assert (approx child-b.state.last-size.x 8.5))
  (grid:drop))

(fn grid-aligns-top-left []
  (local child-a (make-test-child (glm.vec3 1 1 0)))
  (local grid ((Grid {:rows 1
                      :columns 1
                      :align-x :start
                      :align-y :end
                      :children [{:widget child-a.builder}]}) {}))
  (grid.layout:measurer)
  (set grid.layout.size (glm.vec3 4 4 0))
  (set grid.layout.position (glm.vec3 0 0 0))
  (set grid.layout.rotation (glm.quat 1 0 0 0))
  (grid.layout:layouter)
  (assert (approx child-a.state.last-position.x 0))
  (assert (approx child-a.state.last-position.y 3))
  (grid:drop))

(fn grid-cell-stretches-horizontally []
  (local child-a (make-test-child (glm.vec3 1 1 0)))
  (local grid ((Grid {:rows 1
                      :columns 1
                      :align-x :start
                      :align-y :start
                      :children [{:widget child-a.builder
                                  :align-x :stretch}]}) {}))
  (grid.layout:measurer)
  (set grid.layout.size (glm.vec3 5 2 0))
  (set grid.layout.position (glm.vec3 0 0 0))
  (set grid.layout.rotation (glm.quat 1 0 0 0))
  (grid.layout:layouter)
  (assert (approx child-a.state.last-size.x 5))
  (grid:drop))

(table.insert tests {:name "Grid measurer uses rows, columns, and spacing" :fn grid-measurer-uses-rows-columns-and-spacing})
(table.insert tests {:name "Grid layouter fills column-major" :fn grid-layouter-fills-column-major})
(table.insert tests {:name "Grid layouter rotates offsets" :fn grid-layouter-rotates-offsets})
(table.insert tests {:name "Grid tight mode measures columns" :fn grid-tight-measures-columns})
(table.insert tests {:name "Grid column flex distributes space" :fn grid-column-flex-distributes-space})
(table.insert tests {:name "Grid aligns top left" :fn grid-aligns-top-left})
(table.insert tests {:name "Grid cell stretches horizontally" :fn grid-cell-stretches-horizontally})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "grid"
                       :tests tests})))

{:name "grid"
 :tests tests
 :main main}
