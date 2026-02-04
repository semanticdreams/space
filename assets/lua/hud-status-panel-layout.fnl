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

(fn StatusPanelLayout [opts]
  (local options (or opts {}))
  (local state-builder (assert options.state-builder "StatusPanelLayout requires :state-builder"))
  (local focus-builder (assert options.focus-builder "StatusPanelLayout requires :focus-builder"))
  (fn build [ctx]
    (local spacer (make-flex-spacer))
    (local state-column
      (Flex
        {:axis 2
         :xalign :start
         :yalign :start
         :yspacing 0.1
         :children [(FlexChild (Padding {:edge-insets [0.1 0.1]
                                         :child state-builder}))]}))
    (local focus-column
      (Flex
        {:axis 2
         :xalign :end
         :yalign :start
         :yspacing 0.1
         :children [(FlexChild (Padding {:edge-insets [0.1 0.1]
                                         :child focus-builder}))]}))
    (local children
      [(FlexChild state-column)
       (FlexChild spacer 1)
       (FlexChild focus-column)])
    ((Card
       {:child
        (Padding
          {:edge-insets [0.6 0.4]
           :child (Flex {:axis 1
                         :xspacing 0.4
                         :yalign :center
                         :children children})})})
     ctx)))

{:StatusPanelLayout StatusPanelLayout}
