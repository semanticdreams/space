(local Validation (require :graph/heightfield-flat-tool-validation))
(local {:HeightfieldTargetToolView HeightfieldTargetToolView} (require :graph/view/heightfield-target-tool-view))

(fn HeightfieldFlatToolNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    ((HeightfieldTargetToolView target {:validation Validation
                                        :name "heightfield-flat-tool-view"
                                        :info-text "Fill the selected target with one height."})
     ctx)))

HeightfieldFlatToolNodeView
