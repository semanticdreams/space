(local Stack (require :stack))
(local Rectangle (require :rectangle))
(local {: resolve-card-colors} (require :widget-theme-utils))

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
