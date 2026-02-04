(fn ensure-function [value label]
  (when (not (= (type value) "function"))
    (error (.. label " must be a function")))
  value)

(fn Themes []
  (local builders {})
  (var current nil)
  (var current-name nil)

  (fn add-theme [name builder]
    (assert name "Themes.add-theme requires a name")
    (assert builder "Themes.add-theme requires a builder function")
    (ensure-function builder "Theme builder")
    (set (. builders name) builder))

  (fn set-theme [name]
    (local builder (. builders name))
    (assert builder (.. "Theme " name " is not registered"))
    (local instance (builder))
    (when (and current current.drop)
      (current:drop))
    (set current instance)
    (set current-name name)
    instance)

  (fn get-active-theme []
    current)

  (fn get-active-theme-name []
    current-name)

  (fn list-themes []
    (local names [])
    (each [k _ (pairs builders)]
      (table.insert names k))
    names)

  (fn get-button-colors [variant]
    (when current
      (local button current.button)
      (when button
        (local variants (or button.variants {}))
        (local fallback (or button.default-variant :secondary))
        (local key (or variant fallback))
        (or (. variants key)
            (. variants fallback)
            variants.secondary))))

  {:add-theme add-theme
   :set-theme set-theme
   :get-active-theme get-active-theme
   :get-active-theme-name get-active-theme-name
   :get-button-colors get-button-colors
   :list-themes list-themes})

Themes
