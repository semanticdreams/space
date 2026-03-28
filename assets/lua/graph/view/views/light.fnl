(local LightEditorValidation (require :graph/light-editor-validation))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))

(fn info-text [target]
  (.. "Editing "
      (or (and target target.type-key) "light")
      " light "
      (or (and target target.light-id) "?")))

(fn LightNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local validation
    (LightEditorValidation.validation-for-type (and target target.type-key)))
  (local action-buttons
    (if (and target target.removable? (target:removable?))
        [{:key :remove
          :text "Remove"
          :variant :ghost
          :on-click (fn [_payload]
                      (when (and target target.remove-light)
                        (assert (target:remove-light)
                                (.. "Failed to remove light "
                                    (or (and target target.light-id) "?")))
                        (when (and target.graph target.graph.remove-nodes)
                          (target.graph:remove-nodes [target]))))}]
        []))
  (TerrainEditorFormView target {:validation validation
                                 :name "light-node-view"
                                 :info-text (info-text target)
                                 :action-buttons action-buttons}))

LightNodeView
