(local glm (require :glm))
(local WidgetCuboid (require :widget-cuboid))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec-approx= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn make-probe-widget [size]
  (local state {:drop-count 0})
  (fn builder [_ctx _opts]
    (local layout
      (Layout {:name "probe"
               :measurer (fn [self]
                         (set self.measure size))
               :layouter (fn [self]
                           (set self.size self.measure))}))
    (local widget {:layout layout})
    (set widget.drop (fn [_]
                       (set state.drop-count (+ state.drop-count 1))
                       (layout:drop)))
    (set state.widget widget)
    widget)
  {:builder builder :state state})

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx []
  {:triangle-vector (make-vector-buffer)})

(fn widget-cuboid-scales-depth-from-width []
  (local probe (make-probe-widget (glm.vec3 4 2 0)))
  (local builder (WidgetCuboid {:child probe.builder}))
  (local wrapped (builder (make-test-ctx)))

  (wrapped.layout:measurer)

  (assert (vec-approx= wrapped.layout.measure (glm.vec3 4 2 2)))
  (assert (= wrapped.front.__scene_wrapper wrapped))

  (wrapped:drop)
  (assert (= probe.state.drop-count 1)))

(fn widget-cuboid-honors-min-depth []
  (local probe (make-probe-widget (glm.vec3 1 1 0)))
  (local builder (WidgetCuboid {:child probe.builder
                                :depth-scale 0.1
                                :min-depth 0.5}))
  (local wrapped (builder (make-test-ctx)))

  (wrapped.layout:measurer)

  (assert (vec-approx= wrapped.layout.measure (glm.vec3 1 1 0.5)))

  (wrapped:drop))

(table.insert tests {:name "WidgetCuboid scales depth from width" :fn widget-cuboid-scales-depth-from-width})
(table.insert tests {:name "WidgetCuboid honors min depth" :fn widget-cuboid-honors-min-depth})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "widget-cuboid"
                       :tests tests})))

{:name "widget-cuboid"
 :tests tests
 :main main}
