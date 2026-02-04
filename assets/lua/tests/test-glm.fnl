(local glm (require :glm))
(local tests [])

(local epsilon 1e-5)

(fn close? [a b]
  (< (math.abs (- a b)) epsilon))

(fn vec-close? [a b]
  (and (close? a.x b.x)
       (close? a.y b.y)
       (close? a.z b.z)))

(fn vec4-close? [a b]
  (and (close? a.x b.x)
       (close? a.y b.y)
       (close? a.z b.z)
       (close? a.w b.w)))

(fn vec2-close? [a b]
  (and (close? a.x b.x)
       (close? a.y b.y)))

(fn supports-scalar-mul-and-div []
  (local v (glm.vec3 2 4 6))
  (local half (* 0.5 v))
  (local also-half (* v 0.5))
  (assert (vec-close? half (glm.vec3 1 2 3)) "0.5 * glm.vec3 failed")
  (assert (vec-close? also-half (glm.vec3 1 2 3)) "glm.vec3 * 0.5 failed")
  (local divided (/ v 2))
  (local flipped (/ 12 v))
  (assert (vec-close? divided (glm.vec3 1 2 3)) "glm.vec3 / scalar failed")
  (assert (vec-close? flipped (glm.vec3 6 3 2)) "scalar / glm.vec3 failed"))

(fn vec2-and-vec4-scalar-ops []
  (local v2 (glm.vec2 3 9))
  (local v4 (glm.vec4 1 2 3 4))
  (assert (vec2-close? (* 2 v2) (glm.vec2 6 18)) "glm.vec2 scalar mul failed")
  (assert (vec2-close? (/ 12 v2) (glm.vec2 4 1.3333333)) "glm.vec2 scalar div failed")
  (assert (vec4-close? (* v4 0.25) (glm.vec4 0.25 0.5 0.75 1.0)) "glm.vec4 scalar mul failed")
  (assert (vec4-close? (/ v4 2) (glm.vec4 0.5 1 1.5 2)) "glm.vec4 scalar div failed"))

(fn mat4-multiplication-overloads []
  (local identity (glm.mat4 1.0))
  (local v (glm.vec4 1 2 3 1))
  (local scaled (* 0.5 identity))
  (local transformed (* identity v))
  (assert (vec4-close? transformed v) "glm.mat4 * glm.vec4 failed")
  (assert (vec4-close? (* v identity) v) "glm.vec4 * glm.mat4 failed")
  (local scaled-vector (* scaled v))
  (assert (vec4-close? scaled-vector (glm.vec4 0.5 1 1.5 0.5)) "scalar * glm.mat4 failed"))

(fn quat-rotation-applies []
  (local axis (glm.vec3 0 1 0))
  (local rotation (glm.quat (/ math.pi 2) axis))
  (local forward (glm.vec3 0 0 -1))
  (local rotated (rotation:rotate forward))
  (assert (close? rotated.x -1.0) "glm.quat rotation x component incorrect")
  (assert (close? rotated.z 0.0) "glm.quat rotation z component incorrect"))

(fn glm-functions-available []
  (local v (glm.vec3 3 0 4))
  (assert (close? (glm.length v) 5.0) "glm.length missing")
  (local normalized (glm.normalize v))
  (assert (close? (glm.dot normalized normalized) 1.0) "glm.normalize missing")
  (local cross (glm.cross (glm.vec3 1 0 0) (glm.vec3 0 1 0)))
  (assert (vec-close? cross (glm.vec3 0 0 1)) "glm.cross missing"))

(table.insert tests {:name "glm glm.vec3 supports scalar mul/div both sides" :fn supports-scalar-mul-and-div})
(table.insert tests {:name "glm glm.vec2/glm.vec4 scalar ops" :fn vec2-and-vec4-scalar-ops})
(table.insert tests {:name "glm glm.mat4 multiplication overloads" :fn mat4-multiplication-overloads})
(table.insert tests {:name "glm glm.quat rotate applies" :fn quat-rotation-applies})
(table.insert tests {:name "glm core functions bound" :fn glm-functions-available})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "glm"
                       :tests tests})))

{:name "glm"
 :tests tests
 :main main}
