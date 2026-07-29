(global app (or app {}))
(local glm (require :glm))
(local {: Layout} (require :layout))

(fn ActivityTopToolbarView [_opts]
  (fn build [ctx]
    (var prev-builder nil)
    (var built-child nil)

    (fn measurer [self]
      (local current-builder app.activity-top-toolbar-builder)
      (when (not (= current-builder prev-builder))
        (when built-child
          (built-child:drop)
          (set built-child nil))
        (when current-builder
          (set built-child (current-builder ctx)))
        (set prev-builder current-builder))
      (if built-child
          (let [layout built-child.layout]
            (layout:measurer)
            (set self.measure layout.measure))
          (set self.measure (glm.vec3 0 0 0)))
      (set app.activity-top-toolbar-height
           (or (and self.measure self.measure.y) 0)))

    (fn layouter [self]
      (when built-child
        (let [layout built-child.layout]
          (set layout.size (or self.size self.measure))
          (set layout.position self.position)
          (set layout.rotation self.rotation)
          (set layout.clip-region self.clip-region)
          (set layout.depth-offset-index self.depth-offset-index)
          (layout:layouter))))

    (local layout
      (Layout {:name "activity-top-toolbar-view"
               :measurer measurer
               :layouter layouter
               :children []}))

    (fn drop [self]
      (when built-child
        (built-child:drop)
        (set built-child nil))
      (set prev-builder nil)
      (set app.activity-top-toolbar-height 0)
      (layout:drop))

    {:layout layout
     :drop drop})

  build)

ActivityTopToolbarView