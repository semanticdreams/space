(local glm (require :glm))
(local Sized (require :sized))
(local {: Layout} (require :layout))

(local tests [])

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
        (Layout {:name "test-child"
                 :measurer (fn [self]
                             (set state.measure-called true)
                             (set self.measure (glm.vec3 1 2 3)))
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

(fn sized-measurer-applies-fixed-size []
  (local child (make-test-child))
  (local requested-size (glm.vec3 4 5 6))
  (local sized ((Sized {:size requested-size :child child.builder}) {}))
  (assert (= (length sized.layout.children) 1))
  (assert (= (. sized.layout.children 1) sized.child.layout))
  (sized.layout:measurer)
  (assert child.state.measure-called)
  (assert (= sized.layout.measure.x requested-size.x))
  (assert (= sized.layout.measure.y requested-size.y))
  (assert (= sized.layout.measure.z requested-size.z))
  (sized:drop))

(fn sized-layouter-propagates-transform []
  (local child (make-test-child))
  (local sized ((Sized {:size (glm.vec3 1 1 1) :child child.builder}) {}))
  (local parent-size (glm.vec3 7 8 9))
  (local parent-position (glm.vec3 2 4 6))
  (local parent-rotation (glm.quat 1 0.25 0.5 0.75))
  (set sized.layout.size parent-size)
  (set sized.layout.position parent-position)
  (set sized.layout.rotation parent-rotation)
  (sized.layout:layouter)
  (assert child.state.layouter-called)
  (assert (= child.state.received-size.x parent-size.x))
  (assert (= child.state.received-size.y parent-size.y))
  (assert (= child.state.received-size.z parent-size.z))
  (assert (= child.state.received-position.x parent-position.x))
  (assert (= child.state.received-position.y parent-position.y))
  (assert (= child.state.received-position.z parent-position.z))
  (assert (= child.state.received-rotation.w parent-rotation.w))
  (assert (= child.state.received-rotation.x parent-rotation.x))
  (assert (= child.state.received-rotation.y parent-rotation.y))
  (assert (= child.state.received-rotation.z parent-rotation.z))
  (sized:drop))

(fn sized-drop-releases-child []
  (local child (make-test-child))
  (local sized ((Sized {:size (glm.vec3 1 1 1) :child child.builder}) {}))
  (sized:drop)
  (assert child.state.drop-called)
  (assert (= (length sized.layout.children) 0))
  (assert (= sized.child.layout.parent nil)))

(table.insert tests {:name "Sized measurer uses fixed size" :fn sized-measurer-applies-fixed-size})
(table.insert tests {:name "Sized layouter forwards transforms" :fn sized-layouter-propagates-transform})
(table.insert tests {:name "Sized drop releases child" :fn sized-drop-releases-child})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sized"
                       :tests tests})))

{:name "sized"
 :tests tests
 :main main}
