(local Padding (require :padding))
(local Text (require :text))
(local {: resolve-padding} (require :widget-theme-utils))

(fn Label [opts]
    (local options (or opts {}))
    (local padding (resolve-padding options.padding))

    (fn build [ctx]
        (local text-options {})
        (when (not (= options.text nil))
            (set text-options.text options.text))
        (when (not (= options.codepoints nil))
            (set text-options.codepoints options.codepoints))
        (when (not (= options.style nil))
            (set text-options.style options.style))
        ((Padding {:edge-insets [padding.x padding.y]
                   :child (fn [child-ctx]
                                ((Text text-options) child-ctx))})
         ctx))
    build)

(local exports {:Label Label})

(setmetatable exports {:__call (fn [_ ...]
                                 (Label ...))})

exports
