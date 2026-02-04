(local glm (require :glm))
(local QrCode (require :qr-code))
(local Rectangle (require :rectangle))
(local Stack (require :stack))
(local {: Layout : resolve-mark-flag} (require :layout))

(fn build-qr-modules [options ctx]
    (assert ctx "QrCodeModules requires a build context")
    (assert ctx.triangle-vector "QrCodeModules requires ctx.triangle-vector")

    (local module-size (or options.module-size 0.4))
    (local quiet-zone (or options.quiet-zone 4))
    (local color (or options.color (glm.vec4 0 0 0 1)))
    (local allow-empty? (= options.allow-empty? true))

    (var value nil)
    (var qr nil)
    (var module-positions [])
    (var module-count 0)
    (var grid-size 0)
    (var handle nil)
    (var handle-size 0)
    (var visible? true)

    (fn release-handle []
        (when handle
            (when (and ctx ctx.untrack-triangle-handle)
                (ctx:untrack-triangle-handle handle))
            (ctx.triangle-vector:delete handle)
            (set handle nil)
            (set handle-size 0)))

    (fn ensure-handle []
        (if (<= module-count 0)
            (release-handle)
            (do
                (local desired (* module-count 6 8))
                (when (or (not handle) (not (= handle-size desired)))
                    (release-handle)
                    (set handle-size desired)
                    (set handle (ctx.triangle-vector:allocate desired))))))

    (fn rebuild []
        (if value
            (do
                (set qr (QrCode.encode value {:ecc options.ecc}))
                (local size (. qr :size))
                (set grid-size (+ size (* quiet-zone 2)))
                (set module-positions [])
                (for [y 0 (- size 1)]
                    (for [x 0 (- size 1)]
                        (when (qr:get x y)
                            (table.insert module-positions [x y]))))
                (set module-count (# module-positions)))
            (do
                (set qr nil)
                (set module-positions [])
                (set module-count 0)
                (set grid-size 0))))

    (fn measurer [self]
        (if (> grid-size 0)
            (do
                (local dimension (* grid-size module-size))
                (set self.measure (glm.vec3 dimension dimension 0)))
            (set self.measure (glm.vec3 0 0 0))))

    (fn write-vertex [offset position rotation x y depth-index]
        (local point (rotation:rotate (glm.vec3 x y 0)))
        (ctx.triangle-vector:set-glm-vec3 handle offset (+ position point))
        (ctx.triangle-vector:set-glm-vec4 handle (+ offset 3) color)
        (ctx.triangle-vector:set-float handle (+ offset 7) depth-index))

    (fn layouter [self]
        (local should-render (and visible? (not (self:effective-culled?)) (> module-count 0)))
        (if (not should-render)
            (release-handle)
            (do
                (ensure-handle)
                (local depth-index (or self.depth-offset-index 0))
                (local rotation (or self.rotation (glm.quat 1 0 0 0)))
                (local position (or self.position (glm.vec3 0 0 0)))
                (var vertex-index 0)
                (each [_ pos (ipairs module-positions)]
                    (local x (. pos 1))
                    (local y (. pos 2))
                    (local x0 (* (+ quiet-zone x) module-size))
                    (local y0 (* (+ quiet-zone (- (. qr :size) 1 y)) module-size))
                    (local x1 (+ x0 module-size))
                    (local y1 (+ y0 module-size))
                    (local base-offset (* vertex-index 8))
                    (write-vertex base-offset position rotation x0 y0 depth-index)
                    (write-vertex (+ base-offset 8) position rotation x0 y1 depth-index)
                    (write-vertex (+ base-offset 16) position rotation x1 y1 depth-index)
                    (write-vertex (+ base-offset 24) position rotation x1 y1 depth-index)
                    (write-vertex (+ base-offset 32) position rotation x1 y0 depth-index)
                    (write-vertex (+ base-offset 40) position rotation x0 y0 depth-index)
                    (set vertex-index (+ vertex-index 6)))
                (when (and ctx ctx.track-triangle-handle)
                    (ctx:track-triangle-handle handle self.clip-region)))))

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
                (release-handle))
     :set-value set-value
     :get-value get-value
     :set-visible set-visible})

(fn QrCodeModules [opts]
    (local options (or opts {}))
    (fn [ctx]
        (build-qr-modules options ctx)))

(fn build-qr-widget [options ctx]
    (local background-color (or options.background (glm.vec4 1 1 1 1)))
    (local modules-builder
        (QrCodeModules {:value options.value
                        :allow-empty? options.allow-empty?
                        :module-size options.module-size
                        :quiet-zone options.quiet-zone
                        :color (or options.foreground (glm.vec4 0 0 0 1))
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
