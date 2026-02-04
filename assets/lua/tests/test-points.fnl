(local glm (require :glm))
(local Points (require :points))
(local MathUtils (require :math-utils))

(local tests [])

(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
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

(fn defaults-and-setters []
  (local vector (VectorBuffer))
  (local points (Points {:point-vector vector}))
  (local point (points:create-point {}))
  (local view (read-point vector point.handle))
  (assert (approx view.x 0))
  (assert (approx view.y 0))
  (assert (approx view.z 0))
  (assert (approx view.size 10))
  (assert (approx view.depth-offset-index 0))
  (point:set-position (glm.vec3 3 4 5))
  (point:set-color (glm.vec4 0.1 0.2 0.3 0.4))
  (point:set-size 18)
  (point:set-depth-offset-index 3)
  (local updated (read-point vector point.handle))
  (assert (approx updated.x 3))
  (assert (approx updated.y 4))
  (assert (approx updated.z 5))
  (assert (approx updated.r 0.1))
  (assert (approx updated.g 0.2))
  (assert (approx updated.b 0.3))
  (assert (approx updated.a 0.4))
  (assert (approx updated.size 18))
  (assert (approx updated.depth-offset-index 3))
  (point:drop))

(fn drop-reuses-handle []
  (local vector (VectorBuffer))
  (local points (Points {:point-vector vector}))
  (local point (points:create-point {:position (glm.vec3 1 2 3)}))
  (local original-index point.handle.index)
  (point:drop)
  (local reused (points:create-point {:position (glm.vec3 4 5 6)}))
  (assert (= reused.handle.index original-index))
  (reused:drop))

(fn point-intersection-detects-ray-hit []
  (local vector (VectorBuffer))
  (local points (Points {:point-vector vector}))
  (local point (points:create-point {:position (glm.vec3 0 0 0)
                                     :size 10}))
  (local ray {:origin (glm.vec3 0 0 10)
              :direction (glm.vec3 0 0 -1)})
  (local (hit location distance) (point:intersect ray))
  (assert hit "Point should report an intersection when the ray passes through it")
  (assert location "Point intersection should return hit location")
  (assert (approx location.z 5) "Intersection point should lie on the ray")
  (assert (approx distance 5) "Intersection distance should match ray travel")
  (local miss-ray {:origin (glm.vec3 20 0 0)
                   :direction (glm.vec3 1 0 0)})
  (local (miss-hit _ _) (point:intersect miss-ray))
  (assert (not miss-hit) "Point intersection should fail when ray misses the sphere")
  (point:drop))

(table.insert tests {:name "Points defaults and setter updates" :fn defaults-and-setters})
(table.insert tests {:name "Points drop reuses handle storage" :fn drop-reuses-handle})
(table.insert tests {:name "Points expose ray intersections" :fn point-intersection-detects-ray-hit})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "points"
                       :tests tests})))

{:name "points"
 :tests tests
 :main main}
