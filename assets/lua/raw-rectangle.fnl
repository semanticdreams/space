(fn RawRectangle [opts]
  (set opts.color (or opts.color (glm.vec4:new 1 0 0 1)))
  (set opts.position (or opts.position (glm.vec3:new 0)))
  (set opts.size (or opts.size (glm.vec2:new 10)))
  (set opts.rotation (or opts.rotation (glm.quat:new 1 0 0 0)))
  (set opts.depth-offset-index (or opts.depth-offset-index 0))

  (fn build [ctx]
    (local handle (ctx.triangle-vector:allocate (* 8 3 2)))

    (fn update [self]
      (local verts [[0 0 0] [0 self.size.y 0] [self.size.x self.size.y 0]
                    [self.size.x self.size.y 0] [self.size.x 0 0] [0 0 0]])
      (for [i 1 6]
        (ctx.triangle-vector:set_vec3
          handle
          (* (- i 1) 8)
          (+ (self.rotation:rotate (glm.vec3:new (table.unpack (. verts i))))
             self.position))
        (ctx.triangle-vector:set_vec4 handle (+ (* (- i 1) 8) 3) self.color)
        (ctx.triangle-vector:set_float handle (+ (* (- i 1) 8) 7) self.depth-offset-index)
        )
      )

    (fn drop [self]
      (ctx.triangle-vector:delete handle))

    {: update
     :position opts.position
     :color opts.color
     :size opts.size
     :rotation opts.rotation
     :depth-offset-index opts.depth-offset-index
     : drop}
    ))
