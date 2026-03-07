(local glm (require :glm))
(local glm-mat4-trs (. glm :mat4-trs))
(local glm-mat4-world-to-render (. glm :mat4-world-to-render))

(fn rect-matrix [position rotation size]
  (local world (glm-mat4-trs position.x
                             position.y
                             position.z
                             rotation))
  (glm-mat4-world-to-render world size.x size.y 1))

(fn RawRectangle [opts]
  (set opts.color (or opts.color (glm.vec4 1 0 0 1)))
  (set opts.position (or opts.position (glm.vec3 0)))
  (set opts.size (or opts.size (glm.vec2 10)))
  (set opts.rotation (or opts.rotation (glm.quat 1 0 0 0)))

  (fn build [ctx]
    (assert (and ctx ctx.get-rectangle-quad-batcher)
            "RawRectangle requires ctx.get-rectangle-quad-batcher")
    (local quad-batcher (ctx:get-rectangle-quad-batcher))
    (local key {})

    (fn remove-quad []
      (quad-batcher:remove-quad key))

    (fn update [self]
      (if (not self.visible?)
          (remove-quad)
          (quad-batcher:upsert-quad key
                                    {:matrix (rect-matrix self.position self.rotation self.size)
                                     :color self.color
                                     :depth-offset self.depth-offset-index
                                     :clip self.clip-region})))

    (fn set-visible [self visible?]
      (local desired (not (not visible?)))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (if desired
            (update self)
            (remove-quad))))

    (fn drop [_self]
      (remove-quad))

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
