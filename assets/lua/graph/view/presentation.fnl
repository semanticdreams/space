(local glm (require :glm))
(local LayeredPoint (require :layered-point))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))

(fn compact-point [opts]
  "Create a compact graph node presentation (same LayeredPoint as before)."
  (local options (or opts {}))
  (LayeredPoint {:points options.points
                 :position options.position
                 :pointer-target options.pointer-target
                 :depth-offset-step options.depth-offset-step
                 :base-depth-offset-index options.base-depth-offset-index
                 :base-layer-index options.base-layer-index
                 :layers options.layers}))

(fn card-builder [opts]
  "Returns a builder function (ctx) -> widget for an expanded graph node card.
  The returned widget has .layout (Layout), .position (vec3), .size (number),
  and the standard GraphView point interface including .intersect, .set-position,
  .set-position-values, .set-layer-size, .drop, and event handler fields."
  (local options (or opts {}))
  (local node (assert options.node "card-builder requires :node"))
  (local position (or options.position (glm.vec3 0 0 0)))
  (local initial-card-size (or options.size (glm.vec3 64.0 48.0 0)))
  (local background-color (or options.background-color (glm.vec4 0.08 0.09 0.12 0.92)))
  (local selection-color (or options.selection-color (glm.vec4 0.22 0.16 0.08 0.96)))
  (local focus-color (or options.focus-color (glm.vec4 0.08 0.16 0.24 0.96)))
  (local depth-offset-index (or options.depth-offset-index 0))
  (local on-collapse (assert options.on-collapse "card-builder requires :on-collapse"))
  (local on-open (assert options.on-open "card-builder requires :on-open"))
  (local on-menu (assert options.on-menu "card-builder requires :on-menu"))

  (fn build-header-bar [ctx]
    ((Flex {:axis 1
            :yalign :center
            :xspacing 0.25
            :children [(FlexChild (Button {:icon "close_fullscreen"
                                            :variant :ghost
                                            :focusable? false
                                            :text nil
                                            :on-click (fn [_ _] (on-collapse))}) 0)
                       (FlexChild (Button {:icon "open_in_new"
                                            :variant :ghost
                                            :focusable? false
                                            :text nil
                                            :on-click (fn [_ event] (on-open event))}) 0)
                       (FlexChild (Button {:icon "more_vert"
                                            :variant :ghost
                                            :focusable? false
                                            :text nil
                                            :on-click (fn [_ event] (on-menu event))}) 0)]})
     ctx))

  (fn [ctx]
    (assert ctx "card-builder requires ctx")
    (local layout-root (and ctx ctx.layout-root))
    (assert layout-root "card-builder requires ctx.layout-root")
    (local preview-fn (assert (and node node.preview)
                              (.. "Graph card requires node preview for " (or node.key "unknown"))))
    (assert (= (type preview-fn) :function)
            (.. "Graph card preview must be a function for " (or node.key "unknown")))

    (local background ((Rectangle {:color background-color}) ctx))
    (local card {:node node
                  :_card-size (glm.vec3 initial-card-size.x initial-card-size.y initial-card-size.z)
                  :_header-height 3.0
                  :on-click nil
                  :on-double-click nil
                  :on-right-click nil})

    (set card.position (glm.vec3 position.x position.y position.z))
    (set card.size (math.max initial-card-size.x initial-card-size.y))
    (set card.depth-offset-index depth-offset-index)
    (set card._focus-layer-size 0)
    (set card._selection-layer-size 0)

    (fn card-origin [size]
      (local resolved (or size card._card-size initial-card-size))
      (glm.vec3 (- card.position.x (/ resolved.x 2.0))
                (- card.position.y (/ resolved.y 2.0))
                (- card.position.z (/ resolved.z 2.0))))

    (fn update-background-color []
      (when background
        (set background.color
             (if (> card._focus-layer-size 0)
                 focus-color
                 (> card._selection-layer-size 0)
                 selection-color
                 background-color))))

    (local header-bar (build-header-bar ctx))
    (set card.header-bar header-bar)

    (fn measurer [self]
      (header-bar.layout:measurer)
      (set card._header-height (or header-bar.layout.measure.y 3.0))
      (local child (and card.view-widget card.view-widget.layout))
      (when child
        (child:measure-constrained {:max (glm.vec3 initial-card-size.x
                                                    (math.max 0 (- initial-card-size.y card._header-height))
                                                    initial-card-size.z)}))
      (local child-measure (and child child.measure))
      (local total-y (if child-measure
                         (+ card._header-height child-measure.y)
                         initial-card-size.y))
      (set card._card-size
           (glm.vec3 (math.max initial-card-size.x (or (and child-measure child-measure.x) 0))
                     (math.max initial-card-size.y total-y)
                     (math.max initial-card-size.z (or (and child-measure child-measure.z) 0))))
      (set card.size (math.max card._card-size.x card._card-size.y))
      (set self.measure card._card-size))

    (fn layouter [self]
      (local header-height card._header-height)
      (set self.size card._card-size)
      (set self.position (card-origin card._card-size))
      (set self.rotation (glm.quat 1 0 0 0))
      (when background
        (set background.layout.position self.position)
        (set background.layout.size card._card-size)
        (set background.layout.rotation (glm.quat 1 0 0 0))
        (set background.layout.depth-offset-index self.depth-offset-index)
        (background.layout:layouter true))
      (when (and card.header-bar card.header-bar.layout)
        (local header card.header-bar.layout)
        (set header.position self.position)
        (set header.size (glm.vec3 card._card-size.x header-height 0))
        (set header.rotation (glm.quat 1 0 0 0))
        (set header.depth-offset-index (+ self.depth-offset-index 1))
        (header:layouter true))
      (when (and card.view-widget card.view-widget.layout)
        (local child card.view-widget.layout)
        (set child.position (+ self.position (glm.vec3 0 header-height 0)))
        (set child.size (glm.vec3 card._card-size.x (- card._card-size.y header-height) 0))
        (set child.rotation (glm.quat 1 0 0 0))
        (set child.depth-offset-index (+ self.depth-offset-index 2))
        (child:layouter true)))

    (local layout
      (Layout {:name (.. "graph-card-" (or node.key "unknown"))
               :measurer measurer
               :layouter layouter}))
    (layout:set-root layout-root)
    (layout:add-child background.layout)
    (layout:add-child header-bar.layout)
    (set card.layout layout)
    (set layout.position (card-origin card._card-size))
    (set layout.size card._card-size)
    (set layout.measure card._card-size)
    (set layout.depth-offset-index depth-offset-index)

    (set card.set-position
         (fn [_ new-position]
            (set card.position (glm.vec3 new-position.x new-position.y new-position.z))
            (set layout.position (card-origin card._card-size))
            (layout:mark-layout-dirty)))

    (set card.set-position-values
         (fn [_ x y z]
           (card:set-position (glm.vec3 x y z))))

    (set card.set-layer-size
         (fn [_ idx size]
           (when (= idx 1)
             (set card._focus-layer-size (or size 0)))
           (when (= idx 2)
             (set card._selection-layer-size (or size 0)))
           (update-background-color)
           (layout:mark-layout-dirty)))

    (set card.intersect
         (fn [_ ray]
           (layout:intersect ray)))

    (set card.drop
         (fn [_]
            (when card.header-bar
              (when card.header-bar.drop
                (card.header-bar:drop))
              (set card.header-bar nil))
            (when card.view-widget
              (when card.view-widget.drop
                (card.view-widget:drop))
              (set card.view-widget nil))
            (when background
              (background:drop))
            (layout:drop)))

    (local (ok result)
           (pcall
             (fn []
               (local builder (preview-fn node {:node node}))
               (assert (= (type builder) :function)
                       (.. "Graph card preview must return a builder for " (or node.key "unknown")))
               (local view-widget (builder ctx))
               (assert (and view-widget view-widget.layout)
                       (.. "Graph card preview must return widget with layout for " (or node.key "unknown")))
               (set card.view-widget view-widget)
               (layout:add-child view-widget.layout)
               (layout:mark-measure-dirty)
               (layout:mark-layout-dirty)
               view-widget)))
    (if ok
        result
        (do
          (card:drop)
          (error (.. "Graph card failed to build node preview for "
                     (or node.key "unknown")
                     ": "
                     (tostring result)))))

    card))

{:compact-point compact-point
 :card-builder card-builder}
