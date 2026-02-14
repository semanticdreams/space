(local glm (require :glm))

(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)

(fn normalize-padding [padding]
  (if (and padding (= (type padding) :table))
      {:x (or (. padding :x) (. padding 1) 0)
       :y (or (. padding :y) (. padding 2) 0)}
      {:x (or padding 0)
       :y (or padding 0)}))

(fn set-child-frame! [child x y z w h d rz]
  (if child.layout-set-frame
      (child:layout-set-frame x y z w h d rz)
      (child:set-frame x y z w h d rz {:mark-dirty? false})))

(fn PanelWidget [opts]
  (local options (or opts {}))
  (local child options.child)
  (local fixed-width options.width)
  (local fixed-height options.height)
  (local padding (normalize-padding (or options.padding [0.06 0.06])))
  (var color (or options.color (glm.vec4 0.12 0.16 0.26 0.9)))
  (var visible? (if (= options.visible? false) false true))
  (var last-quad-batcher nil)

  (fn measure-fn [self max-width max-height max-depth]
    (if child
        (do
          (child:run-measure (math.max 0 (- max-width (* padding.x 2)))
                             (math.max 0 (- max-height (* padding.y 2)))
                             max-depth)
          (self:set-measure (or fixed-width (+ child.measured-width (* padding.x 2)))
                            (or fixed-height (+ child.measured-height (* padding.y 2)))
                            0))
        (self:set-measure (or fixed-width 0)
                          (or fixed-height 0)
                          0)))

  (fn layout-fn [self width height depth]
    (self:set-size width height depth {:mark-dirty? false})
    (when child
      (set-child-frame! child
                        padding.x
                        padding.y
                        0
                        (math.max 0 (- width (* padding.x 2)))
                        (math.max 0 (- height (* padding.y 2)))
                        0
                        0)
      (child:run-layout child.width child.height child.depth)))

  (local panel
    (Node.new {:name (or options.name "next-panel")
               :measure-fn measure-fn
               :layout-fn layout-fn}))

  (when child
    (panel:add-child child))

  (set panel.emit-quads
       (fn [self quad-batcher clip-matrix]
         (set last-quad-batcher quad-batcher)
         (when visible?
           (quad-batcher:add-quad {:key self
                                   :matrix self.render-matrix
                                   :color color
                                   :depth-offset 0
                                   :clip-matrix clip-matrix}))
         (when (and (not visible?) quad-batcher.remove-quad)
           (quad-batcher:remove-quad self))))

  (set panel.set-color
       (fn [self next-color]
         (set color (or next-color color))
         (set self.color color)
         (self:mark-render-dirty)))

  (set panel.set-visible
       (fn [self next-visible]
         (set visible? (not (= next-visible false)))
         (self:mark-render-dirty)))

  (set panel.visible?
       (fn [_self]
         visible?))

  (set panel.drop
       (fn [self]
         (when (and last-quad-batcher last-quad-batcher.remove-quad)
           (last-quad-batcher:remove-quad self))))

  (set panel.color color)

  panel)

PanelWidget
