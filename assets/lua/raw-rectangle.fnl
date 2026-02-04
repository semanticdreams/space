(local glm (require :glm))
(fn RawRectangle [opts]
  (set opts.color (or opts.color (glm.vec4 1 0 0 1)))
  (set opts.position (or opts.position (glm.vec3 0)))
  (set opts.size (or opts.size (glm.vec2 10)))
  (set opts.rotation (or opts.rotation (glm.quat 1 0 0 0)))

  (fn build [ctx]
    (local layout-handle-size (* 8 3 2))
    (var handle (ctx.triangle-vector:allocate layout-handle-size))

    (fn ensure-handle []
      (when (not handle)
        (set handle (ctx.triangle-vector:allocate layout-handle-size))))

    (fn release-handle []
      (when handle
        (when (and ctx ctx.untrack-triangle-handle)
          (ctx:untrack-triangle-handle handle))
        (ctx.triangle-vector:delete handle)
        (set handle nil)))

    (fn update [self]
      (if
        (not self.visible?) (release-handle)
        (do
          (ensure-handle)
          (local verts [[0 0 0] [0 self.size.y 0] [self.size.x self.size.y 0]
                        [self.size.x self.size.y 0] [self.size.x 0 0] [0 0 0]])
          (for [i 1 6]
            (ctx.triangle-vector.set-glm-vec3
             ctx.triangle-vector
             handle
             (* (- i 1) 8)
             (+ (self.rotation:rotate (glm.vec3 (table.unpack (. verts i))))
                self.position))
            (ctx.triangle-vector:set-glm-vec4 handle (+ (* (- i 1) 8) 3) self.color)
            (ctx.triangle-vector:set-float handle (+ (* (- i 1) 8) 7) self.depth-offset-index))
          (when (and ctx ctx.track-triangle-handle)
            (ctx:track-triangle-handle handle self.clip-region)))))

    (fn set-visible [self visible?]
      (local desired (not (not visible?)))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (if desired
            (ensure-handle)
            (release-handle))))

    (fn drop [_self]
      (release-handle))

    {: update
     :position opts.position
     :color opts.color
     :size opts.size
     :rotation opts.rotation
     :depth-offset-index 0
     :clip-region nil
     :visible? true
     :set-visible set-visible
     : drop}
    ))
