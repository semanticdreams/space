(local glm (require :glm))
(local DemoCar (require :demo-car))
(local MathUtils (require :math-utils))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec-approx= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn make-vector-buffer []
  (local state {:allocations 0
                :deletes 0})
  (local buffer {})
  (set buffer.allocate
       (fn [_self _count]
         (set state.allocations (+ state.allocations 1))
         1))
  (set buffer.delete
       (fn [_self _handle]
         (set state.deletes (+ state.deletes 1))))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  (set buffer.state state)
  buffer)

(fn make-ctx []
  {:triangle-vector (make-vector-buffer)})

(fn demo-car-wraps-car-entity []
  (local ctx (make-ctx))
  (local position (glm.vec3 5 1 2))
  (local builder (DemoCar {:position position}))
  (local entity (builder ctx))

  (entity.layout:measurer)
  (set entity.layout.size entity.layout.measure)
  (entity.layout:layouter)

  (assert entity.car)
  (assert (= entity.car.layout.name "car"))
  (assert (= entity.layout.name "positioned"))
  (assert entity.__demo_car)
  (assert (vec-approx= entity.layout.measure entity.car.bounds.size))

  (entity:drop)
  (assert (= ctx.triangle-vector.state.deletes 1)))

(table.insert tests {:name "Demo car positions a car entity" :fn demo-car-wraps-car-entity})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "demo-car"
                       :tests tests})))

{:name "demo-car"
 :tests tests
 :main main}
