(local glm (require :glm))
(fn resolve-theme-font [theme key]
  (and theme (. theme key)))

(fn resolve-active-theme []
  (and app
       app.themes
       app.themes.get-active-theme
       (app.themes.get-active-theme)))

(fn resolve-theme-text-color [theme]
  (and theme theme.text (or theme.text.foreground theme.text.color)))

(fn resolve-fonts [opts theme fallback-theme]
  (local options (or opts {}))
  (local base (or options.font
                  (resolve-theme-font theme :font)
                  (resolve-theme-font fallback-theme :font)))
  (local italic (or options.italic-font
                    (resolve-theme-font theme :italic-font)
                    (resolve-theme-font fallback-theme :italic-font)
                    base))
  (local bold (or options.bold-font
                  (resolve-theme-font theme :bold-font)
                  (resolve-theme-font fallback-theme :bold-font)
                  base))
  (local bold-italic
    (or options.bold-italic-font
        (resolve-theme-font theme :bold-italic-font)
        (resolve-theme-font fallback-theme :bold-italic-font)
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
  (local local-theme options.theme)
  (local global-theme (resolve-active-theme))
  (local fonts (resolve-fonts options local-theme global-theme))
  (local theme-color (or (resolve-theme-text-color local-theme)
                         (resolve-theme-text-color global-theme)))
  {:color (or options.color theme-color (glm.vec4 1 0 0 1))
   :scale (or options.scale
              (and local-theme local-theme.text local-theme.text.scale)
              (and global-theme global-theme.text global-theme.text.scale)
              1.6)
   :font fonts.font
   :italic-font fonts.italic-font
   :bold-font fonts.bold-font
   :bold-italic-font fonts.bold-italic-font
   :bold? fonts.bold?
   :italic? fonts.italic?})
