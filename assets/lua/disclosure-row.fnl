(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Padding (require :padding))
(local Button (require :button))
(local Icon (require :icon-widget))
(local Signal (require :signal))
(local {: Layout} (require :layout))

(fn DisclosureRow [opts]
  (assert opts.summary "DisclosureRow requires :summary")
  (fn build [ctx]
    (var expanded? (and opts.expanded? true))
    (local toggled (Signal))
    (var toggle-icon nil)
    (var sync-visible-children nil)
    (var layout nil)
    (when opts.on-toggle
      (toggled.connect opts.on-toggle))

    (fn icon-name []
      (if expanded? "expand_more" "chevron_right"))

    (fn sync-icon []
      (when toggle-icon
        (toggle-icon:set-icon (icon-name))))

    (local summary-button
      (Button {:child (fn [icon-ctx]
                        (set toggle-icon ((Icon {:icon (icon-name)
                                                 :scale 1.0})
                                          icon-ctx))
                        toggle-icon)
               :variant :ghost
               :padding [0.15 0.15]
               :on-click (fn [_button _event]
                           (set expanded? (not expanded?))
                           (sync-icon)
                           (when sync-visible-children
                             (sync-visible-children))
                           (when layout
                             (layout:mark-measure-dirty))
                           (toggled:emit expanded?))}))
    (local summary-button-widget (summary-button ctx))

    (local summary-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_ctx] (opts.summary ctx)) 1)
                         (FlexChild (fn [_ctx] summary-button-widget))]})
       ctx))
    (local details-widget (and opts.details (opts.details ctx)))

    (fn measurer [self]
      (summary-row.layout:measurer)
      (local m summary-row.layout.measure)
      (var height m.y)
      (var width m.x)
      (var depth m.z)
      (when (and expanded? details-widget)
        (details-widget.layout:measurer)
        (set height (+ height details-widget.layout.measure.y))
        (when (> details-widget.layout.measure.x width)
          (set width details-widget.layout.measure.x))
        (when (> details-widget.layout.measure.z depth)
          (set depth details-widget.layout.measure.z)))
      (set self.measure (glm.vec3 width height depth)))

    (fn measure-row [self constraints]
      (summary-row.layout:measure-constrained constraints)
      (local m summary-row.layout.measure)
      (var height m.y)
      (var width m.x)
      (var depth m.z)
      (when (and expanded? details-widget)
        (details-widget.layout:measure-constrained constraints)
        (set height (+ height details-widget.layout.measure.y))
        (when (> details-widget.layout.measure.x width)
          (set width details-widget.layout.measure.x))
        (when (> details-widget.layout.measure.z depth)
          (set depth details-widget.layout.measure.z)))
      (set self.measure (glm.vec3 width height depth)))

    (fn layouter [self]
      (set summary-row.layout.size
           (glm.vec3 self.size.x summary-row.layout.measure.y self.size.z))
      (set summary-row.layout.position self.position)
      (set summary-row.layout.rotation self.rotation)
      (set summary-row.layout.depth-offset-index self.depth-offset-index)
      (set summary-row.layout.clip-region self.clip-region)
      (summary-row.layout:layouter)
      (when (and expanded? details-widget)
        (local detail-height (- self.size.y summary-row.layout.measure.y))
        (set details-widget.layout.size
             (glm.vec3 self.size.x (math.max 0 detail-height) self.size.z))
        (local offset (glm.vec3 0 summary-row.layout.measure.y 0))
        (set details-widget.layout.position
             (+ self.position (self.rotation:rotate offset)))
        (set details-widget.layout.rotation self.rotation)
        (set details-widget.layout.depth-offset-index (+ self.depth-offset-index 1))
        (set details-widget.layout.clip-region self.clip-region)
        (details-widget.layout:layouter)))

    (fn visible-children []
      (local children [summary-row.layout])
      (when (and expanded? details-widget)
        (table.insert children details-widget.layout))
      children)

    (set layout
      (Layout {:name "disclosure-row"
               : measurer
               :constrained-measurer measure-row
               : layouter
               :children (visible-children)}))

    (set sync-visible-children
         (fn []
           (layout:set-children (visible-children))))

    (fn on-toggle-visible [self should-expand]
      (set expanded? should-expand)
      (sync-icon)
      (sync-visible-children)
      (toggled:emit expanded?)
      (when self.layout
        (self.layout:mark-measure-dirty)))

    (fn drop [self]
      (self.layout:drop)
      (summary-row:drop)
      (when details-widget
        (details-widget:drop)))

    (local instance
      {:layout layout
       :drop drop
       :summary-row summary-row
       :details-widget details-widget
       :expanded? (fn [_self] expanded?)
       :set-expanded (fn [self should-expand]
                       (on-toggle-visible self should-expand))})

    instance))

DisclosureRow
