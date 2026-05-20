(local glm (require :glm))
(local {: Layout} (require :layout))

(local EdgeInsets
  {
   :all (fn [self v] [v v v v v v])
   :only (fn [self v] [(or v.x0 0) (or v.y0 0) (or v.z0 0)
                  (or v.x1 0) (or v.y1 0) (or v.z1 0)])
   :symmetric (fn [self v] [(or v.x 0) (or v.y 0) (or v.z 0)
                       (or v.x 0) (or v.y 0) (or v.z 0)])
   :auto (fn [self v]
           (if
             (= (length v) 1) (self:all (. v 1))
             (= (length v) 2) (self:symmetric {:x (. v 1) :y (. v 2)})
             (= (length v) 3) (self:symmetric {:x (. v 1) :y (. v 2) :z (. v 3)})
             (= (length v) 4) (self:only {:x0 (. v 1) :x1 (. v 2)
                                                :y0 (. v 3) :y1 (. v 4)})
             (= (length v) 6) (self:only {:x0 (. v 1) :x1 (. v 2)
                                                :y0 (. v 3) :y1 (. v 4)
                                                :z0 (. v 5) :z1 (. v 6)})
             (error "invalid edge inset values")))

   })

(fn Padding [opts]
  (local edge-insets (EdgeInsets:auto (or opts.edge-insets [0.5 0.5])))

  (fn build [ctx]
    (local child (opts.child ctx))

    (fn inset-size []
      (+ (glm.vec3 (. edge-insets 1) (. edge-insets 2) (. edge-insets 3))
         (glm.vec3 (. edge-insets 4) (. edge-insets 5) (. edge-insets 6))))

    (fn child-constraints [constraints]
      (if (and constraints constraints.max)
          {:max (glm.vec3 (math.max 0 (- constraints.max.x (. edge-insets 1) (. edge-insets 4)))
                          (math.max 0 (- constraints.max.y (. edge-insets 2) (. edge-insets 5)))
                          (math.max 0 (- constraints.max.z (. edge-insets 3) (. edge-insets 6))))}
          constraints))

    (fn measurer [self]
      (child.layout:measurer)
      (set self.measure (+ child.layout.measure (inset-size)))
      )

    (fn constrained-measurer [self constraints]
      (child.layout:measure-constrained (child-constraints constraints))
      (set self.measure (+ child.layout.measure (inset-size))))

    (fn layouter [self]
      (local new-size (- self.size
                         (glm.vec3 (. edge-insets 1) (. edge-insets 2) (. edge-insets 3))
                         (glm.vec3 (. edge-insets 4) (. edge-insets 5) (. edge-insets 6))))
      (if (not (= child.layout.size new-size))
          (set child.layout.size new-size))
      (local child-offset (glm.vec3 (. edge-insets 1) (. edge-insets 2) (. edge-insets 3)))
      (local desired-position (+ self.position (self.rotation:rotate child-offset)))
      (set child.layout.position desired-position)
      (set child.layout.rotation self.rotation)
      (set child.layout.depth-offset-index self.depth-offset-index)
      (set child.layout.clip-region self.clip-region)
      (child.layout:layouter))

    (local layout (Layout {:name "padding"
                           : measurer :constrained-measurer constrained-measurer : layouter
                           :children [child.layout]}))

    (fn drop [self]
      (self.layout:drop)
      (child:drop))

    {: child : layout : drop}))
