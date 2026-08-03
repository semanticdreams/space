(local glm (require :glm))
(local {: Layout} (require :layout))
(local {: Flex : FlexChild} (require :flex))
(local Padding (require :padding))
(local Card (require :card))
(local HudChromeMetrics (require :hud-chrome-metrics))

(fn make-flex-spacer []
  (fn build [_ctx]
    (local layout
      (Layout {:name "flex-spacer"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 0 0 0)))
               :layouter (fn [_self] nil)}))
    (fn drop [self]
      (self.layout:drop))
    {:layout layout :drop drop}))

(fn ControlPanelLayout [opts]
  (local options (or opts {}))
  (local title-builder options.title-builder)
  (local status-builder (assert options.status-builder "ControlPanelLayout requires :status-builder"))
  (local button-row-builder (assert options.button-row-builder "ControlPanelLayout requires :button-row-builder"))
  (local body-builder options.body-builder)
  (fn build [ctx]
    (local spacer (make-flex-spacer))
    (local children [])
    (when title-builder
      (table.insert children (FlexChild title-builder)))
    (table.insert children (FlexChild status-builder))
    (when body-builder
      (table.insert children (FlexChild body-builder)))
    (table.insert children (FlexChild spacer 1))
    (table.insert children (FlexChild button-row-builder))
    ((Card
       {:child
        (Padding
          {:edge-insets HudChromeMetrics.button-owned-shell-padding
           :child
           (Flex
             {:axis 1
              :xspacing HudChromeMetrics.control-row-spacing
              :yalign :center
              :children children})})})
     ctx)))

{:ControlPanelLayout ControlPanelLayout}
