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
    (var details-widget nil)
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

    (fn ensure-details-widget []
      (when (and opts.details expanded? (not details-widget))
        (set details-widget (opts.details ctx)))
      details-widget)

    (fn drop-details-widget []
      (when details-widget
        (details-widget:drop)
        (set details-widget nil)))

    (fn measurer [self]
      (summary-row.layout:measurer)
      (local m summary-row.layout.measure)
      (var height m.y)
      (var width m.x)
      (var depth m.z)
      (local details (ensure-details-widget))
      (when (and expanded? details)
        (details.layout:measurer)
        (set height (+ height details.layout.measure.y))
        (when (> details.layout.measure.x width)
          (set width details.layout.measure.x))
        (when (> details.layout.measure.z depth)
          (set depth details.layout.measure.z)))
      (set self.measure (glm.vec3 width height depth)))

    (fn measure-row [self constraints]
      (summary-row.layout:measure-constrained constraints)
      (local m summary-row.layout.measure)
      (var height m.y)
      (var width m.x)
      (var depth m.z)
      (local details (ensure-details-widget))
      (when (and expanded? details)
        (details.layout:measure-constrained constraints)
        (set height (+ height details.layout.measure.y))
        (when (> details.layout.measure.x width)
          (set width details.layout.measure.x))
        (when (> details.layout.measure.z depth)
          (set depth details.layout.measure.z)))
      (set self.measure (glm.vec3 width height depth)))

    (fn layouter [self]
      (set summary-row.layout.size
           (glm.vec3 self.size.x summary-row.layout.measure.y self.size.z))
      (set summary-row.layout.position self.position)
      (set summary-row.layout.rotation self.rotation)
      (set summary-row.layout.depth-offset-index self.depth-offset-index)
      (set summary-row.layout.clip-region self.clip-region)
      (summary-row.layout:layouter)
      (local details (ensure-details-widget))
      (when (and expanded? details)
        (local detail-height (- self.size.y summary-row.layout.measure.y))
        (set details.layout.size
             (glm.vec3 self.size.x (math.max 0 detail-height) self.size.z))
        (local offset (glm.vec3 0 summary-row.layout.measure.y 0))
        (set details.layout.position
             (+ self.position (self.rotation:rotate offset)))
        (set details.layout.rotation self.rotation)
        (set details.layout.depth-offset-index (+ self.depth-offset-index 1))
        (set details.layout.clip-region self.clip-region)
        (details.layout:layouter)))

    (fn visible-children []
      (local children [summary-row.layout])
      (local details (ensure-details-widget))
      (when (and expanded? details)
        (table.insert children details.layout))
      children)

    (set layout
      (Layout {:name "disclosure-row"
               : measurer
               :constrained-measurer measure-row
               : layouter
               :children (visible-children)}))

    (set sync-visible-children
         (fn []
           (when (not expanded?)
             (drop-details-widget))
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
      (drop-details-widget))

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
