(local glm (require :glm))
(local colors (require :colors))

(local default-ciecam-space-value (colors.ciecam02-space))
(local cam02-ucs-space (colors.cam02-space "cam02-ucs"))
(local cam02-lcd-space (colors.cam02-space "cam02-lcd"))
(local cam02-scd-space (colors.cam02-space "cam02-scd"))
(local ciecam-axes-set {:J true :C true :h true :Q true :M true :s true :H true})

(fn copy-table [src]
  (local out {})
  (when src
    (each [k v (pairs src)]
      (tset out k v)))
  out)

(fn merge-table [base overlay]
  (local out (copy-table base))
  (when overlay
    (each [k v (pairs overlay)]
      (tset out k v)))
  out)

(fn vec3-like? [value]
  (and value value.x value.y value.z))

(fn numeric-list? [value]
  (if (not (= (type value) :table))
      false
      (do
        (local n (# value))
        (if (= n 0)
            false
            (do
              (var ok true)
              (for [i 1 n]
                (when (not (= (type (. value i)) :number))
                  (set ok false)))
              ok)))))

(fn numeric-list-of-dim? [value dim]
  (and (= (type value) :table)
       (= (# value) dim)
       (numeric-list? value)))

(fn to-vec3 [value]
  (if (vec3-like? value)
      value
      (if (numeric-list-of-dim? value 3)
          (glm.vec3 (. value 1) (. value 2) (. value 3))
          (error "expected vec3-like value"))))

(fn vec3-to-list [value]
  [value.x value.y value.z])

(fn ciecam-axes? [value]
  (if (or (not (= (type value) :string)) (= (# value) 0))
      false
      (do
        (var ok true)
        (for [i 1 (# value)]
          (local ch (string.sub value i i))
          (when (not (. ciecam-axes-set ch))
            (set ok false)))
        ok)))

(local CIECAM02Surround
  (setmetatable {}
                {:__call (fn [_ F c N_c]
                           {:__kind "CIECAM02Surround"
                            :F F
                            :c c
                            :N_c N_c})}))

(tset CIECAM02Surround :AVERAGE (CIECAM02Surround 1.0 0.69 1.0))
(tset CIECAM02Surround :DIM (CIECAM02Surround 0.9 0.59 0.9))
(tset CIECAM02Surround :DARK (CIECAM02Surround 0.8 0.525 0.8))

(fn standard_illuminant_XYZ100 [name ?observer]
  (local observer (or ?observer "CIE 1931 2 deg"))
  (if (= observer "CIE 1931 2 deg")
      (colors.get-illuminant "2" name)
      (= observer "CIE 1964 10 deg")
      (colors.get-illuminant "10" name)
      (error (.. "observer must be 'CIE 1931 2 deg' or 'CIE 1964 10 deg', not " observer))))

(fn as_XYZ100_w [whitepoint]
  (if (= (type whitepoint) :string)
      (standard_illuminant_XYZ100 whitepoint)
      (to-vec3 whitepoint)))

(local CIECAM02Space
  (setmetatable {}
                {:__call (fn [_ XYZ100_w Y_b L_A ?surround]
                           (local surround (or ?surround CIECAM02Surround.AVERAGE))
                           {:__kind "CIECAM02Space"
                            :XYZ100_w (as_XYZ100_w XYZ100_w)
                            :Y_b Y_b
                            :L_A L_A
                            :surround {:F surround.F :c surround.c :N_c surround.N_c}})}))

(tset CIECAM02Space :sRGB
      (CIECAM02Space "D65" 20 (/ (/ 64 math.pi) 5) CIECAM02Surround.AVERAGE))

(local LuoEtAl2006UniformSpace
  (setmetatable {}
                {:__call (fn [_ KL c1 c2]
                           {:__kind "LuoEtAl2006UniformSpace"
                            :KL KL
                            :c1 c1
                            :c2 c2})}))

(local CAM02UCS (LuoEtAl2006UniformSpace 1.00 0.007 0.0228))
(local CAM02LCD (LuoEtAl2006UniformSpace 0.77 0.007 0.0053))
(local CAM02SCD (LuoEtAl2006UniformSpace 1.24 0.007 0.0363))

(fn default-ciecam-space []
  (copy-table default-ciecam-space-value))

(fn default-cielab-spec [name]
  {:name name
   :XYZ100_w CIECAM02Space.sRGB.XYZ100_w})

(fn alias-spec [name]
  (if (= name "CAM02-UCS")
      {:name "J'a'b'"
       :ciecam02_space CIECAM02Space.sRGB
       :luoetal2006_space CAM02UCS}
      (= name "CAM02-LCD")
      {:name "J'a'b'"
       :ciecam02_space CIECAM02Space.sRGB
       :luoetal2006_space CAM02LCD}
      (= name "CAM02-SCD")
      {:name "J'a'b'"
       :ciecam02_space CIECAM02Space.sRGB
       :luoetal2006_space CAM02SCD}
      (= name "CIECAM02")
      {:name "CIECAM02"
       :ciecam02_space CIECAM02Space.sRGB}
      (= name "CIELab")
      (default-cielab-spec "CIELab")
      (= name "CIELCh")
      (default-cielab-spec "CIELCh")
      nil))

(fn normalize-ciecam-space [value]
  (if (and (= (type value) :table) (= value.__kind "CIECAM02Space"))
      {:XYZ100_w (as_XYZ100_w value.XYZ100_w)
       :Y_b value.Y_b
       :L_A value.L_A
       :surround (copy-table value.surround)}
      (= (type value) :table)
      (if value.XYZ100_w
          {:XYZ100_w (as_XYZ100_w value.XYZ100_w)
           :Y_b value.Y_b
           :L_A value.L_A
           :surround (copy-table (or value.surround {:F value.F :c value.c :N_c value.N_c}))}
          (default-ciecam-space))
      (default-ciecam-space)))

(fn normalize-luo-space [value]
  (if (and (= (type value) :table) (= value.__kind "LuoEtAl2006UniformSpace"))
      {:KL value.KL :c1 value.c1 :c2 value.c2}
      (= (type value) :table)
      {:KL value.KL :c1 value.c1 :c2 value.c2}
      (= (type value) :string)
      (if (= value "CAM02-UCS")
          {:KL CAM02UCS.KL :c1 CAM02UCS.c1 :c2 CAM02UCS.c2}
          (= value "CAM02-LCD")
          {:KL CAM02LCD.KL :c1 CAM02LCD.c1 :c2 CAM02LCD.c2}
          (= value "CAM02-SCD")
          {:KL CAM02SCD.KL :c1 CAM02SCD.c1 :c2 CAM02SCD.c2}
          (error (.. "unknown LuoEtAl2006 space " value)))
      {:KL CAM02UCS.KL :c1 CAM02UCS.c1 :c2 CAM02UCS.c2}))

(fn normalize-space [space]
  (if (= (type space) :string)
      (do
        (local alias (alias-spec space))
        (if alias
            alias
            (if (ciecam-axes? space)
                {:name "CIECAM02-subset"
                 :ciecam02_space CIECAM02Space.sRGB
                 :axes space}
                {:name space})))
      (= (type space) :table)
      (if (= space.__kind "CIECAM02Space")
          {:name "CIECAM02"
           :ciecam02_space space}
          (= space.__kind "LuoEtAl2006UniformSpace")
          {:name "J'a'b'"
           :ciecam02_space CIECAM02Space.sRGB
           :luoetal2006_space space}
          (do
            (local name (. space :name))
            (if (not name)
                space
                (do
                  (local alias (alias-spec name))
                  (if alias
                      (do
                        (local overlay (copy-table space))
                        (tset overlay :name nil)
                        (merge-table alias overlay))
                      space)))))
      (error (.. "unrecognized color space " (tostring space)))))

(fn canonical-space [space]
  (local spec (normalize-space space))
  (local out (copy-table spec))
  (when out.ciecam02_space
    (tset out :ciecam02_space (normalize-ciecam-space out.ciecam02_space)))
  (when out.luoetal2006_space
    (tset out :luoetal2006_space (normalize-luo-space out.luoetal2006_space)))
  (when (and (= out.name "CIECAM02") (not out.ciecam02_space))
    (tset out :ciecam02_space (default-ciecam-space)))
  (when (and (= out.name "CIECAM02-subset") (not out.ciecam02_space))
    (tset out :ciecam02_space (default-ciecam-space)))
  (when (and (= out.name "J'a'b'") (not out.ciecam02_space))
    (tset out :ciecam02_space CIECAM02Space.sRGB))
  (when (and (= out.name "J'a'b'") (not out.luoetal2006_space))
    (tset out :luoetal2006_space CAM02UCS))
  (when (and (= out.name "CIELab") (not out.XYZ100_w))
    (tset out :XYZ100_w CIECAM02Space.sRGB.XYZ100_w))
  (when (and (= out.name "CIELCh") (not out.XYZ100_w))
    (tset out :XYZ100_w CIECAM02Space.sRGB.XYZ100_w))
  out)

(fn source-dimension [spec]
  (if (= spec.name "CIECAM02-subset")
      (# spec.axes)
      3))

(fn ciecam-dict? [value]
  (and (= (type value) :table)
       (or value.J value.Q)
       (or value.C value.M value.s)
       (or value.h value.H)))

(fn source-point? [value spec]
  (if (= spec.name "CIECAM02")
      (ciecam-dict? value)
      (if (= spec.name "CIECAM02-subset")
          (or (numeric-list-of-dim? value (source-dimension spec))
              (vec3-like? value))
          (or (vec3-like? value)
              (numeric-list-of-dim? value (source-dimension spec))))))

(fn batch-value? [value spec]
  (and (= (type value) :table)
       (> (# value) 0)
       (not (source-point? value spec))))

(fn srgb-channel->linear [c]
  (if (< c 0.04045)
      (/ c 12.92)
      (^ (/ (+ c 0.055) 1.055) 2.4)))

(fn linear-channel->srgb [c]
  (if (<= c 0.0031308)
      (* c 12.92)
      (- (* 1.055 (^ c (/ 1 2.4))) 0.055)))

(fn srgb1->srgb1-linear [rgb]
  (local c (to-vec3 rgb))
  (glm.vec3 (srgb-channel->linear c.x)
            (srgb-channel->linear c.y)
            (srgb-channel->linear c.z)))

(fn srgb1-linear->srgb1 [rgb]
  (local c (to-vec3 rgb))
  (glm.vec3 (linear-channel->srgb c.x)
            (linear-channel->srgb c.y)
            (linear-channel->srgb c.z)))

(fn ciecam-subset->table [axes subset-values]
  (local t {})
  (for [i 1 (# axes)]
    (local axis (string.sub axes i i))
    (local component
      (if (vec3-like? subset-values)
          (if (= i 1)
              subset-values.x
              (= i 2)
              subset-values.y
              subset-values.z)
          (. subset-values i)))
    (tset t axis component))
  t)

(fn ciecam-table->subset [axes ciecam]
  (local out [])
  (for [i 1 (# axes)]
    (local axis (string.sub axes i i))
    (table.insert out (. ciecam axis)))
  out)

(fn to-xyz100 [value spec]
  (if (= spec.name "sRGB1")
      (colors.rgb-to-xyz (to-vec3 value))
      (= spec.name "sRGB255")
      (to-xyz100 (glm.vec3 (/ (. value 1) 255.0)
                           (/ (. value 2) 255.0)
                           (/ (. value 3) 255.0))
                 {:name "sRGB1"})
      (= spec.name "sRGB1-linear")
      (colors.rgb-to-xyz (srgb1-linear->srgb1 value))
      (= spec.name "sRGB1-linear+CVD")
      (to-xyz100 (colors.cvd-forward (to-vec3 value) spec.cvd_type spec.severity) {:name "sRGB1-linear"})
      (= spec.name "sRGB1+CVD")
      (to-xyz100 (srgb1->srgb1-linear value) (merge-table spec {:name "sRGB1-linear+CVD"}))
      (= spec.name "XYZ100")
      (to-vec3 value)
      (= spec.name "XYZ1")
      (* (to-vec3 value) 100.0)
      (= spec.name "xyY1")
      (* (colors.xyy-to-xyz (to-vec3 value)) 100.0)
      (= spec.name "xyY100")
      (colors.xyy-to-xyz (to-vec3 value))
      (= spec.name "CIELab")
      (colors.lab-to-xyz (to-vec3 value) "2" (if (= (type spec.XYZ100_w) :string) spec.XYZ100_w "D65"))
      (= spec.name "CIELCh")
      (to-xyz100 (colors.lchab-to-lab (to-vec3 value)) (merge-table spec {:name "CIELab"}))
      (= spec.name "CIECAM02")
      (colors.ciecam02-to-xyz100 value spec.ciecam02_space)
      (= spec.name "CIECAM02-subset")
      (to-xyz100 (ciecam-subset->table spec.axes value) {:name "CIECAM02" :ciecam02_space spec.ciecam02_space})
      (= spec.name "J'a'b'")
      (to-xyz100 (colors.jab-to-jmh (to-vec3 value) spec.luoetal2006_space)
                 {:name "CIECAM02-subset" :axes "JMh" :ciecam02_space spec.ciecam02_space})
      (error (.. "unsupported source space " (tostring spec.name)))))

(fn from-xyz100 [xyz100 spec]
  (if (= spec.name "sRGB1")
      (colors.xyz-to-rgb xyz100)
      (= spec.name "sRGB255")
      (vec3-to-list (* 255.0 (from-xyz100 xyz100 {:name "sRGB1"})))
      (= spec.name "sRGB1-linear")
      (srgb1->srgb1-linear (from-xyz100 xyz100 {:name "sRGB1"}))
      (= spec.name "sRGB1-linear+CVD")
      (colors.cvd-inverse (from-xyz100 xyz100 {:name "sRGB1-linear"}) spec.cvd_type spec.severity)
      (= spec.name "sRGB1+CVD")
      (srgb1-linear->srgb1 (from-xyz100 xyz100 (merge-table spec {:name "sRGB1-linear+CVD"})))
      (= spec.name "XYZ100")
      xyz100
      (= spec.name "XYZ1")
      (/ xyz100 100.0)
      (= spec.name "xyY1")
      (do
        (local xyy100 (colors.xyz-to-xyy xyz100))
        (glm.vec3 xyy100.x xyy100.y (/ xyy100.z 100.0)))
      (= spec.name "xyY100")
      (colors.xyz-to-xyy xyz100)
      (= spec.name "CIELab")
      (colors.xyz-to-lab xyz100 "2" (if (= (type spec.XYZ100_w) :string) spec.XYZ100_w "D65"))
      (= spec.name "CIELCh")
      (colors.lab-to-lchab (from-xyz100 xyz100 (merge-table spec {:name "CIELab"})))
      (= spec.name "CIECAM02")
      (colors.xyz100-to-ciecam02 xyz100 spec.ciecam02_space)
      (= spec.name "CIECAM02-subset")
      (ciecam-table->subset spec.axes (from-xyz100 xyz100 {:name "CIECAM02" :ciecam02_space spec.ciecam02_space}))
      (= spec.name "J'a'b'")
      (colors.jmh-to-jab
        (to-vec3 (from-xyz100 xyz100 {:name "CIECAM02-subset" :axes "JMh" :ciecam02_space spec.ciecam02_space}))
        spec.luoetal2006_space)
      (error (.. "unsupported target space " (tostring spec.name)))))

(fn convert-one [value start-spec end-spec]
  (local xyz100 (to-xyz100 value start-spec))
  (from-xyz100 xyz100 end-spec))

(fn convert-batch [value start-spec end-spec]
  (if (batch-value? value start-spec)
      (do
        (local out [])
        (for [i 1 (# value)]
          (table.insert out (convert-batch (. value i) start-spec end-spec)))
        out)
      (convert-one value start-spec end-spec)))

(fn cspace_convert [value start-space end-space]
  (local start-spec (canonical-space start-space))
  (local end-spec (canonical-space end-space))
  (convert-batch value start-spec end-spec))

(fn cspace_converter [start-space end-space]
  (local start-spec (canonical-space start-space))
  (local end-spec (canonical-space end-space))
  (fn [value]
    (convert-batch value start-spec end-spec)))

(fn vec-distance [a b]
  (local va (to-vec3 a))
  (local vb (to-vec3 b))
  (local dx (- va.x vb.x))
  (local dy (- va.y vb.y))
  (local dz (- va.z vb.z))
  (math.sqrt (+ (* dx dx) (* dy dy) (* dz dz))))

(fn deltaE [color1 color2 ?input-space ?uniform-space]
  (local input-space (or ?input-space "sRGB1"))
  (local uniform-space (or ?uniform-space "CAM02-UCS"))
  (local uniform1 (cspace_convert color1 input-space uniform-space))
  (local uniform2 (cspace_convert color2 input-space uniform-space))
  (if (and (= (type uniform1) :table)
           (= (type uniform2) :table)
           (> (# uniform1) 0)
           (> (# uniform2) 0)
           (not (vec3-like? uniform1)))
      (do
        (assert (= (# uniform1) (# uniform2)) "deltaE vectorized inputs must have same length")
        (local out [])
        (for [i 1 (# uniform1)]
          (table.insert out (deltaE (. uniform1 i) (. uniform2 i) "J'a'b'" "J'a'b'")))
        out)
      (vec-distance uniform1 uniform2)))

(local NegativeAError {:name "NegativeAError"})

(fn JChQMsH [table-value]
  table-value)

{:CIECAM02Surround CIECAM02Surround
 :CIECAM02Space CIECAM02Space
 :NegativeAError NegativeAError
 :JChQMsH JChQMsH
 :LuoEtAl2006UniformSpace LuoEtAl2006UniformSpace
 :CAM02UCS CAM02UCS
 :CAM02LCD CAM02LCD
 :CAM02SCD CAM02SCD
 :standard_illuminant_XYZ100 standard_illuminant_XYZ100
 :as_XYZ100_w as_XYZ100_w
 :machado_et_al_2009_matrix colors.machado-et-al-2009-matrix
 :cspace_converter cspace_converter
 :cspace_convert cspace_convert
 :deltaE deltaE
 :normalize-space canonical-space
 :cspace-converter cspace_converter
 :cspace-convert cspace_convert
 :delta-e deltaE}
