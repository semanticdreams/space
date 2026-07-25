(fn drawing-root-actions [context]
  (local controller (and context.drawing context.drawing.controller))
  (local actions [])
  (when controller
    (table.insert actions
                  {:name "Add Vector Layer"
                   :icon "draw"
                   :fn (fn [_button _event]
                         (controller:add-layer "vector"))})
    (table.insert actions
                  {:name "Add Raster Layer"
                   :icon "brush"
                   :fn (fn [_button _event]
                         (controller:add-layer "raster"))})
    (table.insert actions
                  {:name "Duplicate Layer"
                   :icon "layers"
                   :fn (fn [_button _event]
                         (controller:duplicate-active-layer))})
    (when (> (or context.drawing.layer-count 0) 1)
      (table.insert actions
                    {:name "Delete Active Layer"
                     :icon "delete"
                     :variant :danger
                     :fn (fn [_button _event]
                           (controller:delete-active-layer))})))
  actions)

(fn drawing-selection-actions [context]
  (local controller (and context.drawing context.drawing.controller))
  (if (and controller
           context.drawing.has-selection?)
      [{:name "Delete Selection"
        :icon "delete"
        :variant :danger
        :fn (fn [_button _event]
              (controller:on-delete-selection))}]
      []))

{:drawing-root-actions drawing-root-actions
 :drawing-selection-actions drawing-selection-actions}
