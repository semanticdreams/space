(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)

(fn clamp [value low high]
  (math.max low (math.min high value)))

(fn drop-child-node [node]
  (when (and node node.drop)
    (node:drop)))

(fn VirtualListWidget [opts]
  (local options (or opts {}))
  (var item-count (or options.item-count 0))
  (local item-height (or options.item-height 0.08))
  (local width (or options.width 1.0))
  (local height (or options.height 0.5))
  (local overscan (or options.overscan 2))
  (local build-item (assert options.item-builder "VirtualListWidget requires :item-builder"))

  (var scroll-y (or options.scroll-y 0))
  (var first-visible -1)
  (var last-visible -1)
  (var list nil)

  (fn clear-visible-children [self]
    (each [_ child (ipairs self.children)]
      (drop-child-node child))
    (self:clear-children))

  (fn set-items-range [self first-index last-index]
    (when (or (not (= first-index first-visible))
              (not (= last-index last-visible)))
      (set first-visible first-index)
      (set last-visible last-index)
      (clear-visible-children self)
      (when (and (>= first-index 0) (>= last-index first-index))
        (for [idx first-index last-index]
          (local node (build-item idx))
          (self:add-child node)
          (node:layout-set-frame 0
                                 (* idx item-height)
                                 -0.001
                                 width
                                 item-height
                                 0
                                 0)
          (node:run-layout node.width node.height node.depth)))))

  (fn measure-fn [self _mw _mh _md]
    (self:set-measure width height 0))

  (fn layout-fn [self resolved-width resolved-height depth]
    (self:set-size resolved-width resolved-height depth {:mark-dirty? false})
    (local total-height (* item-count item-height))
    (local max-scroll (math.max 0 (- total-height resolved-height)))
    (set scroll-y (clamp scroll-y 0 max-scroll))

    (local start-index
      (clamp (math.floor (/ scroll-y item-height)) 0 (math.max 0 (- item-count 1))))
    (local visible-count (math.ceil (/ resolved-height item-height)))
    (local first-index (clamp (- start-index overscan) 0 (math.max 0 (- item-count 1))))
    (local last-index (clamp (+ start-index visible-count overscan) 0 (math.max 0 (- item-count 1))))

    (set-items-range self first-index last-index)

    (each [_ child (ipairs self.children)]
      (local idx (math.floor (/ child.local-y item-height)))
      (child:layout-set-frame 0
                              (- (* idx item-height) scroll-y)
                              -0.001
                              resolved-width
                              item-height
                              0
                              0)
      (child:run-layout child.width child.height child.depth))

    (set self.scroll-y scroll-y)
    (set self.max-scroll max-scroll)
    (set self.first-visible-index first-index)
    (set self.last-visible-index last-index))

  (set list
       (Node.new {:name (or options.name "next-virtual-list")
                  :measure-fn measure-fn
                  :layout-fn layout-fn}))

  (set list.scroll-y scroll-y)
  (set list.max-scroll 0)
  (set list.first-visible-index -1)
  (set list.last-visible-index -1)

  (set list.set-scroll-y
       (fn [self value]
         (set scroll-y value)
         (self:mark-layout-dirty)))

  (set list.scroll-by
       (fn [self delta]
         (self:set-scroll-y (+ scroll-y delta))))

  (set list.set-item-count
       (fn [self value]
         (set item-count (math.max 0 value))
         (self:mark-measure-dirty)
         (self:mark-layout-dirty)))

  (set list.drop
       (fn [self]
         (clear-visible-children self)))

  list)

VirtualListWidget
