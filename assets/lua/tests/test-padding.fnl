(local glm (require :glm))
(local Padding (require :padding))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-test-child []
  (local state {:measure-called false
                :layouter-called false
                :drop-called false
                :received-size nil
                :received-position nil
                :received-rotation nil})
  (local builder
    (fn [_ctx]
      (local layout
        (Layout {:name "test-padding-child"
                 :measurer (fn [self]
                             (set state.measure-called true)
                             (set self.measure (glm.vec3 2 2 2)))
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

(fn padding-propagates-rotation []
  (local child (make-test-child))
  (local padding ((Padding {:edge-insets [1 0 0 0 0 0]
                            :child child.builder}) {}))
  (padding.layout:measurer)
  (set padding.layout.size (glm.vec3 10 5 3))
  (set padding.layout.position (glm.vec3 5 6 7))
  (local rotation (glm.quat (math.rad 45) (glm.vec3 0 0 1)))
  (set padding.layout.rotation rotation)
  (padding.layout:layouter)

  (assert child.state.layouter-called)
  (assert (= child.state.received-size.x 9))
  (assert (= child.state.received-size.y 5))
  (assert (= child.state.received-size.z 3))

  (local expected-offset (rotation:rotate (glm.vec3 1 0 0)))
  (local expected-position (+ padding.layout.position expected-offset))
  (assert (approx child.state.received-position.x expected-position.x))
  (assert (approx child.state.received-position.y expected-position.y))
  (assert (approx child.state.received-position.z expected-position.z))

  (assert (approx child.state.received-rotation.w rotation.w))
  (assert (approx child.state.received-rotation.x rotation.x))
  (assert (approx child.state.received-rotation.y rotation.y))
  (assert (approx child.state.received-rotation.z rotation.z))

  (padding:drop)
  (assert child.state.drop-called))

(table.insert tests {:name "Padding propagates rotation and offsets" :fn padding-propagates-rotation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "padding"
                       :tests tests})))

{:name "padding"
 :tests tests
 :main main}
