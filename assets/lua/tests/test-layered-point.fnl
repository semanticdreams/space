(local glm (require :glm))
(local LayeredPoint (require :layered-point))
(local Points (require :points))
(local MathUtils (require :math-utils))

(local tests [])

(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local approx (. MathUtils :approx))

(fn read-point [vector handle]
  (local data (vector:view handle))
  {:x (. data 1)
   :y (. data 2)
   :z (. data 3)
   :r (. data 4)
   :g (. data 5)
   :b (. data 6)
   :a (. data 7)
   :size (. data 8)
   :depth-offset-index (. data 9)})

(fn layered-point-updates-layers []
  (local vector (VectorBuffer))
  (local points (Points {:point-vector vector}))
  (local point
    (LayeredPoint {:points points
                   :position (glm.vec3 1 2 3)
                   :depth-offset-step 1
                   :base-depth-offset-index 2
                   :base-layer-index 3
                   :layers [{:size 12 :color (glm.vec4 1 0 0 1)}
                            {:size 10 :color (glm.vec4 0 1 0 1)}
                            {:size 8 :color (glm.vec4 0 0 1 1)}]}))
  (local layer-1 (. point.layers 1))
  (local layer-2 (. point.layers 2))
  (local layer-3 (. point.layers 3))
  (local view-1 (read-point vector layer-1.point.handle))
  (local view-2 (read-point vector layer-2.point.handle))
  (local view-3 (read-point vector layer-3.point.handle))
  (assert (approx view-1.size 12))
  (assert (approx view-2.size 10))
  (assert (approx view-3.size 8))
  (assert (approx view-3.z 3))
  (assert (approx view-1.depth-offset-index 0))
  (assert (approx view-2.depth-offset-index 1))
  (assert (approx view-3.depth-offset-index 2))
  (point:set-position (glm.vec3 4 5 6))
  (local moved-1 (read-point vector layer-1.point.handle))
  (local moved-2 (read-point vector layer-2.point.handle))
  (local moved-3 (read-point vector layer-3.point.handle))
  (assert (approx moved-1.x 4))
  (assert (approx moved-1.y 5))
  (assert (approx moved-1.z 6))
  (assert (approx moved-2.z 6))
  (assert (approx moved-3.z 6))
  (point:set-layer-size 1 0)
  (local resized-1 (read-point vector layer-1.point.handle))
  (assert (approx resized-1.size 0))
  (point:drop))

(table.insert tests {:name "LayeredPoint updates layer positions and sizes" :fn layered-point-updates-layers})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "layered-point"
                       :tests tests})))

{:name "layered-point"
 :tests tests
 :main main}
