(local glm (require :glm))
(local Car (require :car))
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
                :deletes 0
                :vec3-writes 0
                :vec4-writes 0
                :float-writes 0
                :last-size nil})
  (local buffer {})
  (set buffer.allocate
       (fn [_self count]
         (set state.allocations (+ state.allocations 1))
         (set state.last-size count)
         1))
  (set buffer.delete
       (fn [_self _handle]
         (set state.deletes (+ state.deletes 1))))
  (set buffer.set-glm-vec3
       (fn [_self _handle _offset value]
         (set state.vec3-writes (+ state.vec3-writes 1))
         (set state.last-position value)))
  (set buffer.set-glm-vec4
       (fn [_self _handle _offset _value]
         (set state.vec4-writes (+ state.vec4-writes 1))))
  (set buffer.set-float
       (fn [_self _handle _offset _value]
         (set state.float-writes (+ state.float-writes 1))))
  (set buffer.state state)
  buffer)

(fn make-test-ctx []
  (local track-log [])
  (local vector (make-vector-buffer))
  {:triangle-vector vector
   :track-log track-log
   :track-triangle-handle (fn [_ handle clip]
                            (table.insert track-log {:handle handle :clip clip}))
   :untrack-triangle-handle (fn [_ handle]
                              (table.insert track-log {:untracked handle}))})

(fn car-measurer-reflects-total-size []
  (local ctx (make-test-ctx))
  (local car ((Car {:body-length 12
                    :body-width 5
                    :body-height 4
                    :roof-height 2}) ctx))

  (car.layout:measurer)

  (local expected-size (glm.vec3 12 6 (+ 5 (* 2 1.2))))
  (assert (vec-approx= car.layout.measure expected-size))
  (assert (vec-approx= car.bounds.size expected-size))

  (car:drop)
  (assert (= ctx.triangle-vector.state.deletes 1)))

(fn car-layouter-writes-all-vertices []
  (local ctx (make-test-ctx))
  (local car ((Car {:body-length 10
                    :body-width 6
                    :body-height 3
                    :roof-height 1.5}) ctx))
  (car.layout:measurer)
  (set car.layout.size car.layout.measure)
  (set car.layout.position (glm.vec3 1 2 3))
  (set car.layout.rotation (glm.quat 1 0 0 0))

  (car.layout:layouter)

  (assert (> car.mesh.vertex-count 0))
  (assert (= ctx.triangle-vector.state.vec3-writes car.mesh.vertex-count))
  (assert (= ctx.triangle-vector.state.vec4-writes car.mesh.vertex-count))
  (assert (= ctx.triangle-vector.state.float-writes car.mesh.vertex-count))
  (assert (= (length ctx.track-log) 1))

  (car:drop)
  (assert (= ctx.triangle-vector.state.deletes 1)))

(fn car-set-visible-releases-buffer []
  (local ctx (make-test-ctx))
  (local car ((Car {:body-height 3 :roof-height 2}) ctx))

  (car:set-visible false)
  (assert (= ctx.triangle-vector.state.deletes 1))
  (car:set-visible true)
  (car.layout:measurer)
  (set car.layout.size car.layout.measure)
  (car.layout:layouter)
  (assert (> ctx.triangle-vector.state.vec3-writes 0))

  (car:drop)
  (assert (>= ctx.triangle-vector.state.deletes 2)))

(fn car-wheels-extend-outside-body []
  (local body-width 6)
  (local wheel-width 1.5)
  (local ctx (make-test-ctx))
  (local car ((Car {:body-width body-width
                    :wheel-width wheel-width}) ctx))
  (var min-z math.huge)
  (var max-z (- math.huge))
  (each [_ pos (ipairs car.mesh.positions)]
    (when (< pos.z min-z)
      (set min-z pos.z))
    (when (> pos.z max-z)
      (set max-z pos.z)))
  (assert (< min-z 0)
          (.. "Expected wheel geometry to extend below zero z, got " min-z))
  (assert (> max-z body-width)
          (.. "Expected wheel geometry to extend beyond body width, got " max-z))
  (assert (> car.bounds.size.z body-width))

  (car:drop))

(table.insert tests {:name "Car measurer reflects configured size" :fn car-measurer-reflects-total-size})
(table.insert tests {:name "Car layouter writes triangle data" :fn car-layouter-writes-all-vertices})
(table.insert tests {:name "Car set-visible toggles buffers" :fn car-set-visible-releases-buffer})
(table.insert tests {:name "Car wheels extend outside body width" :fn car-wheels-extend-outside-body})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "car"
                       :tests tests})))

{:name "car"
 :tests tests
 :main main}
