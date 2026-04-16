(local SearchView (require :search-view))
(local Button (require :button))
(local ComboBox (require :combo-box))
(local {: Flex : FlexChild} (require :flex))
(local TerrainRecords (require :scene-terrain-records))

(fn kind-items [target]
  (icollect [_ kind (ipairs (or (and target target.supported-terrain-kinds) []))]
    (do
      (local spec (TerrainRecords.terrain-kind-spec kind))
      [kind (or (and spec spec.label) kind)])))

(fn TerrainsNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local items (or options.items []))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "TerrainsNodeView requires a build context")
    (local view {})
    (local terrain-kind-items (kind-items target))
    (local kind-picker
      ((ComboBox {:name "terrains-node-kind-picker"
                  :items terrain-kind-items
                  :value (and (> (length terrain-kind-items) 0)
                              (. (. terrain-kind-items 1) 1))
                  :placeholder "Terrain kind"})
       build-ctx))
    (local add-button
      ((Button {:text "Add Terrain"
                :variant :ghost
                :enabled? (and (> (length terrain-kind-items) 0)
                               (not (not (and target target.add-terrain))))
                :on-click (fn [_button _event]
                            (local selected-kind (and kind-picker (kind-picker:get-value)))
                            (when (and target target.add-terrain selected-kind)
                              (target:add-terrain selected-kind)))})
       build-ctx))
    (local actions-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] kind-picker) 1)
                         (FlexChild (fn [_] add-button) 0)]})
       build-ctx))
    (local search
      ((SearchView {:items []
                    :name "terrains-node-view"
                    :num-per-page 10
                    :builder (fn [item child-ctx]
                               (local label (tostring (. item 2)))
                               ((Button {:text label
                                         :variant :ghost
                                         :on-click (fn [_button _event]
                                                     (when (and target target.open-terrain-node)
                                                       (target:open-terrain-node (. item 1))))})
                                child-ctx))})
       build-ctx))
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] actions-row) 0)
                         (FlexChild (fn [_] search) 1)]})
       build-ctx))
    (set view.kind-picker kind-picker)
    (set view.add-button add-button)
    (set view.search search)
    (set view.layout flex.layout)
    (set view.set-items
         (fn [_self new-items]
           (search:set-items new-items)))
    (set view.refresh-items
         (fn [self]
           (local refreshed
             (if (and target target.emit-items)
                 (target:emit-items)
                 items))
           (self:set-items refreshed)
           (when self.search
             (set self.search.items refreshed))))
    (local items-signal (and target target.items-changed))
    (local items-handler
      (and items-signal
           (fn [new-items]
             (view:set-items new-items))))
    (when items-signal
      (items-signal:connect items-handler))
    (set view.drop
         (fn [_self]
           (when items-signal
             (items-signal:disconnect items-handler true))
           (flex:drop)))
    (search.submitted:connect
      (fn [item]
        (when (and target target.open-terrain-node item)
          (target:open-terrain-node (. item 1)))))
    (view:refresh-items)
    view))
TerrainsNodeView
