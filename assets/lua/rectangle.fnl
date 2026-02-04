(local glm (require :glm))
(local Widget (require :widget))
(local RawRectangle (require :raw-rectangle))
(local {: Layout : resolve-mark-flag} (require :layout))

(fn Rectangle [opts]
  (set opts.color (or opts.color (glm.vec4 1 1 0 1)))
  ;(set opts.size (or opts.size (glm.vec2 3)))

  (fn build [ctx]
    (local e {:color opts.color
              :visible? true
              :render-visible? true})

    (local rectangle
      ((RawRectangle {}) ctx))

    (fn measurer [self]
      (set self.measure (glm.vec3 0)))

    (fn layouter [self]
      (local should-render (and e.visible? (not (self:effective-culled?))))
      (rectangle:set-visible should-render)
      (set e.render-visible? should-render)
      (when should-render
        (set rectangle.color e.color)
        (set rectangle.size self.size)
        (set rectangle.position self.position)
        (set rectangle.rotation self.rotation)
        (set rectangle.depth-offset-index self.depth-offset-index)
        (set rectangle.clip-region self.clip-region)
        (rectangle:update)))

    (set e.layout (Layout {:name "rectangle"
                           : measurer
                           : layouter}))

    (fn set-visible [self visible? opts]
      (local desired (not (not visible?)))
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? false))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (rectangle:set-visible desired)
        (when (and mark-layout-dirty? self.layout)
          (self.layout:mark-layout-dirty))
        ))

    (set e.drop (fn [self]
                  (e.layout:drop)
                  (rectangle:drop)))
    (set e.set-visible set-visible)
    e)
  )
  ;(Widget {}))
