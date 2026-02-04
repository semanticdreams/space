(local glm (require :glm))
(local {: Layout : resolve-mark-flag} (require :layout))
(local ClipUtils (require :clip-utils))
(local MathUtils (require :math-utils))
(local BoundsUtils (require :bounds-utils))

(var clip-region-seq 0)

(fn next-clip-region-id []
  (set clip-region-seq (+ clip-region-seq 1))
  clip-region-seq)

(local scroll-offset-epsilon 1e-5)

(local approx (fn [a b] (MathUtils.approx a b {:epsilon scroll-offset-epsilon})))

(fn bounds-aabb-in-parent [parent child]
  (BoundsUtils.bounds-aabb-in-parent parent child))

(fn quat-equal? [a b]
  (if (and a b)
      (and (approx a.x b.x)
           (approx a.y b.y)
           (approx a.z b.z)
           (approx a.w b.w))
      (= a b)))

(fn intersect-bounds [parent child]
  (if (not parent)
      child
      (if (not child)
          parent
          (bounds-aabb-in-parent parent child))))

(fn vec3-equal? [a b]
  (if (and a b)
      (and (approx a.x b.x)
           (approx a.y b.y)
           (approx a.z b.z))
      (= a b)))

(fn resolve-glm-vec3 [value]
  (if (and value (= (type value) :userdata))
      (glm.vec3 (or value.x 0)
            (or value.y 0)
            (or value.z 0))
      (if (and value (= (type value) :table))
          (glm.vec3 (or value.x (. value 1) 0)
                (or value.y (. value 2) 0)
                (or value.z (. value 3) 0))
          (glm.vec3 0 0 0))))

(fn ScrollArea [opts]
  (local options (or opts {}))
  (assert options.child "ScrollArea requires :child")

  (fn build [ctx]
    (local child (options.child ctx))
    (local scroll-offset (resolve-glm-vec3 options.scroll-offset))
    (local state {:child child
                  :scroll-offset scroll-offset
                  :clip-region nil
                  :clip-region-id (next-clip-region-id)
                  :content-size (glm.vec3 0 0 0)})

    (fn update-clip-region [layout]
      (local clip (or state.clip-region
                      {:id state.clip-region-id
                       :layout layout
                       :bounds {:position layout.position
                                :rotation layout.rotation
                                :size layout.size}}))
      (set clip.id state.clip-region-id)
      (set clip.layout layout)
      (local bounds (or clip.bounds
                        {:position layout.position
                         :rotation layout.rotation
                         :size layout.size}))
      (local parent-clip (and layout layout.clip-region))
      (local parent-bounds (and parent-clip parent-clip.bounds))
      (local desired {:position layout.position
                      :rotation layout.rotation
                      :size layout.size})
      (local resolved (intersect-bounds parent-bounds desired))
      (set clip.bounds bounds)
      (set bounds.position (or (and resolved resolved.position) layout.position))
      (set bounds.rotation (or (and resolved resolved.rotation) layout.rotation))
      (set bounds.size (or (and resolved resolved.size) layout.size))
      (ClipUtils.update-region clip)
      (set state.clip-region clip)
      clip)

    (fn measurer [self]
      (child.layout:measurer)
      (local measured (or child.layout.measure (glm.vec3 0 0 0)))
      (set state.content-size measured)
      (set self.measure measured))

    (fn layouter [self]
      (local clip (update-clip-region self))
      (set self.clip-region clip)
      (local child-layout state.child.layout)
      (local content-size (or state.content-size child-layout.measure (glm.vec3 0 0 0)))
      (local viewport-size (or self.size (glm.vec3 0 0 0)))
      (local child-size
        (glm.vec3 (math.max content-size.x viewport-size.x)
              (math.max content-size.y viewport-size.y)
              content-size.z))
      (set child-layout.size child-size)
      (local rotated-scroll (self.rotation:rotate state.scroll-offset))
      (set child-layout.position (- self.position rotated-scroll))
      (set child-layout.rotation self.rotation)
      (set child-layout.depth-offset-index self.depth-offset-index)
      (set child-layout.clip-region self.clip-region)
      (child-layout:layouter))

    (local layout
      (Layout {:name (or options.name "scroll-area")
               : measurer : layouter
               :children [state.child.layout]}))

    (set state.layout layout)

    (fn drop [self]
      (self.layout:drop)
      (state.child:drop))

    (fn set-scroll-offset [self offset opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local desired (resolve-glm-vec3 offset))
      (when (not (vec3-equal? desired state.scroll-offset))
        (set state.scroll-offset desired)
        (when mark-layout-dirty?
          (self.layout:mark-layout-dirty))))

    (fn get-scroll-offset [_self]
      state.scroll-offset)

    (fn get-content-size [_self]
      (or state.content-size
          (and state.child state.child.layout state.child.layout.measure)
          (glm.vec3 0 0 0)))

    {:child state.child
     :layout layout
     :drop drop
     :set-scroll-offset set-scroll-offset
     :get-scroll-offset get-scroll-offset
     :get-content-size get-content-size}))

ScrollArea
