(local glm (require :glm))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Padding (require :padding))
(local Stack (require :stack))

(local tone-colors
  {:neutral (glm.vec4 0.35 0.38 0.42 1)
   :info (glm.vec4 0.25 0.43 0.96 1)
   :success (glm.vec4 0.17 0.55 0.36 1)
   :warning (glm.vec4 0.85 0.57 0.21 1)
   :danger (glm.vec4 0.78 0.22 0.31 1)})

(local tone-foreground
  {:neutral (glm.vec4 0.92 0.94 0.98 1)
   :info (glm.vec4 0.94 0.95 1 1)
   :success (glm.vec4 0.92 0.98 0.94 1)
   :warning (glm.vec4 0.98 0.95 0.92 1)
   :danger (glm.vec4 0.98 0.92 0.92 1)})

(fn StatusBadge [opts]
  (assert opts.text "StatusBadge requires :text")
  (local initial-tone (or opts.tone :neutral))
  (fn build [ctx]
    (var current-tone initial-tone)
    (var current-text opts.text)

    (fn resolve-color [tone]
      (or opts.color (. tone-colors tone) (. tone-colors :neutral)))

    (fn resolve-foreground [tone]
      (or opts.foreground (. tone-foreground tone) (. tone-foreground :neutral)))

    (local text-style (TextStyle {:color (resolve-foreground current-tone)
                                  :scale (or opts.scale 1.2)}))
    (local text ((Text {:text current-text :style text-style}) ctx))
    (local padded ((Padding {:edge-insets (or opts.padding [0.3 0.15])
                              :child (fn [_ctx] text)})
                   ctx))
    (local rect ((Rectangle {:color (resolve-color current-tone)}) ctx))
    (local stack ((Stack {:children [(fn [_ctx] rect) (fn [_ctx] padded)]})
                  ctx))

    (fn set-tone [_self tone]
      (set current-tone tone)
      (set rect.color (resolve-color current-tone))
      (set text-style.color (resolve-foreground current-tone))
      (text:set-text current-text)
      (when rect.layout
        (rect.layout:mark-layout-dirty)))

    (fn drop [self]
      (self.layout:drop)
      (stack:drop))

    {:layout stack.layout
     :drop drop
     :set-text (fn [_self new-text]
                 (set current-text new-text)
                 (text:set-text current-text))
     :set-tone set-tone}))

StatusBadge
