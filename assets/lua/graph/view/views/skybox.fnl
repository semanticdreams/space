(local SkyboxValidation (require :graph/skybox-validation))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))

(fn info-text [target]
  (.. "Editing world skybox for "
      (or (and target target.world-id) "?")))

(fn SkyboxNodeView [node opts]
  (local options (or opts {}))
  (local target (assert (or node options.node) "SkyboxNodeView requires target node"))
  (local validation
    (SkyboxValidation.create-validation
      ((assert target.available-items "SkyboxNodeView requires target.available-items")
       target)))
  (TerrainEditorFormView target {:validation validation
                                 :name "skybox-node-view"
                                 :info-text (info-text target)}))

SkyboxNodeView
