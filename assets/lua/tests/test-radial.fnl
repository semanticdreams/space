(local glm (require :glm))
(local Radial (require :radial))
(local BuildContext (require :build-context))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec3-approx= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn center-of [state]
  (+ state.position (state.rotation:rotate (glm.vec3 (* 0.5 state.size.x)
                                                (* 0.5 state.size.y)
                                                (* 0.5 state.size.z)))))

(fn make-child [measure]
  (local state {:position nil :rotation nil :size nil})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "radial-child"
               :measurer (fn [self]
                           (set self.measure (or measure (glm.vec3 1 1 1))))
               :layouter (fn [self]
                           (set state.position self.position)
                           (set state.rotation self.rotation)
                           (set state.size self.size))}))
    {:layout layout
     :state state
     :drop (fn [_self])})
  {:builder builder :state state})

(fn make-context []
  (BuildContext {}))

(fn radial-spreads-around-circle []
  (local a (make-child))
  (local b (make-child))
  (local c (make-child))
  (local ctx (make-context))
  (local widget ((Radial {:radius 2
                          :children [a.builder b.builder c.builder]}) ctx))
  (widget.layout:measurer)
  (set widget.layout.size (glm.vec3 6 6 0))
  (widget.layout:layouter)
  (assert (vec3-approx= (center-of a.state) (glm.vec3 2 0 0)))
  (assert (vec3-approx= (center-of b.state) (glm.vec3 (- 1) 1.7320508 0)))
  (assert (vec3-approx= (center-of c.state) (glm.vec3 (- 1) -1.7320508 0)))
  (widget:drop))

(fn radial-start-align-clusters []
  (local a (make-child))
  (local b (make-child))
  (local c (make-child))
  (local ctx (make-context))
  (local widget ((Radial {:radius 1
                          :align :start
                          :children [a.builder b.builder c.builder]}) ctx))
  (widget.layout:measurer)
  (set widget.layout.size (glm.vec3 4 4 0))
  (widget.layout:layouter)
  (local center-a (center-of a.state))
  (local center-b (center-of b.state))
  (local center-c (center-of c.state))
  (assert (approx center-a.y 0))
  (assert (> center-b.y 0))
  (assert (> center-c.y 0))
  (assert (> center-a.x center-b.x))
  (widget:drop))

(fn radial-accounts-for-size []
  (local big (make-child (glm.vec3 4 1 1)))
  (local ctx (make-context))
  (local widget ((Radial {:radius 3
                          :children [big.builder]}) ctx))
  (widget.layout:measurer)
  (set widget.layout.size (glm.vec3 10 10 0))
  (widget.layout:layouter)
  (assert (vec3-approx= (center-of big.state) (glm.vec3 3 0 0)))
  (widget:drop))

(fn radial-orients-forward []
  (local a (make-child))
  (local ctx (make-context))
  (local widget ((Radial {:radius 2
                          :plane :xz
                          :orientation :forward
                          :children [a.builder]}) ctx))
  (widget.layout:measurer)
  (set widget.layout.size (glm.vec3 5 5 0))
  (widget.layout:layouter)
  (local facing (glm.normalize (a.state.rotation:rotate (glm.vec3 0 0 1))))
  (local center (center-of a.state))
  (local radial (glm.normalize (glm.vec3 center.x 0 center.z)))
  (local tangent (glm.normalize (glm.cross radial (glm.vec3 0 1 0))))
  (assert (> (glm.dot facing tangent) 0.9) (.. "expected forward tangent dot>0.9, got " (glm.dot facing tangent)))
  (widget:drop))

(fn radial-orients-inward []
  (local a (make-child (glm.vec3 2 2 2)))
  (local ctx (make-context))
  (local widget ((Radial {:radius 2
                          :plane :xz
                          :orientation :inward
                          :children [a.builder]}) ctx))
  (widget.layout:measurer)
  (set widget.layout.size (glm.vec3 5 5 0))
  (widget.layout:layouter)
  (local facing (glm.normalize (a.state.rotation:rotate (glm.vec3 0 0 1))))
  (local center (center-of a.state))
  (local radial (glm.normalize (glm.vec3 center.x 0 center.z)))
  (local dot (glm.dot facing radial))
  (assert (< dot -0.9) (.. "expected inward-facing, dot=" dot))
  (widget:drop))

(table.insert tests {:name "Radial spreads children around circle" :fn radial-spreads-around-circle})
(table.insert tests {:name "Radial start align clusters children" :fn radial-start-align-clusters})
(table.insert tests {:name "Radial positions children with size" :fn radial-accounts-for-size})
(table.insert tests {:name "Radial orientation faces forward tangent" :fn radial-orients-forward})
(table.insert tests {:name "Radial orientation faces inward" :fn radial-orients-inward})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "radial"
                       :tests tests})))

{:name "radial"
 :tests tests
 :main main}
