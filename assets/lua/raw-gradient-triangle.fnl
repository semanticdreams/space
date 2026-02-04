(local glm (require :glm))

(fn RawGradientTriangle [opts]
  (set opts.position (or opts.position (glm.vec3 0 0 0)))
  (set opts.size (or opts.size (glm.vec2 1.2 1.2)))
  (set opts.rotation (or opts.rotation (glm.quat 1 0 0 0)))
  (set opts.colors (or opts.colors
                       [(glm.vec4 1 0 0 1)
                        (glm.vec4 0 1 0 1)
                        (glm.vec4 0 0 1 1)]))

  (fn build [ctx]
    (assert ctx "RawGradientTriangle requires a build context")
    (assert ctx.triangle-vector "RawGradientTriangle requires triangle vector support")
    (local layout-handle-size (* 8 3))
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
          (local verts [[-0.5 -0.5 0]
                        [0.5 -0.5 0]
                        [0.0 0.5 0]])
          (for [i 1 3]
            (local base (glm.vec3 (table.unpack (. verts i))))
            (local scaled (glm.vec3 (* self.size.x base.x)
                                (* self.size.y base.y)
                                0))
            (local rotated (self.rotation:rotate scaled))
            (ctx.triangle-vector.set-glm-vec3
             ctx.triangle-vector
             handle
             (* (- i 1) 8)
             (+ rotated self.position))
            (ctx.triangle-vector:set-glm-vec4 handle (+ (* (- i 1) 8) 3)
                                              (or (. self.colors i)
                                                  (glm.vec4 1 1 1 1)))
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
     :size opts.size
     :rotation opts.rotation
     :colors opts.colors
     :depth-offset-index 0
     :clip-region nil
     :visible? true
     :set-visible set-visible
     :drop drop}))

RawGradientTriangle
