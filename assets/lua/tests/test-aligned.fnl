(local glm (require :glm))
(local Aligned (require :aligned))
(local {: Layout} (require :layout))

(local tests [])

(fn make-test-child [measure]
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

(fn aligned-measurer-uses-child-measure []
  (local measure (glm.vec3 2 4 6))
  (local child (make-test-child measure))
  (local aligned ((Aligned {:child child.builder}) {}))
  (aligned.layout:measurer)
  (assert child.state.measure-called)
  (assert (= aligned.layout.measure.x measure.x))
  (assert (= aligned.layout.measure.y measure.y))
  (assert (= aligned.layout.measure.z measure.z))
  (aligned:drop))

(fn aligned-centers-child-on-axis []
  (local child (make-test-child (glm.vec3 1 2 3)))
  (local aligned ((Aligned {:child child.builder
                            :axis :y
                            :alignment :center}) {}))
  (set aligned.layout.size (glm.vec3 6 10 3))
  (set aligned.layout.position (glm.vec3 1 2 3))
  (set aligned.layout.rotation (glm.quat 1 0 0 0))
  (aligned.layout:measurer)
  (aligned.layout:layouter)
  (assert child.state.layouter-called)
  (assert (= child.state.received-size.x 6))
  (assert (= child.state.received-size.y 2))
  (assert (= child.state.received-size.z 3))
  (assert (= child.state.received-position.x 1))
  (assert (= child.state.received-position.y 6))
  (assert (= child.state.received-position.z 3))
  (aligned:drop))

(fn aligned-stretch-follows-parent-size []
  (local child (make-test-child (glm.vec3 1 2 3)))
  (local aligned ((Aligned {:child child.builder
                            :axis :y
                            :alignment :stretch}) {}))
  (set aligned.layout.size (glm.vec3 4 9 5))
  (set aligned.layout.position (glm.vec3 0 0 0))
  (set aligned.layout.rotation (glm.quat 1 0 0 0))
  (aligned.layout:measurer)
  (aligned.layout:layouter)
  (assert (= child.state.received-size.x 4))
  (assert (= child.state.received-size.y 9))
  (assert (= child.state.received-size.z 5))
  (assert (= child.state.received-position.y 0))
  (aligned:drop))

(fn aligned-drop-cleans-up-child []
  (local child (make-test-child (glm.vec3 1 1 1)))
  (local aligned ((Aligned {:child child.builder}) {}))
  (aligned:drop)
  (assert child.state.drop-called)
  (assert (= (length aligned.layout.children) 0)))

(fn aligned-centers-multiple-axes []
  (local child (make-test-child (glm.vec3 2 4 6)))
  (local aligned ((Aligned {:child child.builder
                            :xalign :center
                            :yalign :center}) {}))
  (set aligned.layout.size (glm.vec3 10 12 6))
  (set aligned.layout.position (glm.vec3 1 2 3))
  (set aligned.layout.rotation (glm.quat 1 0 0 0))
  (aligned.layout:measurer)
  (aligned.layout:layouter)
  (assert (= child.state.received-size.x 2))
  (assert (= child.state.received-size.y 4))
  (assert (= child.state.received-size.z 6))
  (assert (= child.state.received-position.x 5))
  (assert (= child.state.received-position.y 6))
  (assert (= child.state.received-position.z 3))
  (aligned:drop))

(fn aligned-stretch-multiple-axes []
  (local child (make-test-child (glm.vec3 2 4 6)))
  (local aligned ((Aligned {:child child.builder
                            :xalign :stretch
                            :yalign :stretch}) {}))
  (set aligned.layout.size (glm.vec3 10 12 6))
  (set aligned.layout.position (glm.vec3 0 0 0))
  (set aligned.layout.rotation (glm.quat 1 0 0 0))
  (aligned.layout:measurer)
  (aligned.layout:layouter)
  (assert (= child.state.received-size.x 10))
  (assert (= child.state.received-size.y 12))
  (assert (= child.state.received-size.z 6))
  (assert (= child.state.received-position.x 0))
  (assert (= child.state.received-position.y 0))
  (aligned:drop))

(table.insert tests {:name "Aligned measurer uses child measurement" :fn aligned-measurer-uses-child-measure})
(table.insert tests {:name "Aligned centers child along axis" :fn aligned-centers-child-on-axis})
(table.insert tests {:name "Aligned stretch fills parent size" :fn aligned-stretch-follows-parent-size})
(table.insert tests {:name "Aligned drop releases child" :fn aligned-drop-cleans-up-child})
(table.insert tests {:name "Aligned centers child on multiple axes" :fn aligned-centers-multiple-axes})
(table.insert tests {:name "Aligned stretch fills on multiple axes" :fn aligned-stretch-multiple-axes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "aligned"
                       :tests tests})))

{:name "aligned"
 :tests tests
 :main main}
