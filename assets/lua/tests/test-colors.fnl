(local glm (require :glm))
(local colors (require :colors))
(local tests [])

(fn close? [a b ?eps]
  (< (math.abs (- a b)) (or ?eps 1e-4)))

(fn vec3-close? [a b ?eps]
  (and (close? a.x b.x ?eps)
       (close? a.y b.y ?eps)
       (close? a.z b.z ?eps)))

(fn vec4-close? [a b ?eps]
  (and (close? a.x b.x ?eps)
       (close? a.y b.y ?eps)
       (close? a.z b.z ?eps)
       (close? a.w b.w ?eps)))

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
  (assert (vec3-close? (. swatch 500) base 2e-2) "step 500 should match base color")
  (assert (> (luma (. swatch 0)) (luma (. swatch 900)))
          "lighter steps should have higher luma than darkest"))

(fn rgb-xyz-roundtrip []
  (local rgb (glm.vec3 0.12 0.34 0.56))
  (local xyz (colors.rgb-to-xyz rgb))
  (local rgb-back (colors.xyz-to-rgb xyz))
  (assert (vec3-close? rgb rgb-back 4e-4) "RGB<->XYZ should roundtrip"))

(fn rgb-lab-roundtrip []
  (local rgb (glm.vec3 0.9 0.2 0.4))
  (local lab (colors.rgb-to-lab rgb))
  (local rgb-back (colors.lab-to-rgb lab))
  (assert (vec3-close? rgb rgb-back 5e-4) "RGB<->Lab should roundtrip"))

(fn lchab-lab-roundtrip []
  (local lab (glm.vec3 55 -22 40))
  (local lch (colors.lab-to-lchab lab))
  (local lab-back (colors.lchab-to-lab lch))
  (assert (vec3-close? lab lab-back 5e-4) "Lab<->LCHab should roundtrip"))

(fn luv-lchuv-and-xyz-roundtrip []
  (local xyz (glm.vec3 25 32 12))
  (local luv (colors.xyz-to-luv xyz))
  (local lchuv (colors.luv-to-lchuv luv))
  (local luv-back (colors.lchuv-to-luv lchuv))
  (local xyz-back (colors.luv-to-xyz luv-back))
  (assert (vec3-close? luv luv-back 5e-4) "Luv<->LCHuv should roundtrip")
  (assert (vec3-close? xyz xyz-back 5e-3) "XYZ<->Luv should roundtrip"))

(fn xyy-roundtrip-and-zero []
  (local xyz (glm.vec3 22 33 11))
  (local xyy (colors.xyz-to-xyy xyz))
  (local xyz-back (colors.xyy-to-xyz xyy))
  (assert (vec3-close? xyz xyz-back 5e-4) "XYZ<->xyY should roundtrip")

  (local zero (colors.xyy-to-xyz (glm.vec3 0.2 0.0 0.7)))
  (assert (vec3-close? zero (glm.vec3 0 0 0) 1e-7) "xyY with y=0 should map to zero XYZ"))

(fn hsv-hsl-cmy-cmyk-roundtrips []
  (local rgb (glm.vec3 0.18 0.62 0.43))

  (local hsv (colors.rgb-to-hsv rgb))
  (local rgb-hsv (colors.hsv-to-rgb hsv))
  (assert (vec3-close? rgb rgb-hsv 5e-4) "RGB<->HSV should roundtrip")

  (local hsl (colors.rgb-to-hsl rgb))
  (local rgb-hsl (colors.hsl-to-rgb hsl))
  (assert (vec3-close? rgb rgb-hsl 5e-4) "RGB<->HSL should roundtrip")

  (local cmy (colors.rgb-to-cmy rgb))
  (local rgb-cmy (colors.cmy-to-rgb cmy))
  (assert (vec3-close? rgb rgb-cmy 1e-7) "RGB<->CMY should roundtrip")

  (local cmyk (colors.cmy-to-cmyk cmy))
  (local cmy-back (colors.cmyk-to-cmy cmyk))
  (assert (vec3-close? cmy cmy-back 1e-6) "CMY<->CMYK should roundtrip")

  (local black-cmyk (colors.cmy-to-cmyk (glm.vec3 1 1 1)))
  (assert (vec4-close? black-cmyk (glm.vec4 0 0 0 1) 1e-7) "pure CMY black should map to K-only"))

(fn ipt-roundtrip []
  (local xyz (glm.vec3 41 21 13))
  (local ipt (colors.xyz-to-ipt xyz))
  (local xyz-back (colors.ipt-to-xyz ipt))
  (assert (vec3-close? xyz xyz-back 1e-2) "XYZ<->IPT should roundtrip"))

(fn illuminants-and-adaptation []
  (local d65 (colors.get-illuminant "2" "d65"))
  (local d50 (colors.get-illuminant "2" "d50"))
  (assert (vec3-close? d65 (glm.vec3 95.047 100 108.883) 1e-3) "D65 illuminant should match reference")

  (local same (colors.adapt-xyz d65 "d65" "d65"))
  (assert (vec3-close? same d65 1e-4) "identity adaptation should preserve XYZ")

  (local adapted (colors.adapt-xyz d65 "d65" "d50" "2" "bradford"))
  (assert (vec3-close? adapted d50 2e-2) "adapting D65 white to D50 should produce D50 white")

  (local adapted-vk (colors.adapt-xyz d65 "d65" "d50" "2" "von_kries"))
  (assert (vec3-close? adapted-vk d50 2e-2) "von_kries should also map source white to target white"))

(fn delta-e-metrics []
  (local lab1 (glm.vec3 50 2.6772 -79.7751))
  (local lab2 (glm.vec3 50 0 -82.7485))

  (assert (close? (colors.delta-e-cie2000 lab1 lab2) 2.0425 2e-3)
          "DeltaE2000 should match reference pair")
  (assert (close? (colors.delta-e-cie1976 lab1 lab1) 0 1e-7)
          "DeltaE1976 should be zero for identical colors")
  (assert (close? (colors.delta-e-cie1994 lab1 lab1) 0 1e-7)
          "DeltaE1994 should be zero for identical colors")
  (assert (close? (colors.delta-e-cmc lab1 lab1) 0 1e-7)
          "DeltaECMC should be zero for identical colors")

  (assert (> (colors.delta-e-cie1976 lab1 lab2) 3.9)
          "DeltaE1976 should show a larger geometric distance for the sample"))

(fn make-spectral-sample []
  (local out [])
  (for [i 1 50]
    (table.insert out (+ 35 (* i 0.5))))
  out)

(fn matrix-and-spectral-and-density []
  (local lab-base (glm.vec3 42 3 -19))
  (local labs [(glm.vec3 42 3 -19)
               (glm.vec3 42 4 -19)
               (glm.vec3 46 10 -12)])
  (local e76-m (colors.delta-e-cie1976-matrix lab-base labs))
  (local e94-m (colors.delta-e-cie1994-matrix lab-base labs))
  (local e00-m (colors.delta-e-cie2000-matrix lab-base labs))
  (local cmc-m (colors.delta-e-cmc-matrix lab-base labs))
  (assert (= (# e76-m) 3) "matrix DeltaE76 should return one value per candidate")
  (assert (= (# e94-m) 3) "matrix DeltaE94 should return one value per candidate")
  (assert (= (# e00-m) 3) "matrix DeltaE00 should return one value per candidate")
  (assert (= (# cmc-m) 3) "matrix DeltaECMC should return one value per candidate")
  (assert (close? (. e76-m 1) 0 1e-7) "first matrix entry should be zero for identical color")

  (local spectral (make-spectral-sample))
  (local xyz-d50 (colors.spectral-to-xyz spectral))
  (local xyz-d65 (colors.spectral-to-xyz spectral "2" "d65"))
  (assert (> xyz-d50.y 0) "spectral-to-xyz should produce positive Y")
  (assert (> xyz-d65.y 0) "spectral-to-xyz with explicit illuminant should produce positive Y")

  (local d-blue (colors.ansi-density spectral "ansi_status_t_blue"))
  (local d-auto (colors.auto-density spectral))
  (assert (= d-blue d-blue) "ansi-density should be numeric")
  (assert (= d-auto d-auto) "auto-density should be numeric"))

(fn convert-color-and-appearance-models []
  (local rgb (glm.vec4 0.3 0.6 0.2 0))
  (local lab4 (colors.convert-color rgb "rgb" "lab"))
  (local rgb-back (colors.convert-color lab4 "lab" "rgb"))
  (assert (vec3-close? (glm.vec3 rgb.x rgb.y rgb.z) (glm.vec3 rgb-back.x rgb-back.y rgb-back.z) 5e-3)
          "convert-color should roundtrip RGB->Lab->RGB")

  (local nayatani (colors.model-nayatani95 19.01 20.0 21.78 95.05 100.0 108.88 20.0 1000.0 1000.0 1.0))
  (assert nayatani.chroma "nayatani95 model should return chroma")
  (assert nayatani.hue-angle "nayatani95 model should return hue-angle")

  (local hunt (colors.model-hunt 19.01 20.0 21.78 19.01 20.0 21.78 95.05 100.0 108.88 318.31 1.0 1.0))
  (assert hunt.colorfulness "hunt model should return colorfulness")

  (local rlab (colors.model-rlab 19.01 20.0 21.78 95.05 100.0 108.88 318.31 (/ 1 2.3) 1.0))
  (assert rlab.lightness "rlab model should return lightness")

  (local atd95 (colors.model-atd95 19.01 20.0 21.78 95.05 100.0 108.88 31.83 1.0 0.0 300.0))
  (assert atd95.brightness "atd95 model should return brightness")

  (local llab (colors.model-llab 19.01 20.0 21.78 95.05 100.0 108.88 20.0 1.0 1.0 1.0 318.31 1.0))
  (assert llab.a-l "llab model should return a-l")

  (local ciecam (colors.model-ciecam02 19.01 20.0 21.78 95.05 100.0 108.88 20.0 318.31 0.69 1.0 1.0 false))
  (assert ciecam.lightness "ciecam02 model should return lightness")

  (local ciecam-m1 (colors.model-ciecam02m1 19.01 20.0 21.78 95.05 100.0 108.88 30.0 30.0 30.0 318.31 0.69 1.0 1.0 0.2 false))
  (assert ciecam-m1.colorfulness "ciecam02m1 model should return colorfulness"))

(fn conversion-graph-and-rgb-helpers-and-illuminant-aware []
  (assert (colors.can-convert "rgb" "lab") "rgb should be convertible to lab")
  (local path (colors.conversion-path "rgb" "lchuv"))
  (assert (= (. path 1) "rgb") "conversion path should start with source")
  (assert (= (. path (# path)) "lchuv") "conversion path should end with target")

  (local upscaled (colors.rgb-to-upscaled (glm.vec3 0.5 0.25 1.0)))
  (assert (= upscaled.x 128) "rgb-to-upscaled should round correctly")
  (assert (= upscaled.y 64) "rgb-to-upscaled should round correctly")
  (assert (= upscaled.z 255) "rgb-to-upscaled should round correctly")

  (local hex (colors.rgb-to-hex (glm.vec3 1 0.5 0)))
  (assert (= hex "#ff8000") "rgb-to-hex should encode")
  (local rgb-from-hex (colors.rgb-from-hex "#ff8000"))
  (assert (vec3-close? rgb-from-hex (glm.vec3 1 0.5019608 0) 1e-6) "rgb-from-hex should decode")

  (local clamped (colors.clamp-rgb (glm.vec3 -0.3 0.2 1.8)))
  (assert (vec3-close? clamped (glm.vec3 0 0.2 1) 1e-7) "clamp-rgb should clamp channels")

  (local xyz-d50 (glm.vec3 42 50 39))
  (local lab-d50 (colors.xyz-to-lab xyz-d50 "2" "d50"))
  (local xyz-back (colors.lab-to-xyz lab-d50 "2" "d50"))
  (assert (vec3-close? xyz-d50 xyz-back 5e-3) "xyz<->lab should support explicit observer/illuminant")

  (local luv-d50 (colors.xyz-to-luv xyz-d50 "2" "d50"))
  (local xyz-luv-back (colors.luv-to-xyz luv-d50 "2" "d50"))
  (assert (vec3-close? xyz-d50 xyz-luv-back 5e-3) "xyz<->luv should support explicit observer/illuminant"))

(table.insert tests {:name "colors create-color-swatch returns expected steps" :fn swatch-provides-default-steps})
(table.insert tests {:name "colors create-color-swatch keeps midpoint and orders lightness" :fn swatch-preserves-base-step-and-orders-lightness})
(table.insert tests {:name "colors RGB XYZ roundtrip" :fn rgb-xyz-roundtrip})
(table.insert tests {:name "colors RGB Lab roundtrip" :fn rgb-lab-roundtrip})
(table.insert tests {:name "colors Lab LCHab roundtrip" :fn lchab-lab-roundtrip})
(table.insert tests {:name "colors Luv LCHuv XYZ roundtrip" :fn luv-lchuv-and-xyz-roundtrip})
(table.insert tests {:name "colors xyY roundtrip and zero edge" :fn xyy-roundtrip-and-zero})
(table.insert tests {:name "colors HSV HSL CMY CMYK roundtrips" :fn hsv-hsl-cmy-cmyk-roundtrips})
(table.insert tests {:name "colors IPT roundtrip" :fn ipt-roundtrip})
(table.insert tests {:name "colors illuminants and adaptation" :fn illuminants-and-adaptation})
(table.insert tests {:name "colors Delta E metrics" :fn delta-e-metrics})
(table.insert tests {:name "colors matrix delta spectral and density" :fn matrix-and-spectral-and-density})
(table.insert tests {:name "colors convert-color and appearance models" :fn convert-color-and-appearance-models})
(table.insert tests {:name "colors conversion graph rgb helpers and illuminant-aware conversions"
                     :fn conversion-graph-and-rgb-helpers-and-illuminant-aware})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "colors"
                       :tests tests})))

{:name "colors"
 :tests tests
 :main main}
