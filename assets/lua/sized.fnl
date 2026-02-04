(local {: Layout} (require :layout))

(fn Sized [opts]
  (fn build [ctx]
    (local child (opts.child ctx))

    (fn measurer [self]
      (child.layout:measurer)
      (set self.measure opts.size))

    (fn layouter [self]
      (set child.layout.size self.size)
      (set child.layout.position self.position)
      (set child.layout.rotation self.rotation)
      (set child.layout.depth-offset-index self.depth-offset-index)
      (set child.layout.clip-region self.clip-region)
      (child.layout:layouter))

    (local layout (Layout {:name "sized"
                           : measurer : layouter
                           :children [child.layout]}))

    (fn drop [self]
      (self.layout:drop)
      (child:drop))

    {: child : layout : drop}))
