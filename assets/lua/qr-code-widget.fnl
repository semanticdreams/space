(local gl (require :gl))
(local glm (require :glm))
(local QrCode (require :qr-code))
(local RawImage (require :raw-image))
(local Rectangle (require :rectangle))
(local Stack (require :stack))
(local textures (require :textures))
(local {: resolve-qr-colors} (require :widget-theme-utils))
(local {: Layout : resolve-mark-flag} (require :layout))

(var qr-texture-counter 0)

(fn next-texture-name []
    (set qr-texture-counter (+ qr-texture-counter 1))
    (.. "qr-code-widget/" qr-texture-counter))

(fn clamp-byte [value]
    (local scaled (math.floor (+ 0.5 (* 255 (or value 0)))))
    (math.max 0 (math.min 255 scaled)))

(fn build-qr-pixels [qr quiet-zone grid-size dark-color light-color]
    (local dark-r (clamp-byte dark-color.x))
    (local dark-g (clamp-byte dark-color.y))
    (local dark-b (clamp-byte dark-color.z))
    (local dark-a (clamp-byte dark-color.w))
    (local light-r (clamp-byte light-color.x))
    (local light-g (clamp-byte light-color.y))
    (local light-b (clamp-byte light-color.z))
    (local light-a (clamp-byte light-color.w))
    (local dark (string.char dark-r dark-g dark-b dark-a))
    (local light (string.char light-r light-g light-b light-a))
    (local size (. qr :size))
    (local rows [])
    (for [grid-y 0 (- grid-size 1)]
        (local row [])
        (local qr-y (- grid-y quiet-zone))
        (for [grid-x 0 (- grid-size 1)]
            (local qr-x (- grid-x quiet-zone))
            (if (and (>= qr-x 0)
                     (< qr-x size)
                     (>= qr-y 0)
                     (< qr-y size)
                     (qr:get qr-x qr-y))
                (table.insert row dark)
                (table.insert row light)))
        (table.insert rows (table.concat row)))
    (table.concat rows))

(fn configure-texture [texture]
    (assert texture "QrCodeModules failed to allocate texture")
    (set texture.filterMin gl.GL_NEAREST)
    (set texture.filterMax gl.GL_NEAREST)
    (set texture.wrapS gl.GL_CLAMP_TO_EDGE)
    (set texture.wrapT gl.GL_CLAMP_TO_EDGE))

(fn build-qr-modules [options ctx]
    (assert ctx "QrCodeModules requires a build context")
    (assert ctx.get-image-batch "QrCodeModules requires image batch support")
    (assert textures.load-texture-from-pixels "QrCodeModules requires textures.load-texture-from-pixels")
    (assert textures.get-texture "QrCodeModules requires textures.get-texture")
    (assert textures.drop-texture "QrCodeModules requires textures.drop-texture")

    (local module-size (or options.module-size 0.4))
    (local quiet-zone (or options.quiet-zone 4))
    (local color (or options.color (glm.vec4 0 0 0 1)))
    (local background-color (or options.background-color (glm.vec4 1 1 1 1)))
    (local allow-empty? (= options.allow-empty? true))

    (local texture-name (next-texture-name))
    (local transparent-pixel (string.char 0 0 0 0))
    (var texture (textures.get-texture texture-name))
    (configure-texture texture)
    (set texture (textures.load-texture-from-pixels texture-name 1 1 4 transparent-pixel true))
    (local raw-image ((RawImage {:texture texture}) ctx))

    (var value nil)
    (var grid-size 0)
    (var visible? true)

    (fn rebuild []
        (if value
            (do
                (local qr (QrCode.encode value {:ecc options.ecc}))
                (set grid-size (+ (. qr :size) (* quiet-zone 2)))
                (local pixels (build-qr-pixels qr quiet-zone grid-size color background-color))
                (configure-texture texture)
                (set texture (textures.load-texture-from-pixels texture-name
                                                                grid-size
                                                                grid-size
                                                                4
                                                                pixels))
                (set raw-image.texture texture))
            (set grid-size 0)))

    (fn measurer [self]
        (if (> grid-size 0)
            (do
                (local dimension (* grid-size module-size))
                (set self.measure (glm.vec3 dimension dimension 0)))
            (set self.measure (glm.vec3 0 0 0))))

    (fn layouter [self]
        (local should-render (and visible? (not (self:effective-culled?)) (> grid-size 0)))
        (raw-image:set-visible should-render)
        (when should-render
            (local dimension (* grid-size module-size))
            (set raw-image.size (glm.vec3 dimension dimension 0))
            (set raw-image.position self.position)
            (set raw-image.rotation self.rotation)
            (set raw-image.depth-offset-index (or self.depth-offset-index 0))
            (set raw-image.clip-region self.clip-region)
            (raw-image:update)))

    (local layout
        (Layout {:name (or options.name "qr-code")
                 :measurer measurer
                 :layouter layouter}))

    (fn set-value [_self next-value opts]
        (when (and (not allow-empty?) (= next-value nil))
            (error "QrCodeModules requires a value"))
        (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
        (set value next-value)
        (rebuild)
        (when mark-measure-dirty?
            (layout:mark-measure-dirty)))

    (fn get-value [_self]
        value)

    (fn set-visible [_self next-visible?]
        (set visible? (not (not next-visible?))))

    (set-value nil options.value {:mark-measure-dirty? false})

    {:layout layout
     :drop (fn [_self]
                (layout:drop)
                (raw-image:drop)
                (textures.drop-texture texture-name))
     :set-value set-value
     :get-value get-value
     :set-visible set-visible})

(fn QrCodeModules [opts]
    (local options (or opts {}))
    (fn [ctx]
        (build-qr-modules options ctx)))

(fn build-qr-widget [options ctx]
    (local colors (resolve-qr-colors ctx options))
    (local background-color colors.background)
    (local modules-builder
        (QrCodeModules {:value options.value
                        :allow-empty? options.allow-empty?
                        :module-size options.module-size
                        :quiet-zone options.quiet-zone
                        :color colors.foreground
                        :background-color background-color
                        :ecc options.ecc
                        :name options.name}))
    (local stack-builder
        (Stack {:children [(Rectangle {:color background-color})
                           modules-builder]}))
    (local stack (stack-builder ctx))
    (local modules (. stack.children 2))
    {:layout stack.layout
     :drop (fn [_self]
                (stack:drop))
     :set-value (fn [_self value opts]
                     (modules:set-value value opts))
     :get-value (fn [_self]
                     (modules:get-value))
     :set-visible (fn [_self visible?]
                       (modules:set-visible visible?))})

(fn QrCodeWidget [opts]
    (local options (or opts {}))
    (fn [ctx]
        (build-qr-widget options ctx)))

{:QrCodeWidget QrCodeWidget}
