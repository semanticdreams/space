(local Widget (require :widget))
(local RawRectangle (require :raw-rectangle))
(local {: Layout} (require :layout))

(fn Rectangle [opts]
  (set opts.color (or opts.color (glm.vec4:new 1 1 0 1)))
  ;(set opts.size (or opts.size (glm.vec2:new 3)))

  (fn build [ctx]
    (local e {:color opts.color})

    (local rectangle
      ((RawRectangle {}) ctx))

    (fn measurer [self]
      (set self.measure (vec3 0)))

    (fn layouter [self]
      (set rectangle.color e.color)
      (set rectangle.size self.size)
      (set rectangle.position self.position)
      (set rectangle.rotation self.rotation)
      (rectangle:update))

    (set e.layout (Layout {:name "rectangle"
                                 : measurer
                                 : layouter}))

    (set e.drop (fn [self]
                  (e.layout:drop)
                  (rectangle:drop)))
    e)
  )
  ;(Widget {}))
