(local glm (require :glm))
(local {: Layout} (require :layout))
(local Padding (require :padding))
(local Card (require :card))
(local HudChromeMetrics (require :hud-chrome-metrics))

(local row-spacing HudChromeMetrics.status-row-spacing)
(local column-edge-insets HudChromeMetrics.status-column-edge-insets)
(local column-horizontal-padding HudChromeMetrics.status-column-horizontal-padding)

(fn padded-column [child-builder]
  (Padding {:edge-insets column-edge-insets
            :child child-builder}))

(fn widget-size [entity]
  (local layout (and entity entity.layout))
  (and layout (or layout.measure layout.size)))

(fn StatusPanelLayout [opts]
  (local options (or opts {}))
  (local commands-builder (assert options.commands-builder "StatusPanelLayout requires :commands-builder"))
  (local info-builder (assert options.info-builder "StatusPanelLayout requires :info-builder"))
  (local body-builder options.body-builder)
  (fn build [ctx]
    (local commands-column ((padded-column commands-builder) ctx))
    (local body-column (and body-builder
                            ((padded-column body-builder) ctx)))
    (local info-column ((padded-column info-builder) ctx))
    (local row-state {:commands-max-width nil})

    (fn commands-content-min-width []
      (local provider options.commands-min-width-provider)
      (if provider
          (math.max 0 (or (provider) 0))
          0))

    (fn row-gap-count []
      (if body-column 2 1))

    (fn place-child [parent child offset size]
      (set child.layout.size size)
      (set child.layout.position (+ parent.position (parent.rotation:rotate offset)))
      (set child.layout.rotation parent.rotation)
      (set child.layout.depth-offset-index parent.depth-offset-index)
      (set child.layout.clip-region parent.clip-region)
      (child.layout:layouter))

    (local row-children [commands-column.layout])
    (when body-column
      (table.insert row-children body-column.layout))
    (table.insert row-children info-column.layout)
    (local row {:children row-children})

    (fn row-measurer [self]
      (commands-column.layout:measurer)
      (info-column.layout:measurer)
      (when body-column
        (body-column.layout:measurer))
      (local commands-size (widget-size commands-column))
      (local body-size (widget-size body-column))
      (local info-size (widget-size info-column))
      (local width (+ (. commands-size 1)
                      (if body-size (. body-size 1) 0)
                      (. info-size 1)
                      (* row-spacing (row-gap-count))))
      (local height (math.max (. commands-size 2)
                              (if body-size (. body-size 2) 0)
                              (. info-size 2)))
      (local depth (math.max (. commands-size 3)
                             (if body-size (. body-size 3) 0)
                             (. info-size 3)))
      (set self.measure (glm.vec3 width height depth)))

    (fn row-layouter [self]
      (set self.size (or self.size self.measure))
      (local commands-size (widget-size commands-column))
      (local body-size (widget-size body-column))
      (local info-size (widget-size info-column))
      (local commands-column-min-width (+ (commands-content-min-width)
                                          column-horizontal-padding))
      (local available-width (- (. self.size 1)
                                (if body-size (. body-size 1) 0)
                                (. info-size 1)
                                (* row-spacing (row-gap-count))))
      (local commands-column-width (math.max commands-column-min-width
                                             available-width))
      (local commands-content-width (math.max 0
                                             (- commands-column-width
                                                column-horizontal-padding)))
      (local commands-y (/ (- (. self.size 2) (. commands-size 2)) 2))
      (local info-y (/ (- (. self.size 2) (. info-size 2)) 2))
      (set row-state.commands-max-width commands-content-width)
      (place-child self
                   commands-column
                   (glm.vec3 0 commands-y 0)
                   (glm.vec3 commands-column-width
                             (. commands-size 2)
                             (. commands-size 3)))
      (when body-column
        (local body-y (/ (- (. self.size 2) (. body-size 2)) 2))
        (place-child self
                     body-column
                     (glm.vec3 (+ commands-column-width row-spacing) body-y 0)
                     body-size))
      (place-child self
                   info-column
                   (glm.vec3 (- (. self.size 1) (. info-size 1)) info-y 0)
                   info-size))

    (local row-layout
      (Layout {:name "status-panel-row"
               :children row.children
               :measurer row-measurer
               :layouter row-layouter}))
    (set row.layout row-layout)
    (set row.drop
         (fn [_self]
           (row-layout:drop)
           (commands-column:drop)
           (when body-column
             (body-column:drop))
           (info-column:drop)))

    (local panel
      ((Card
         {:child
          (Padding
            {:edge-insets HudChromeMetrics.single-row-shell-padding
             :child (fn [_child-ctx]
                      row)})})
       ctx))
    (set panel.commands-max-width
         (fn [_self]
           (or row-state.commands-max-width
               (commands-content-min-width))))
    panel))

{:StatusPanelLayout StatusPanelLayout}
