(local Widget (require :widget))
(local {: Layout} (require :layout))

(fn Flex [opts]
  (fn build [ctx]
    (local e {:children (or opts.children [])})

    (fn measurer [self]
      (each [i child (ipairs e.children)]
        (child.layout:measurer))
      (set self.measure (glm.vec3:new 0)))

    (fn layouter [self]
      (var offset 0)
      (each [i child (ipairs e.children)]
        (set child.layout.size child.layout.measure)
        (set child.layout.position
             (+ self.position (glm.vec3:new offset 0 0)))
        (child.layout:layouter)
        (set offset (+ offset child.layout.size.x)))
      )

    (set e.layout
         (Layout
           {:name "flex"
            :children (icollect [_ v (ipairs e.children)]
                                v.layout)
            : measurer
            : layouter}))

    (set e.drop (fn [self]
                  ))

    e)
  )
  ;(Widget {}))
