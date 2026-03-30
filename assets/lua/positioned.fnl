(local glm (require :glm))
(local {: Layout} (require :layout))

(fn Positioned [opts]
  (assert opts.child "Positioned requires :child")
  (local offset (or opts.position (glm.vec3 0 0 0)))
  (local local-rotation (or opts.rotation (glm.quat 1 0 0 0)))

  (fn resolve-size-option []
    (if (= (type opts.size) :function)
        (opts.size)
        opts.size))

  (fn build [ctx]
    (local child (opts.child ctx))

    (fn measurer [self]
      (child.layout:measurer)
      (set self.measure (or (resolve-size-option) child.layout.measure)))

    (fn layouter [self]
      (local desired-size (or (resolve-size-option) child.layout.measure))
      (set self.size desired-size)
      (set child.layout.size desired-size)
      (local positioned (+ self.position (self.rotation:rotate offset)))
      (set child.layout.position positioned)
      (set child.layout.rotation (* self.rotation local-rotation))
      (set child.layout.depth-offset-index self.depth-offset-index)
      (set child.layout.clip-region self.clip-region)
      (child.layout:layouter))

    (local layout
      (Layout {:name "positioned"
               :children [child.layout]
               : measurer
               : layouter}))

    (fn drop [self]
      (self.layout:drop)
      (child:drop))

    {:child child
     :layout layout
     :drop drop}))

Positioned
