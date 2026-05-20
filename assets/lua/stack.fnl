(local glm (require :glm))
(import-macros {: incf : maxf} :macros)

(local {: Layout} (require :layout))

(fn Stack [opts]
  (local depth-offset-step (or opts.depth-offset-step 1))
  (fn build [ctx]
    (local children
      (icollect [_ x (ipairs opts.children)] (x ctx)))

    (fn measurer [self]
      (set self.measure (glm.vec3 0))
      (each [i child (ipairs self.children)]
        (child:measurer)
        (for [a 1 3] (maxf (. self.measure a) (. child.measure a))))
      )

    (fn constrained-measurer [self constraints]
      (set self.measure (glm.vec3 0))
      (each [i child (ipairs self.children)]
        (child:measure-constrained constraints)
        (for [a 1 3] (maxf (. self.measure a) (. child.measure a)))))

    (fn layouter [self]
      (each [i child (ipairs self.children)]
        (set child.size self.size)
        (set child.position self.position)
        (set child.rotation self.rotation)
        (set child.depth-offset-index (+ self.depth-offset-index (* depth-offset-step i)))
        (set child.clip-region self.clip-region)
        (child:layouter)
        ))

    (local layout
      (Layout {:name "stack"
               : measurer :constrained-measurer constrained-measurer : layouter
               :children (icollect [_ x (ipairs children)]
                                   x.layout)}))

    (fn drop [self]
      (self.layout:drop)
      (each [_ child (ipairs children)]
        (child:drop)))

    {: children : layout : drop}))
