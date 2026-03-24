(local Validation (require :graph/heightfield-resize-tool-validation))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))

(fn HeightfieldResizeToolNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (var draft (Validation.draft-from-record (and target target.get-record (target:get-record))))
    ((TerrainEditorFormView target {:validation Validation
                                    :name "heightfield-resize-tool-view"
                                    :apply-when-valid? true
                                    :refresh-on-change? false
                                    :read-baseline-draft (fn []
                                                           draft)
                                    :write-baseline-draft (fn [next-draft]
                                                            (set draft next-draft))
                                    :info-text "Resize chunk coverage. [0,0] to [0,0] means one chunk. Existing chunks are preserved."})
     ctx)))

HeightfieldResizeToolNodeView
