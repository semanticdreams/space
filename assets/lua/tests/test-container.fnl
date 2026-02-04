(local glm (require :glm))
(local Container (require :container))
(local Positioned (require :positioned))
(local {: Layout} (require :layout))

(local tests [])

(fn make-test-child [measure]
  (local state {:measure-called false
                :layouter-called false
                :drop-called false
                :expected-measure measure
                :received-size nil
                :received-position nil
                :received-rotation nil})
  (local builder
    (fn [_ctx]
      (local layout
        (Layout {:name "test-child"
                 :measurer (fn [self]
                             (set state.measure-called true)
                             (set self.measure measure))
                 :layouter (fn [self]
                             (set state.layouter-called true)
                             (set state.received-size self.size)
                             (set state.received-position self.position)
                             (set state.received-rotation self.rotation))}))
      (local child {:layout layout})
      (set child.drop (fn [_self]
                        (set state.drop-called true)))
      child))
  {:state state :builder builder})

(fn container-layout-propagates-to-children []
  (local first (make-test-child (glm.vec3 2 3 4)))
  (local second (make-test-child (glm.vec3 5 1 2)))
  (local container ((Container {:children [first.builder second.builder]}) {}))
  (container.layout:measurer)
  (assert (= container.layout.measure.x 5))
  (assert (= container.layout.measure.y 3))
  (assert (= container.layout.measure.z 4))
  (set container.layout.position (glm.vec3 7 8 9))
  (container.layout:layouter)
  (each [_ child (ipairs [first second])]
    (assert child.state.layouter-called)
    (assert (= child.state.received-position.x 7))
    (assert (= child.state.received-position.y 8))
    (assert (= child.state.received-position.z 9))
    (assert (= child.state.received-size.x child.state.expected-measure.x))
    (assert (= child.state.received-size.y child.state.expected-measure.y))
    (assert (= child.state.received-size.z child.state.expected-measure.z)))
  (container:drop)
  (assert first.state.drop-called)
  (assert second.state.drop-called))

(fn positioned-applies-offset []
  (local child (make-test-child (glm.vec3 1 2 3)))
  (local offset (glm.vec3 4 5 6))
  (local positioned ((Positioned {:position offset :child child.builder}) {}))
  (positioned.layout:measurer)
  (set positioned.layout.position (glm.vec3 1 1 1))
  (positioned.layout:layouter)
  (assert child.state.layouter-called)
  (assert (= child.state.received-position.x (+ 1 offset.x)))
  (assert (= child.state.received-position.y (+ 1 offset.y)))
  (assert (= child.state.received-position.z (+ 1 offset.z)))
  (assert (= child.state.received-size.x 1))
  (assert (= child.state.received-size.y 2))
  (assert (= child.state.received-size.z 3))
  (positioned:drop)
  (assert child.state.drop-called))

(table.insert tests {:name "Container propagates transforms to children" :fn container-layout-propagates-to-children})
(table.insert tests {:name "Positioned offsets child layout" :fn positioned-applies-offset})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "container"
                       :tests tests})))

{:name "container"
 :tests tests
 :main main}
