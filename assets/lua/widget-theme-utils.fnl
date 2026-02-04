(local glm (require :glm))
(local colors (require :colors))
(fn clamp01 [value]
  (math.max 0 (math.min 1 value)))

(fn adjust [color delta]
  (glm.vec4 (clamp01 (+ color.x delta))
        (clamp01 (+ color.y delta))
        (clamp01 (+ color.z delta))
        color.w))

(fn make-button-variant [base opts]
  (local options (or opts {}))
  (local hover-delta (or options.hover-delta 0.05))
  (local pressed-delta (or options.pressed-delta -0.07))
  (local focus-outline (or options.focus-outline (glm.vec4 0.9 0.52 0.12 0.9)))
  {:background base
   :foreground (or options.foreground (glm.vec4 0.94 0.95 0.97 1))
   :hover-background (adjust base hover-delta)
   :pressed-background (adjust base pressed-delta)
   :focus-outline focus-outline})

(fn get-input-theme [ctx]
  (local theme (and ctx ctx.theme))
  (and theme theme.input))

(fn resolve-input-colors [ctx opts]
  (local options (or opts {}))
  (local theme (get-input-theme ctx))
  (local base (or options.background-color
                  (and theme theme.background)
                  (glm.vec4 0.12 0.14 0.18 0.98)))
  (local foreground (or options.foreground-color
                        (and theme theme.foreground)
                        (glm.vec4 0.92 0.94 0.97 1)))
  (local hover (or options.hover-background-color
                   (and theme theme.hover-background)
                   (adjust base 0.04)))
  (local focused (or options.focused-background-color
                     (and theme theme.focused-background)
                     (adjust base 0.06)))
  (local placeholder (or options.placeholder-color
                         (and theme theme.placeholder)
                         (glm.vec4 0.56 0.58 0.62 0.85)))
  (local caret-normal (or options.caret-normal-color
                          (and theme theme.caret-normal)
                          (glm.vec4 0.89 0.78 0.37 1)))
  (local caret-insert (or options.caret-insert-color
                          (and theme theme.caret-insert)
                          (glm.vec4 0.32 0.69 0.38 1)))
  (local focus-outline (or options.focus-outline-color
                           (and theme theme.focus-outline)
                           (glm.vec4 0.9 0.52 0.12 0.9)))
  {:background base
   :hover-background hover
   :focused-background focused
   :foreground foreground
   :placeholder placeholder
   :caret-normal caret-normal
   :caret-insert caret-insert
   :focus-outline focus-outline})

(fn resolve-padding [value]
  (if (not value)
      {:x 0.45 :y 0.35}
      (let [kind (type value)]
        (if (= kind "number")
            {:x value :y value}
            (if (= kind "table")
                (let [first (or (. value 1) value.x value.horizontal)
                      second (or (. value 2) value.y value.vertical first)]
                  {:x (or first 0.45)
                   :y (or second 0.35)})
                {:x 0.45 :y 0.35})))))

(fn get-button-theme-colors [ctx variant]
  (local theme (and ctx ctx.theme))
  (local button-theme (and theme theme.button))
  (when button-theme
    (local variants (or button-theme.variants {}))
    (local fallback (or button-theme.default-variant :secondary))
    (local key (or variant fallback))
    (or (. variants key)
        (. variants fallback)
        variants.secondary)))

(fn resolve-button-colors [ctx options]
  (local theme (and ctx ctx.theme))
  (local button-theme (and theme theme.button))
  (local variant (or options.variant
                     (and button-theme button-theme.default-variant)
                     :secondary))
  (local theme-colors (get-button-theme-colors ctx variant))
  (local background
    (or options.background-color
        (and theme-colors theme-colors.background)
        (glm.vec4 0.2 0.2 0.2 1)))
  (local hover
    (or options.hover-background-color
        (and theme-colors theme-colors.hover-background)
        (adjust background 0.08)))
  (local pressed
    (or options.pressed-background-color
        (and theme-colors theme-colors.pressed-background)
        (adjust background -0.12)))
  (local foreground
    (or options.foreground-color
        (and theme-colors theme-colors.foreground)
        (glm.vec4 0.95 0.95 0.95 1)))
  (local focus-outline
    (or options.focus-outline-color
        (and theme-colors theme-colors.focus-outline)
        (glm.vec4 0.9 0.52 0.12 0.9)))
 {:background background
   :hover hover
   :pressed pressed
   :foreground foreground
   :focus-outline focus-outline
   :variant variant})

{:clamp01 clamp01
 :adjust adjust
 :make-button-variant make-button-variant
 :resolve-input-colors resolve-input-colors
 :resolve-padding resolve-padding
 :get-button-theme-colors get-button-theme-colors
 :resolve-button-colors resolve-button-colors}
