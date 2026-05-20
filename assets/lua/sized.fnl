(local glm (require :glm))
(local {: Layout} (require :layout))

(fn Sized [opts]
  (fn build [ctx]
    (local child (opts.child ctx))

    (fn measurer [self]
      (child.layout:measurer)
      (set self.measure opts.size))

    (fn resolve-child-max [constraints]
      (local max-size (and constraints constraints.max))
      (if max-size
          (glm.vec3 (if (> opts.size.x 0) opts.size.x max-size.x)
                    (if (> opts.size.y 0) opts.size.y max-size.y)
                    (if (> opts.size.z 0) opts.size.z max-size.z))
          opts.size))

    (fn constrained-measurer [self constraints]
      (child.layout:measure-constrained {:max (resolve-child-max constraints)})
      (set self.measure opts.size))

    (fn layouter [self]
      (set child.layout.size self.size)
      (set child.layout.position self.position)
      (set child.layout.rotation self.rotation)
      (set child.layout.depth-offset-index self.depth-offset-index)
      (set child.layout.clip-region self.clip-region)
      (child.layout:layouter))

    (local layout (Layout {:name "sized"
                           : measurer :constrained-measurer constrained-measurer : layouter
                           :children [child.layout]}))

    (fn drop [self]
      (self.layout:drop)
      (child:drop))

    {: child : layout : drop}))
