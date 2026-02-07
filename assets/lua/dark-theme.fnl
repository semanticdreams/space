(local glm (require :glm))
(local Font (require :font))
(local {: adjust : make-button-variant} (require :widget-theme-utils))

(local terrain-center (glm.vec3 0 -100 0))
(local light-position (glm.vec3 200 200 200))
(local light-direction (glm.normalize (- light-position terrain-center)))

(fn DarkTheme []
  (local font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-R.json"
                     :texture-path "ubuntu-font/msdf/UbuntuMono-R.png"
                     :texture-name "font-UbuntuMono-R"}))
  (local italic-font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-RI.json"
                            :texture-path "ubuntu-font/msdf/UbuntuMono-RI.png"
                            :texture-name "font-UbuntuMono-RI"}))
  (local bold-font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-B.json"
                          :texture-path "ubuntu-font/msdf/UbuntuMono-B.png"
                          :texture-name "font-UbuntuMono-B"}))
  (local bold-italic-font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-BI.json"
                                 :texture-path "ubuntu-font/msdf/UbuntuMono-BI.png"
                                 :texture-name "font-UbuntuMono-BI"}))
  (local text-color (glm.vec4 0.92 0.94 0.98 1))
  (local secondary-base (glm.vec4 0.17 0.21 0.31 1))
  (local input-base (glm.vec4 0.12 0.15 0.2 0.95))
  {:name :dark
   :font font
   :italic-font italic-font
   :bold-font bold-font
   :bold-italic-font bold-italic-font
   :text {:foreground text-color
          :scale 1.6}
   :list-view {:header {:foreground text-color}}
   :combo-box {:items-per-page 10}
   :graph {:edge-color (glm.vec4 0.36 0.45 0.68 0.9)
           :label-color text-color
           :selection-border-color (glm.vec4 0.2 0.55 0.95 0.95)}
   :lights {:ambient (glm.vec3 0 0 0)
            :directional [{:direction light-direction
                           :ambient (glm.vec3 0.6 0.6 0.6)
                           :diffuse (glm.vec3 0.9 0.9 0.9)
                           :specular (glm.vec3 1.1 1.1 1.1)}]
            :point [{:enabled? false
                     :position (glm.vec3 0 0 0)
                     :ambient (glm.vec3 0.0 0.0 0.0)
                     :diffuse (glm.vec3 1.0 1.0 1.0)
                     :specular (glm.vec3 1.0 1.0 1.0)
                     :constant 1.0
                     :linear 0.09
                     :quadratic 0.032}]
            :spot [{:enabled? false
                    :position (glm.vec3 0 0 0)
                    :direction (glm.vec3 0 0 -1)
                    :ambient (glm.vec3 0.0 0.0 0.0)
                    :diffuse (glm.vec3 1.0 1.0 1.0)
                    :specular (glm.vec3 1.0 1.0 1.0)
                    :cutoff (math.cos (math.rad 12.5))
                    :outer-cutoff (math.cos (math.rad 17.5))
                    :constant 1.0
                    :linear 0.09
                    :quadratic 0.032}]}
   :skybox {:brightness -0.8}
   :flat-terrain {:dark (glm.vec4 0.12 0.14 0.18 1.0)
                  :light (glm.vec4 0.18 0.21 0.27 1.0)}
   :card {:background (glm.vec4 0.12 0.13 0.18 1)
          :foreground text-color}
   :input {:background input-base
           :hover-background (adjust input-base 0.04)
           :focused-background (adjust input-base 0.06)
           :foreground text-color
           :placeholder (glm.vec4 0.58 0.62 0.72 0.85)
           :caret-normal (glm.vec4 0.95 0.73 0.31 1)
           :caret-insert (glm.vec4 0.32 0.69 0.38 1)
           :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)}
   :button
   {:default-variant :secondary
    :variants
    {:primary (make-button-variant (glm.vec4 0.25 0.43 0.96 1))
     :secondary (make-button-variant secondary-base)
     :success (make-button-variant (glm.vec4 0.17 0.55 0.36 1))
     :warning (make-button-variant (glm.vec4 0.85 0.57 0.21 1))
     :danger (make-button-variant (glm.vec4 0.78 0.22 0.31 1))}}})

DarkTheme
