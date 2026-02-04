(local glm (require :glm))
(local {: Layout} (require :layout))

(fn Container [opts]
  (fn build [ctx]
    (local children
      (icollect [_ child (ipairs (or opts.children []))]
        (let [raw (child ctx)
              element (or (and raw raw.element) raw)]
          {:element element
           :position (and raw raw.position)
           :rotation (and raw raw.rotation)
           :size (and raw raw.size)
           :transform-applied? false})))

    (fn measurer [self]
      (set self.measure (glm.vec3 0))
      (each [_ metadata (ipairs children)]
        (local child (and metadata metadata.element))
        (local layout (and child child.layout))
        (when layout
          (layout:measurer)
          (for [axis 1 3]
            (when (> (. layout.measure axis) (. self.measure axis))
              (set (. self.measure axis) (. layout.measure axis)))))))

    (fn layouter [self]
      (set self.size self.measure)
      (each [_ metadata (ipairs children)]
        (local child (and metadata metadata.element))
        (local layout (and child child.layout))
        (when layout
          (set layout.size (or metadata.size layout.measure layout.size))
          (local has-custom-transform
            (or metadata.position metadata.rotation))
          (if has-custom-transform
              (when (not metadata.transform-applied?)
                (local offset (or metadata.position (glm.vec3 0 0 0)))
                (local rotation (or metadata.rotation (glm.quat 1 0 0 0)))
                (local world-position (+ self.position (self.rotation:rotate offset)))
                (local world-rotation (* self.rotation rotation))
                (set layout.position world-position)
                (set layout.rotation world-rotation)
                (set metadata.transform-applied? true))
              (do
                (set layout.position self.position)
                (set layout.rotation self.rotation)))
          (set layout.depth-offset-index self.depth-offset-index)
          (set layout.clip-region self.clip-region)
          (layout:layouter))))

    (local layout
      (Layout {:name "container"
               :children (icollect [_ metadata (ipairs children)]
                                   metadata.element.layout)
               : measurer
               : layouter}))

    (fn drop [self]
      (self.layout:drop)
      (each [_ metadata (ipairs children)]
        (when (and metadata metadata.element metadata.element.drop)
          (metadata.element:drop))))

    {:children children
     :layout layout
     :drop drop}))

Container
