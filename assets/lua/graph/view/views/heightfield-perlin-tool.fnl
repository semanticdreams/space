(local Validation (require :graph/heightfield-perlin-tool-validation))
(local {:HeightfieldTargetToolView HeightfieldTargetToolView} (require :graph/view/heightfield-target-tool-view))

(fn HeightfieldPerlinToolNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    ((HeightfieldTargetToolView target {:validation Validation
                                        :name "heightfield-perlin-tool-view"
                                        :info-text "Apply perlin to the selected target."})
     ctx)))

HeightfieldPerlinToolNodeView
