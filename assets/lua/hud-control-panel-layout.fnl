(local glm (require :glm))
(local {: Layout} (require :layout))
(local {: Flex : FlexChild} (require :flex))
(local Padding (require :padding))
(local Card (require :card))

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
  (local title-builder (assert options.title-builder "ControlPanelLayout requires :title-builder"))
  (local status-builder (assert options.status-builder "ControlPanelLayout requires :status-builder"))
  (local button-row-builder (assert options.button-row-builder "ControlPanelLayout requires :button-row-builder"))
  (fn build [ctx]
    (local spacer (make-flex-spacer))
    ((Card
       {:child
        (Padding
          {:edge-insets [0.6 0.4]
           :child
           (Flex
             {:axis 1
              :xspacing 0.5
              :yalign :center
              :children
              [(FlexChild (Padding {:child title-builder
                                    :edge-insets [0.1 0.1]}))
               (FlexChild (Padding {:child status-builder
                                    :edge-insets [0.1 0.1]}))
               (FlexChild spacer 1)
               (FlexChild button-row-builder)]})})})
     ctx)))

{:ControlPanelLayout ControlPanelLayout}
