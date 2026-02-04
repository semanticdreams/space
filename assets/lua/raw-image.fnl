(local glm (require :glm))
(local textures (require :textures))
(fn RawImage [opts]
  (set opts.color (or opts.color (glm.vec4 1 1 1 1)))
  (set opts.position (or opts.position (glm.vec3 0 0 0)))
  (set opts.size (or opts.size (glm.vec3 1 1 0)))
  (set opts.rotation (or opts.rotation (glm.quat 1 0 0 0)))

  (fn build [ctx]
    (assert ctx "RawImage requires a build context")
    (assert ctx.get-image-batch "Context missing image batch support")
    (assert (or opts.texture opts.texture-path)
            "RawImage requires :texture or :texture-path")
    (local texture
      (or opts.texture
          (and opts.texture-path textures textures.load-texture-async
               (textures.load-texture-async
                 (or opts.texture-name opts.texture-path)
                 (if app.engine.get-asset-path
                     (app.engine.get-asset-path opts.texture-path)
                     opts.texture-path)))))
    (assert texture "Failed to resolve texture for RawImage")
    (local batch (ctx:get-image-batch texture))
    (local vector batch.vector)
    (local handle (vector:allocate (* 10 6)))

    (local self {:texture texture
                 :color opts.color
                 :position opts.position
                 :size opts.size
                 :rotation opts.rotation
                 :depth-offset-index 0
                 :clip-region nil
                 :visible? true})
    (var tracked? false)

    (fn untrack []
      (when (and tracked? ctx ctx.untrack-image-handle)
        (ctx:untrack-image-handle batch handle)
        (set tracked? false)))

    (local verts
      [[0 0 0] [1 0 0] [1 1 0]
       [0 0 0] [1 1 0] [0 1 0]])
    (local uvs
      [[0 0] [1 0] [1 1]
       [0 0] [1 1] [0 1]])

    (fn update [this]
      (if (not this.visible?)
          (untrack)
          (do
            (local size (glm.vec3 this.size.x this.size.y this.size.z))
            (for [i 1 6]
              (local base (glm.vec3 (table.unpack (. verts i))))
              (local scaled
                    (glm.vec3 (* size.x base.x)
                          (* size.y base.y)
                          (* size.z base.z)))
              (local rotated (this.rotation:rotate scaled))
              (vector.set-glm-vec3
               vector
               handle
               (* (- i 1) 10)
               (+ rotated this.position))
              (vector.set-glm-vec2
               vector
               handle
               (+ (* (- i 1) 10) 3)
               (glm.vec2 (table.unpack (. uvs i))))
              (vector.set-glm-vec4
               vector
               handle
               (+ (* (- i 1) 10) 5)
               this.color)
              (vector:set-float handle (+ (* (- i 1) 10) 9) this.depth-offset-index))
            (when (and ctx ctx.track-image-handle)
              (ctx:track-image-handle batch handle this.clip-region)
              (set tracked? true)))))

    (fn set-visible [this visible?]
      (local desired (not (not visible?)))
      (when (not (= desired this.visible?))
        (set this.visible? desired)
        (when (not desired)
          (untrack))))

    (fn drop [_this]
      (untrack)
      (vector:delete handle))

    (set self.update update)
    (set self.drop drop)
    (set self.set-visible set-visible)
    self))
