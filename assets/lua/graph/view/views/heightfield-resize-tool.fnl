(local Validation (require :graph/heightfield-resize-tool-validation))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))
(local TerrainIssueLog (require :terrain-issue-log))

(fn value-text [table-value key]
  (tostring (and table-value (. table-value key))))

(fn format-record-bounds [record]
  (local bounds (Validation.chunk-bounds record))
  (if (= (length (or (and record record.chunks) [])) 0)
      "empty"
      (string.format "[%s,%s..%s,%s]"
                     (tostring bounds.min-chunk-x)
                     (tostring bounds.min-chunk-z)
                     (tostring bounds.max-chunk-x)
                     (tostring bounds.max-chunk-z))))

(fn format-range [range-values]
  (string.format "[%s,%s..%s,%s]"
                 (value-text range-values :min-chunk-x)
                 (value-text range-values :min-chunk-z)
                 (value-text range-values :max-chunk-x)
                 (value-text range-values :max-chunk-z)))

(fn log-apply-attempt [target payload]
  (local record (and target target.get-record (target:get-record)))
  (local visible-fields (or payload.visible-fields {}))
  (local draft (or payload.draft {}))
  (local validation-result (or payload.validation-result {}))
  (local parsed-fields (or validation-result.values {}))
  (TerrainIssueLog.info
    (string.format
      "[terrain-resize] apply-attempt terrain=%s valid=%s errors=%s visible=%s draft=%s parsed=%s fill=[visible=%s draft=%s parsed=%s] record-bounds=%s chunk-count=%s"
      (tostring (and target target.terrain-id))
      (tostring validation-result.ok?)
      (tostring validation-result.error-count)
      (format-range visible-fields)
      (format-range draft)
      (format-range parsed-fields)
      (value-text visible-fields :fill-height)
      (value-text draft :fill-height)
      (value-text parsed-fields :fill-height)
      (format-record-bounds record)
      (tostring (length (or (and record record.chunks) [])))))
  (when (or (not (= (or visible-fields.min-chunk-x "") (or draft.min-chunk-x "")))
            (not (= (or visible-fields.min-chunk-z "") (or draft.min-chunk-z "")))
            (not (= (or visible-fields.max-chunk-x "") (or draft.max-chunk-x "")))
            (not (= (or visible-fields.max-chunk-z "") (or draft.max-chunk-z "")))
            (not (= (or visible-fields.fill-height "") (or draft.fill-height ""))))
    (TerrainIssueLog.warn
      (string.format
        "[terrain-resize] visible-field-mismatch terrain=%s visible=%s draft=%s fill=[visible=%s draft=%s]"
        (tostring (and target target.terrain-id))
        (format-range visible-fields)
        (format-range draft)
        (value-text visible-fields :fill-height)
        (value-text draft :fill-height)))))

(fn HeightfieldResizeToolNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (var draft (Validation.draft-from-record (and target target.get-record (target:get-record))))
    ((TerrainEditorFormView target {:validation Validation
                                    :name "heightfield-resize-tool-view"
                                    :action-buttons
                                    [{:key :center-on-origin
                                      :view-key :center-on-origin-button
                                      :text "Center On Origin"
                                      :enabled? (fn [state]
                                                  (local result (Validation.validate-draft state.draft))
                                                  (not (not (and target
                                                                 target.apply-values-centered-on-origin
                                                                 result.ok?))))
                                      :on-click (fn [state]
                                                  (log-apply-attempt target {:draft state.draft
                                                                             :visible-fields state.visible-fields
                                                                             :validation-result state.validation-result})
                                                  (local result state.validation-result)
                                                  (when (and result.ok?
                                                             target
                                                             target.apply-values-centered-on-origin)
                                                    (target:apply-values-centered-on-origin result.values)))}]
                                    :apply-when-valid? true
                                    :refresh-on-change? false
                                    :on-apply-attempt (fn [payload]
                                                        (log-apply-attempt target payload))
                                    :read-baseline-draft (fn []
                                                           draft)
                                    :write-baseline-draft (fn [next-draft]
                                                            (set draft next-draft))
                                    :info-text "Resize chunk coverage. [0,0] to [0,0] means one chunk. Existing chunks are preserved."})
     ctx)))

HeightfieldResizeToolNodeView
