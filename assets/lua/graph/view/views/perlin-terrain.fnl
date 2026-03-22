(local Validation (require :graph/perlin-terrain-editor-validation))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))

(fn PerlinTerrainNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (TerrainEditorFormView target {:validation Validation
                                 :name "perlin-terrain-node-view"
                                 :info-text (.. "Editing perlin terrain "
                                                (or (and target target.terrain-id) "?"))}))

PerlinTerrainNodeView
