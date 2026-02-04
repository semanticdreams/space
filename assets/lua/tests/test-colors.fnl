(local glm (require :glm))
(local tests [])

(local epsilon 2e-2)

(local colors (require :colors))
(fn close? [a b]
  (< (math.abs (- a b)) epsilon))

(fn vec3-close? [a b]
  (and (close? a.x b.x)
       (close? a.y b.y)
       (close? a.z b.z)))

(fn luma [color]
  (+ (* 0.2126 color.x)
     (* 0.7152 color.y)
     (* 0.0722 color.z)))

(fn swatch-provides-default-steps []
  (local swatch (colors.create-color-swatch (glm.vec3 0.35 0.55 0.75)))
  (each [_ key (ipairs [0 100 200 300 400 500 600 700 800 900])]
    (assert (. swatch key) (.. "missing swatch step " key)))
  (var count 0)
  (each [_ _ (pairs swatch)]
    (set count (+ count 1)))
  (assert (= count 10) "swatch should include 10 entries"))

(fn swatch-preserves-base-step-and-orders-lightness []
  (local base (glm.vec3 0.25 0.5 0.75))
  (local swatch (colors.create-color-swatch base))
  (assert (vec3-close? (. swatch 500) base) "step 500 should match base color")
  (assert (> (luma (. swatch 0)) (luma (. swatch 900))) "lighter steps should have higher luma than darkest"))

(table.insert tests {:name "colors create_color_swatch returns expected steps" :fn swatch-provides-default-steps})
(table.insert tests {:name "colors create_color_swatch keeps midpoint and orders lightness" :fn swatch-preserves-base-step-and-orders-lightness})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "colors"
                       :tests tests})))

{:name "colors"
 :tests tests
 :main main}
