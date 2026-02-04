(local glm (require :glm))
(local Stack (require :stack))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-test-child []
  (local state {:layouter-called false
                :last-position nil
                :last-rotation nil})
  (local builder
    (fn [_ctx]
      (local layout
        (Layout {:name "test-stack-child"
                 :measurer (fn [self]
                             (set self.measure (glm.vec3 1 1 1)))
                 :layouter (fn [self]
                             (set state.layouter-called true)
                             (set state.last-position self.position)
                             (set state.last-rotation self.rotation))}))
      (local child {:layout layout})
      (set child.drop (fn [_self]))
      child))
  {:state state :builder builder})

(fn stack-propagates-rotation []
  (local child-a (make-test-child))
  (local child-b (make-test-child))
  (local stack ((Stack {:children [child-a.builder child-b.builder]}) {}))
  (stack.layout:measurer)
  (set stack.layout.size (glm.vec3 2 2 2))
  (set stack.layout.position (glm.vec3 0 0 0))
  (local rotation (glm.quat (math.rad 90) (glm.vec3 0 1 0)))
  (set stack.layout.rotation rotation)
  (stack.layout:layouter)

  (assert (approx child-a.state.last-position.x stack.layout.position.x))
  (assert (approx child-a.state.last-position.y stack.layout.position.y))
  (assert (approx child-a.state.last-position.z stack.layout.position.z))
  (assert (approx child-b.state.last-position.x stack.layout.position.x))
  (assert (approx child-b.state.last-position.y stack.layout.position.y))
  (assert (approx child-b.state.last-position.z stack.layout.position.z))

  (assert (approx child-a.state.last-rotation.w rotation.w))
  (assert (approx child-a.state.last-rotation.x rotation.x))
  (assert (approx child-a.state.last-rotation.y rotation.y))
  (assert (approx child-a.state.last-rotation.z rotation.z))
  (assert (approx child-b.state.last-rotation.w rotation.w))
  (assert (approx child-b.state.last-rotation.x rotation.x))
  (assert (approx child-b.state.last-rotation.y rotation.y))
  (assert (approx child-b.state.last-rotation.z rotation.z))

  (local first-child (. stack.layout.children 1))
  (local second-child (. stack.layout.children 2))
  (assert (= first-child.depth-offset-index (+ stack.layout.depth-offset-index 1)))
  (assert (= second-child.depth-offset-index (+ stack.layout.depth-offset-index 2)))

  (stack:drop))

(table.insert tests {:name "Stack propagates rotation offsets" :fn stack-propagates-rotation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "stack"
                       :tests tests})))

{:name "stack"
 :tests tests
 :main main}
