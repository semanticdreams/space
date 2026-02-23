(local glm (require :glm))
(local colorspacious (require :colorspacious))
(local tests [])

(fn close? [a b ?eps]
  (< (math.abs (- a b)) (or ?eps 1e-4)))

(fn vec3-components [v]
  (if (and v v.x v.y v.z)
      [v.x v.y v.z]
      [(. v 1) (. v 2) (. v 3)]))

(fn vec3-close? [a b ?eps]
  (local av (vec3-components a))
  (local bv (vec3-components b))
  (and (close? (. av 1) (. bv 1) ?eps)
       (close? (. av 2) (. bv 2) ?eps)
       (close? (. av 3) (. bv 3) ?eps)))

(fn illuminants-and-whitepoint-helper []
  (local d65-2 (colorspacious.standard_illuminant_XYZ100 "D65"))
  (assert (vec3-close? d65-2 (glm.vec3 95.047 100 108.883) 1e-3)
          "D65 CIE1931 values should match reference")

  (local d65-10 (colorspacious.standard_illuminant_XYZ100 "D65" "CIE 1964 10 deg"))
  (assert (vec3-close? d65-10 (glm.vec3 94.81 100 107.3) 2e-2)
          "D65 CIE1964 values should match reference")

  (local wp (colorspacious.as_XYZ100_w "D50"))
  (assert (vec3-close? wp (glm.vec3 96.422 100 82.521) 1e-3)
          "as_XYZ100_w should resolve string whitepoints"))

(fn constructors-and-normalize-space []
  (local surround (colorspacious.CIECAM02Surround 1.0 0.69 1.0))
  (local vc (colorspacious.CIECAM02Space "D65" 20.0 30.0 surround))
  (assert (= vc.__kind "CIECAM02Space") "CIECAM02Space constructor should return typed table")

  (local luo (colorspacious.LuoEtAl2006UniformSpace 1.0 0.007 0.0228))
  (assert (= luo.__kind "LuoEtAl2006UniformSpace") "LuoEtAl2006 constructor should return typed table")

  (local alias (colorspacious.normalize-space "CAM02-UCS"))
  (assert (= alias.name "J'a'b'") "CAM02-UCS alias should normalize to J'a'b'")

  (local jch (colorspacious.normalize-space "JCh"))
  (assert (= jch.name "CIECAM02-subset") "JCh string should normalize to CIECAM02 subset")
  (assert (= jch.axes "JCh") "JCh subset should preserve axes")

  (local override
    (colorspacious.normalize-space {:name "CAM02-UCS" :ciecam02_space vc}))
  (assert (= override.name "J'a'b'") "alias dict should normalize to target space")
  (assert (= (. override.ciecam02_space.Y_b) 20.0)
          "override should preserve explicit ciecam02_space"))

(fn cspace-convert-trivial-and-vectorized []
  (local one (colorspacious.cspace_convert [0.1 0.2 0.3] "sRGB1" "sRGB1"))
  (assert (vec3-close? one [0.1 0.2 0.3] 2e-5)
          "sRGB1->sRGB1 should be identity")

  (local batch [[0.1 0.2 0.3] [0.3 0.2 0.1]])
  (local to255 (colorspacious.cspace_convert batch "sRGB1" "sRGB255"))
  (assert (vec3-close? (. to255 1) [25.5 51.0 76.5] 2e-2)
          "vectorized conversion should transform first row")
  (local back (colorspacious.cspace_convert to255 "sRGB255" "sRGB1"))
  (assert (vec3-close? (. back 2) [0.3 0.2 0.1] 2e-4)
          "vectorized roundtrip should recover second row"))

(fn cspace-convert-gold-paths []
  (local xyY100 (colorspacious.cspace_convert [0.1 0.2 0.3] "sRGB1" "xyY100"))
  (assert (vec3-close? xyY100 [0.21778106689453 0.2319852411747 3.1095232963562] 3e-5)
          "sRGB1->xyY100 should match gold tolerance")

  (local srgb255 (colorspacious.cspace_convert [0.4 0.3 0.2] "sRGB1" "sRGB255"))
  (assert (vec3-close? srgb255 [102 76.5 51] 2e-2)
          "sRGB1->sRGB255 should scale channels"))

(fn cielab-and-cielch-with-whitepoint []
  (local xyz [2.61219 1.52732 10.96471])
  (local lab-d50 (colorspacious.cspace_convert xyz "XYZ100" {:name "CIELab" :XYZ100_w "D50"}))
  (assert (vec3-close? lab-d50 [12.7806 26.1147 -52.4348] 2e-3)
          "XYZ100->CIELab D50 should match gold")

  (local lch-d65 (colorspacious.cspace_convert [10 20 30] "XYZ100" "CIELCh"))
  (assert (vec3-close? lch-d65 [51.8372 57.88 193.1636] 3e-3)
          "XYZ100->CIELCh D65 should match gold"))

(fn ciecam02-gold-and-roundtrip []
  (local vc (colorspacious.CIECAM02Space [98.88 90 32.03] 18 200
                                         (colorspacious.CIECAM02Surround 1.0 0.69 1.0)))
  (local spec {:name "CIECAM02" :ciecam02_space vc})
  (local got (colorspacious.cspace_convert [19.31 23.93 10.14] "XYZ100" spec))
  (assert (close? got.h 191.0452 3e-3) "CIECAM02 hue should match gold")
  (assert (close? got.J 48.0314 3e-3) "CIECAM02 J should match gold")

  (local xyz-back (colorspacious.cspace_convert got spec "XYZ100"))
  (assert (vec3-close? xyz-back [19.31 23.93 10.14] 1e-3)
          "CIECAM02 roundtrip should recover XYZ100"))

(fn ciecam02-subset-and-cross-viewing-condition []
  (local vc1 (colorspacious.CIECAM02Space [98.88 90 32.03] 18 200
                                          (colorspacious.CIECAM02Surround 1.0 0.69 1.0)))
  (local vc2 (colorspacious.CIECAM02Space [98.88 90 32.03] 18 20
                                          (colorspacious.CIECAM02Surround 1.0 0.69 1.0)))

  (local jch1-space {:name "CIECAM02-subset" :axes "JCh" :ciecam02_space vc1})
  (local jch2-space {:name "CIECAM02-subset" :axes "JCh" :ciecam02_space vc2})
  (local jch1 [48.0314 38.7789 191.0452])
  (local jch2 (colorspacious.cspace_convert jch1 jch1-space jch2-space))
  (assert (vec3-close? jch2 [47.6856 36.0527 185.3445] 5e-3)
          "cross-viewing-condition JCh conversion should match gold")

  (local qmh-space {:name "CIECAM02-subset" :axes "QMH" :ciecam02_space vc1})
  (local qmh (colorspacious.cspace_convert jch1 jch1-space qmh-space))
  (assert (vec3-close? qmh [183.1240 38.7789 240.8885] 8e-3)
          "subset->subset should route through XYZ/CIECAM02"))

(fn cam02-ucs-lcd-scd-silver []
  (local ucs (colorspacious.cspace_convert [50 20 10] "JMh" "CAM02-UCS"))
  (assert (vec3-close? ucs [62.96296296 16.22742674 2.86133316] 5e-5)
          "JMh->CAM02-UCS should match silver")

  (local lcd (colorspacious.cspace_convert [50 20 10] "JMh" "CAM02-LCD"))
  (assert (vec3-close? lcd [81.77008177 18.72061994 3.30095039] 5e-5)
          "JMh->CAM02-LCD should match silver")

  (local scd (colorspacious.cspace_convert [10 60 100] "JMh" "CAM02-SCD"))
  (assert (vec3-close? scd [12.81278263 -5.5311588 31.36876036] 4e-5)
          "JMh->CAM02-SCD should match silver"))

(fn cvd-silver-and-matrix []
  (local m (colorspacious.machado_et_al_2009_matrix "deuteranomaly" 50))
  (assert (close? (. (. m 1) 1) 0.547494 1e-6)
          "CVD matrix should expose Machado coefficients")

  (local deut50
    (colorspacious.cspace_convert [0.1 0.2 0.3]
                                  {:name "sRGB1+CVD" :cvd_type "deuteranomaly" :severity 50}
                                  "sRGB1"))
  (assert (vec3-close? deut50 [0.12440528 0.19103024 0.29911687] 3e-5)
          "deuteranomaly 50 should match silver")

  (local prot95
    (colorspacious.cspace_convert [0.9 0.5 0.3]
                                  {:name "sRGB1+CVD" :cvd_type "protanomaly" :severity 95}
                                  "sRGB1"))
  (assert (vec3-close? prot95 [0.62151883 0.55237436 0.27997229] 3e-5)
          "protanomaly 95 should match silver"))

(fn converter-and-deltae []
  (local conv (colorspacious.cspace_converter "sRGB1" "CIELab"))
  (local a (conv [0.1 0.2 0.3]))
  (local b (colorspacious.cspace_convert [0.1 0.2 0.3] "sRGB1" "CIELab"))
  (assert (vec3-close? a b 1e-7) "cspace_converter should match direct cspace_convert")

  (local de76 (colorspacious.deltaE [173 52 52] [69 120 51] "sRGB255" "CIELab"))
  (assert (close? de76 80.3336 0.2) "deltaE CIELab should match reference")

  (local de-batch (colorspacious.deltaE [[173 52 52] [69 100 52]]
                                        [[69 120 51] [69 120 51]]
                                        "sRGB255"
                                        "CIELab"))
  (assert (close? (. de-batch 1) 80.3336 0.2) "vectorized deltaE first row should match")
  (assert (close? (. de-batch 2) 14.7071 0.2) "vectorized deltaE second row should match"))

(fn error-checks []
  (local (ok1 err1) (pcall colorspacious.standard_illuminant_XYZ100 "D65" "bad observer"))
  (assert (not ok1) "invalid observer should fail")
  (assert err1 "invalid observer should provide error")

  (local subset {:name "CIECAM02-subset" :axes "JCh" :ciecam02_space colorspacious.CIECAM02Space.sRGB})
  (local (ok2 err2) (pcall colorspacious.cspace_convert [1 2 3 4] subset "XYZ100"))
  (assert (not ok2) "subset dimensional mismatch should fail")
  (assert err2 "subset mismatch should provide error"))

(table.insert tests {:name "colorspacious illuminants and whitepoint helper" :fn illuminants-and-whitepoint-helper})
(table.insert tests {:name "colorspacious constructors and normalization" :fn constructors-and-normalize-space})
(table.insert tests {:name "colorspacious trivial and vectorized conversion" :fn cspace-convert-trivial-and-vectorized})
(table.insert tests {:name "colorspacious long conversion paths" :fn cspace-convert-gold-paths})
(table.insert tests {:name "colorspacious CIELab CIELCh with whitepoint" :fn cielab-and-cielch-with-whitepoint})
(table.insert tests {:name "colorspacious CIECAM02 gold and roundtrip" :fn ciecam02-gold-and-roundtrip})
(table.insert tests {:name "colorspacious CIECAM02 subset and cross-vc" :fn ciecam02-subset-and-cross-viewing-condition})
(table.insert tests {:name "colorspacious CAM02 UCS LCD SCD" :fn cam02-ucs-lcd-scd-silver})
(table.insert tests {:name "colorspacious CVD silver and matrix" :fn cvd-silver-and-matrix})
(table.insert tests {:name "colorspacious converter and deltaE" :fn converter-and-deltae})
(table.insert tests {:name "colorspacious error checks" :fn error-checks})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "colorspacious"
                       :tests tests})))

{:name "colorspacious"
 :tests tests
 :main main}
