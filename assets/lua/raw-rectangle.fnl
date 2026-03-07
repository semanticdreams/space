(local glm (require :glm))
(local glm-mat4-render-trs (. glm :mat4-render-trs))
(local QuadBatcher (require :next-app/quad-batcher))

(var fallback-quad-batcher nil)

(fn ensure-fallback-quad-batcher []
  (if fallback-quad-batcher
      fallback-quad-batcher
      (do
        (set fallback-quad-batcher (QuadBatcher {}))
        fallback-quad-batcher)))

(fn rect-matrix [position rotation size]
  (glm-mat4-render-trs position.x
                       position.y
                       position.z
                       rotation
                       size.x
                       size.y
                       1))

(fn RawRectangle [opts]
  (set opts.color (or opts.color (glm.vec4 1 0 0 1)))
  (set opts.position (or opts.position (glm.vec3 0)))
  (set opts.size (or opts.size (glm.vec2 10)))
  (set opts.rotation (or opts.rotation (glm.quat 1 0 0 0)))

  (fn build [ctx]
    (local quad-batcher
      (if (and ctx ctx.get-rectangle-quad-batcher)
          (ctx:get-rectangle-quad-batcher)
          (ensure-fallback-quad-batcher)))
    (local key {})
    (local upsert-options {:matrix nil
                           :color nil
                           :depth-offset 0
                           :clip nil})
    (local cached {:has-state? false
                   :px nil
                   :py nil
                   :pz nil
                   :rx nil
                   :ry nil
                   :rz nil
                   :rw nil
                   :sx nil
                   :sy nil
                   :c1 nil
                   :c2 nil
                   :c3 nil
                   :c4 nil
                   :depth nil
                   :clip nil})

    (fn remove-quad []
      (quad-batcher:remove-quad key))

    (fn upsert [self clip-region]
      (set upsert-options.matrix (rect-matrix self.position self.rotation self.size))
      (set upsert-options.color self.color)
      (set upsert-options.depth-offset self.depth-offset-index)
      (set upsert-options.clip clip-region)
      (quad-batcher:upsert-quad key upsert-options))

    (fn update-clipped [self clip-region]
      (upsert self clip-region)
      (when cached.has-state?
        (set cached.has-state? false)))

    (fn update-unclipped [self]
      (local position self.position)
      (local rotation self.rotation)
      (local size self.size)
      (local color self.color)
      (local depth-offset-index self.depth-offset-index)
      (local px position.x)
      (local py position.y)
      (local pz position.z)
      (local rx rotation.x)
      (local ry rotation.y)
      (local rz rotation.z)
      (local rw rotation.w)
      (local sx size.x)
      (local sy size.y)
      (local color1 (or color.x (. color 1)))
      (local color2 (or color.y (. color 2)))
      (local color3 (or color.z (. color 3)))
      (local color4 (or color.w (. color 4)))
      (local changed?
        (or (not cached.has-state?)
            (not (= cached.clip nil))
            (not (= cached.px px))
            (not (= cached.py py))
            (not (= cached.pz pz))
            (not (= cached.rx rx))
            (not (= cached.ry ry))
            (not (= cached.rz rz))
            (not (= cached.rw rw))
            (not (= cached.sx sx))
            (not (= cached.sy sy))
            (not (= cached.c1 color1))
            (not (= cached.c2 color2))
            (not (= cached.c3 color3))
            (not (= cached.c4 color4))
            (not (= cached.depth depth-offset-index))))
      (when changed?
        (upsert self nil)
        (set cached.px px)
        (set cached.py py)
        (set cached.pz pz)
        (set cached.rx rx)
        (set cached.ry ry)
        (set cached.rz rz)
        (set cached.rw rw)
        (set cached.sx sx)
        (set cached.sy sy)
        (set cached.c1 color1)
        (set cached.c2 color2)
        (set cached.c3 color3)
        (set cached.c4 color4)
        (set cached.depth depth-offset-index)
        (set cached.clip nil)
        (set cached.has-state? true)))

    (fn update [self]
      (if (not self.visible?)
          (do
            (remove-quad)
            (set cached.has-state? false))
          (do
            (local clip-region self.clip-region)
            (if clip-region
                (update-clipped self clip-region)
                (update-unclipped self)))))

    (fn set-visible [self visible?]
      (local desired (not (not visible?)))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (if desired
            (when cached.has-state?
              (update self))
            (do
              (remove-quad)
              (set cached.has-state? false)))))

    (fn drop [_self]
      (remove-quad)
      (set cached.has-state? false))

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
