(local glm (require :glm))
(local Stack (require :stack))
(local Rectangle (require :rectangle))

(local colors (require :colors))
(fn get-theme-card-colors [ctx]
  (local theme (and ctx ctx.theme))
  (and theme theme.card))

(fn resolve-card-colors [ctx opts]
  (local theme-colors (get-theme-card-colors ctx))
  (local background
    (or opts.color
        opts.background-color
        (and theme-colors theme-colors.background)
        (glm.vec4 0.15 0.15 0.18 1)))
  (local foreground
    (or opts.foreground-color
        (and theme-colors theme-colors.foreground)
        (glm.vec4 0.95 0.95 0.95 1)))
  {:background background
   :foreground foreground})

(fn Card [opts]
  (assert opts.child "Card requires :child")
  (local options (or opts {}))
  (fn build [ctx]
    (local colors (resolve-card-colors ctx options))
    (local rectangle-builder (Rectangle {:color colors.background}))
    (local stack-builder
      (Stack {:children
              [rectangle-builder
               options.child]}))
    (local stack (stack-builder ctx))
    (set stack.background-color colors.background)
    (set stack.foreground-color colors.foreground)
    stack)
  build)

Card
