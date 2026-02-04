(local glm (require :glm))
(local MathUtils (require :math-utils))
(local {: ray-box-intersection} (require :ray-box))

(local tests [])

(local approx (. MathUtils :approx))

(fn intersects-axis-aligned-box []
  (local ray {:origin (glm.vec3 1 1 -5)
              :direction (glm.vec3 0 0 1)})
  (let [(hit point distance)
        (ray-box-intersection ray {:position (glm.vec3 0 0 0)
                                   :rotation (glm.quat 1 0 0 0)
                                   :size (glm.vec3 2 2 2)})]
    (assert hit "expected a hit")
    (assert point)
    (assert (approx distance 5))
    (assert (approx point.x 1))
    (assert (approx point.y 1))
    (assert (approx point.z 0))))

(fn intersects-rotated-box []
  (local ray {:origin (glm.vec3 -5 0.5 -0.5)
              :direction (glm.vec3 1 0 0)})
  (let [(hit point distance)
        (ray-box-intersection ray {:position (glm.vec3 0 0 0)
                                   :rotation (glm.quat (math.rad 90) (glm.vec3 0 1 0))
                                   :size (glm.vec3 1 1 1)})]
    (assert hit "expected rotated box hit")
    (assert point)
    (assert (approx distance 5))
    (assert (approx point.y 0.5))))

(fn misses-box []
  (local ray {:origin (glm.vec3 0 0 -5)
              :direction (glm.vec3 0 0 1)})
  (let [(hit _point _distance)
        (ray-box-intersection ray {:position (glm.vec3 10 0 0)
                                   :rotation (glm.quat 1 0 0 0)
                                   :size (glm.vec3 1 1 1)})]
    (assert (not hit) "expected miss for far box")))

(table.insert tests {:name "ray box intersect axis aligned" :fn intersects-axis-aligned-box})
(table.insert tests {:name "ray box intersect rotated" :fn intersects-rotated-box})
(table.insert tests {:name "ray box miss" :fn misses-box})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ray-box"
                       :tests tests})))

{:name "ray-box"
 :tests tests
 :main main}
