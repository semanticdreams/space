(local glm (require :glm))
(local Font (require :font))
(local {: adjust : make-button-variant} (require :widget-theme-utils))

(fn LightTheme []
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
  (local text-color (glm.vec4 0.16 0.18 0.22 1))
  (local secondary-base (glm.vec4 0.88 0.89 0.92 1))
  (local input-base (glm.vec4 0.93 0.94 0.96 1))
  {:name :light
   :font font
   :italic-font italic-font
   :bold-font bold-font
   :bold-italic-font bold-italic-font
   :text {:foreground text-color
          :scale 1.6}
   :list-view {:header {:foreground text-color}}
   :combo-box {:items-per-page 10}
   :graph {:edge-color (glm.vec4 0.25 0.3 0.4 0.85)
           :label-color (glm.vec4 0.3 0.34 0.42 0.95)
           :selection-border-color (glm.vec4 0.18 0.5 0.9 0.9)}
   :skybox {:brightness 0.3}
   :flat-terrain {:dark (glm.vec4 0.86 0.88 0.9 1.0)
                  :light (glm.vec4 0.94 0.95 0.97 1.0)}
   :card {:background (glm.vec4 0.96 0.97 0.98 1)
          :foreground text-color}
   :input {:background input-base
           :hover-background (adjust input-base -0.03)
           :focused-background (adjust input-base -0.05)
           :foreground text-color
           :placeholder (glm.vec4 0.45 0.48 0.52 0.85)
           :caret-normal (glm.vec4 0.85 0.54 0.14 1)
           :caret-insert (glm.vec4 0.14 0.55 0.22 1)
           :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)}
   :button
   {:default-variant :secondary
    :variants
    {:primary (make-button-variant (glm.vec4 0.22 0.46 0.96 1)
                                   {:foreground (glm.vec4 0.98 0.99 1 1)
                                    :hover-delta -0.05
                                    :pressed-delta -0.1
                                    :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)})
     :secondary (make-button-variant secondary-base
                                     {:foreground text-color
                                      :hover-delta -0.03
                                      :pressed-delta -0.07
                                      :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)})
     :success (make-button-variant (glm.vec4 0.2 0.64 0.32 1)
                                   {:foreground (glm.vec4 0.96 0.99 0.97 1)
                                    :hover-delta -0.04
                                    :pressed-delta -0.09})
     :warning (make-button-variant (glm.vec4 0.93 0.65 0.2 1)
                                   {:foreground (glm.vec4 0.2 0.14 0.05 1)
                                    :hover-delta -0.04
                                    :pressed-delta -0.1})
     :danger (make-button-variant (glm.vec4 0.86 0.26 0.3 1)
                                  {:foreground (glm.vec4 1 0.98 0.98 1)
                                   :hover-delta -0.04
                                   :pressed-delta -0.1})}}})

LightTheme
