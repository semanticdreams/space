(local BackgroundValidation (require :graph/background-validation))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))

(fn info-text [target]
  (.. "Editing world background for "
      (or (and target target.world-id) "?")))

(fn BackgroundNodeView [node opts]
  (local options (or opts {}))
  (local target (assert (or node options.node) "BackgroundNodeView requires target node"))
  (local validation (BackgroundValidation.create-validation))
  (TerrainEditorFormView target {:validation validation
                                 :name "background-node-view"
                                 :info-text (info-text target)}))

BackgroundNodeView
