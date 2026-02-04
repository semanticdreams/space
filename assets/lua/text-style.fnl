(local glm (require :glm))
(fn resolve-theme-font [theme key]
  (and theme (. theme key)))

(fn resolve-fonts [opts theme]
  (local options (or opts {}))
  (local base (or options.font (resolve-theme-font theme :font)))
  (local italic (or options.italic-font (resolve-theme-font theme :italic-font) base))
  (local bold (or options.bold-font (resolve-theme-font theme :bold-font) base))
  (local bold-italic
    (or options.bold-italic-font
        (resolve-theme-font theme :bold-italic-font)
        bold
        italic
        base))
  (local bold? (or options.bold? false))
  (local italic? (or options.italic? false))
  (local resolved
    (if bold?
        (if italic?
            (or bold-italic bold italic base)
            (or bold base))
        (if italic?
            (or italic base)
            base)))
  {:font resolved
   :italic-font italic
   :bold-font bold
   :bold-italic-font bold-italic
   :bold? bold?
   :italic? italic?})

(fn TextStyle [opts]
  (local options (or opts {}))
  (local theme (app.themes.get-active-theme))
  (local fonts (resolve-fonts options theme))
  (local theme-text (and theme theme.text))
  {:color (or options.color (glm.vec4 1 0 0 1))
   :scale (or options.scale (and theme-text theme-text.scale) 1.6)
   :font fonts.font
   :italic-font fonts.italic-font
   :bold-font fonts.bold-font
   :bold-italic-font fonts.bold-italic-font
   :bold? fonts.bold?
   :italic? fonts.italic?})
