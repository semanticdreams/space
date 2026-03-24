(local Validation (require :graph/heightfield-terrain-editor-validation))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))

(fn HeightfieldTerrainNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (TerrainEditorFormView target {:validation Validation
                                 :name "heightfield-terrain-node-view"
                                 :info-text "Edit terrain properties."}))

HeightfieldTerrainNodeView
