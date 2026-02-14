(local glm (require :glm))

(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)
(local PanelWidget (require :next-app/panel-widget))
(local ClipMatrix (require :next-app/clip-matrix))

(fn clamp [value low high]
  (math.max low (math.min high value)))

(fn ScrollWidget [opts]
  (local options (or opts {}))
  (local child (assert options.child "ScrollWidget requires :child"))
  (local width (or options.width 1.0))
  (local height (or options.height 0.6))
  (var scroll-y (or options.scroll-y 0))
  (var max-scroll 0)
  (var local-clip-matrix (ClipMatrix.alloc-matrix))
  (var composed-clip-matrix (ClipMatrix.alloc-matrix))

  (local background (PanelWidget {:name (or options.background-name "next-scroll-bg")
                                  :padding [0 0]
                                  :color (or options.background-color (glm.vec4 0.08 0.10 0.15 0.88))}))

  (var scroll nil)

  (fn measure-fn [self max-width max-height max-depth]
    (child:run-measure max-width max-height max-depth)
    (self:set-measure width height 0))

  (fn layout-fn [self resolved-width resolved-height depth]
    (self:set-size resolved-width resolved-height depth {:mark-dirty? false})
    (background:layout-set-frame 0 0 -0.001 resolved-width resolved-height 0 (glm.quat 1 0 0 0))
    (background:run-layout background.width background.height background.depth)

    (set max-scroll (math.max 0 (- child.measured-height resolved-height)))
    (set scroll-y (clamp scroll-y 0 max-scroll))

    (child:layout-set-frame 0 (- 0 scroll-y) -0.002
                            (math.max child.measured-width resolved-width)
                            child.measured-height
                            0
                            (glm.quat 1 0 0 0))
    (child:run-layout child.width child.height child.depth)

    (set self.scroll-y scroll-y)
    (set self.max-scroll max-scroll))

  (set scroll
       (Node.new {:name (or options.name "next-scroll")
                  :measure-fn measure-fn
                  :layout-fn layout-fn}))
  (scroll:add-child background)
  (scroll:add-child child)

  (set scroll.child child)
  (set scroll.scroll-y scroll-y)
  (set scroll.max-scroll max-scroll)

  (set scroll.set-scroll-y
       (fn [self value]
         (set scroll-y (clamp value 0 max-scroll))
         (set self.scroll-y scroll-y)
         (self:mark-layout-dirty)))

  (set scroll.scroll-by
       (fn [self delta]
         (self:set-scroll-y (+ scroll-y delta))))

  (set scroll.emit-quads
       (fn [_self quad-batcher inherited-clip-matrix]
         (background:emit-quads quad-batcher inherited-clip-matrix)))

  (set scroll.get-clip-matrix
       (fn [_self inherited-clip-matrix]
         (set local-clip-matrix (ClipMatrix.update-from-render-matrix! local-clip-matrix scroll.render-matrix))
         (set composed-clip-matrix (ClipMatrix.compose! composed-clip-matrix inherited-clip-matrix local-clip-matrix))
         composed-clip-matrix))

  scroll)

ScrollWidget
