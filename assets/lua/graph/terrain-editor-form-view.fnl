(local glm (require :glm))
(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local {:Grid Grid} (require :grid))
(local Input (require :input))
(local Text (require :text))
(local TextStyle (require :text-style))
(local FormComboBox (require :graph/view/widgets/form-combo-box))

(fn make-field [ctx opts]
  (if opts.items
      (FormComboBox ctx {:name opts.name
                         :items opts.items
                         :value opts.text
                         :placeholder (or opts.placeholder "")
                         :on-change (or opts.on-change (fn [_input _text] nil))})
      ((Input {:text (or opts.text "")
               :placeholder (or opts.placeholder "")
               :on-change (or opts.on-change (fn [_input _text] nil))})
       ctx)))

(fn make-error-label [ctx]
  ((Text {:text ""
          :style (TextStyle {:color (glm.vec4 0.92 0.38 0.38 1)})})
   ctx))

(fn make-status-label [ctx]
  ((Text {:text "No pending changes"
          :style (TextStyle {:color (glm.vec4 0.7 0.7 0.7 1)})})
   ctx))

(fn set-field-text [field value]
  (if field.set-value
      (field:set-value value)
      (field:set-text (or value "") {:mark-measure-dirty? false})))

(fn sync-errors! [validation draft errors error-labels set-error-label]
  (local validation-result (validation.validate-draft draft))
  (each [_ spec (ipairs validation.field-specs)]
    (local message (. validation-result.errors spec.key))
    (set (. errors spec.key) message)
    (set-error-label spec.key message))
  validation-result)

(fn count-errors [validation errors]
  (var total 0)
  (each [_ spec (ipairs validation.field-specs)]
    (when (. errors spec.key)
      (set total (+ total 1))))
  total)

(fn TerrainEditorFormView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local validation (assert options.validation "TerrainEditorFormView requires :validation"))
  (local info-text (assert options.info-text "TerrainEditorFormView requires :info-text"))
  (local name (or options.name "terrain-editor-form-view"))
  (local wrap-scroll? (if (= options.wrap-scroll? nil) true (not (not options.wrap-scroll?))))
  (local refresh-on-change? (if (= options.refresh-on-change? nil) true (not (not options.refresh-on-change?))))
  (local apply-when-valid? (if (= options.apply-when-valid? nil) false (not (not options.apply-when-valid?))))
  (local on-draft-changed (or options.on-draft-changed (fn [_draft _validation-result] nil)))

  (fn clone-table [value]
    (if (= (type value) :table)
        (do
          (local out {})
          (each [k v (pairs value)]
            (set (. out k) (clone-table v)))
          out)
        value))

  (fn baseline-draft []
    (if options.read-baseline-draft
        (clone-table (options.read-baseline-draft))
        (validation.draft-from-record (and target target.get-record (target:get-record)))))

  (fn store-baseline-draft! [draft]
    (when options.write-baseline-draft
      (options.write-baseline-draft (clone-table draft))))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "TerrainEditorFormView requires a build context")
    (local view {})
    (local fields {})
    (local error-labels {})
    (var draft (baseline-draft))
    (local errors {})
    (var syncing? false)
    (var applied? false)
    (var apply-failed? false)
    (var pending-apply? false)

    (local status-label (make-status-label build-ctx))
    (local info-label ((Text {:text info-text}) build-ctx))

    (fn set-error-label [field-key message]
      (local label (. error-labels field-key))
      (when label
        (label:set-text (or message "") {:mark-measure-dirty? false})))

    (fn update-status-and-actions []
      (local current-draft (baseline-draft))
      (local dirty? (not (validation.draft-equals? draft current-draft)))
      (local validation-result
        (if apply-when-valid?
            (validation.validate-draft draft)
            nil))
      (local error-count
        (if validation-result
            validation-result.error-count
            (count-errors validation errors)))
      (local can-apply?
        (if apply-when-valid?
            validation-result.ok?
            dirty?))
      (view.apply-button:set-enabled can-apply?)
      (if apply-failed?
          (status-label:set-text "Apply failed" {:mark-measure-dirty? false})
          (if (> error-count 0)
              (status-label:set-text
                (.. "Fix " (tostring error-count) " invalid field" (if (= error-count 1) "" "s") " before applying")
                {:mark-measure-dirty? false})
              (if apply-when-valid?
                  (if applied?
                      (status-label:set-text "Applied" {:mark-measure-dirty? false})
                      (status-label:set-text "Ready to apply" {:mark-measure-dirty? false}))
                  (if dirty?
                  (status-label:set-text "Unsaved changes" {:mark-measure-dirty? false})
                  (if applied?
                      (status-label:set-text "Applied" {:mark-measure-dirty? false})
                      (status-label:set-text "No pending changes" {:mark-measure-dirty? false})))))))

    (fn refresh-from-target [refresh-opts]
      (local refresh-options (or refresh-opts {}))
      (set syncing? true)
      (set draft (baseline-draft))
      (each [_ spec (ipairs validation.field-specs)]
        (set-field-text (. fields spec.key) (. draft spec.key))
        (set (. errors spec.key) nil)
        (set-error-label spec.key nil))
      (set applied? (not (= refresh-options.applied? false)))
      (set apply-failed? false)
      (set syncing? false)
      (update-status-and-actions))

    (fn handle-field-change [field-key text]
      (when (not syncing?)
        (set (. draft field-key) text)
        (var draft-validation-result nil)
        (if apply-when-valid?
            (set draft-validation-result
                 (sync-errors! validation draft errors error-labels set-error-label))
            (when (. errors field-key)
              (local field-result (validation.validate-field field-key text))
              (if field-result.ok?
                  (do
                    (set (. errors field-key) nil)
                    (set-error-label field-key nil))
                  (do
                    (set (. errors field-key) field-result.error)
                    (set-error-label field-key field-result.error)))))
        (set applied? false)
        (set apply-failed? false)
        (update-status-and-actions)
        (on-draft-changed (clone-table draft)
                          (or draft-validation-result
                              (validation.validate-draft draft)))))

    (fn sync-visible-fields [field-keys]
      (each [_ key (ipairs field-keys)]
        (set-field-text (. fields key) (. draft key))))

    (fn sync-validation-state []
      (if apply-when-valid?
          (sync-errors! validation draft errors error-labels set-error-label)
          (each [_ spec (ipairs validation.field-specs)]
            (local key spec.key)
            (local result (validation.validate-field key (. draft key)))
            (if result.ok?
                (do
                  (set (. errors key) nil)
                  (set-error-label key nil))
                (do
                  (set (. errors key) result.error)
                  (set-error-label key result.error))))))

    (each [_ spec (ipairs validation.field-specs)]
      (set (. fields spec.key)
           (make-field build-ctx {:name (.. name "-" (tostring spec.key))
                                  :items spec.items
                                  :placeholder spec.placeholder
                                  :on-change (fn [_input text]
                                               (handle-field-change spec.key text))}))
      (set (. error-labels spec.key) (make-error-label build-ctx)))

    (local changed-signal (and target target.changed))

    (local apply-button
      ((Button {:text "Apply"
                :enabled? false
                :on-click (fn [_button _event]
                            (local result (validation.validate-draft draft))
                            (set applied? false)
                            (set apply-failed? false)
                            (each [_ spec (ipairs validation.field-specs)]
                              (local message (. result.errors spec.key))
                              (set (. errors spec.key) message)
                              (set-error-label spec.key message))
                            (if result.ok?
                                (do
                                  (set pending-apply? true)
                                  (local updated
                                    (if (and target target.apply-values)
                                        (target:apply-values result.values)
                                        nil))
                                  (if updated
                                      (when (or (not changed-signal)
                                                (not refresh-on-change?))
                                        (set pending-apply? false)
                                        (store-baseline-draft! draft)
                                        (refresh-from-target {:applied? true}))
                                      (do
                                        (set pending-apply? false)
                                        (set apply-failed? true)
                                        (update-status-and-actions))))
                                (update-status-and-actions)))})
       build-ctx))
    (set view.apply-button apply-button)

    (local field-widgets {})
    (each [_ spec (ipairs validation.field-specs)]
      (local field-key spec.key)
      (set (. field-widgets field-key)
           ((Flex {:axis 2
                   :xalign :stretch
                   :yspacing 0.15
                   :children [(FlexChild (fn [_] (. fields field-key)) 0)
                              (FlexChild (fn [_] (. error-labels field-key)) 0)]})
            build-ctx)))

    (local grid-children [])
    (each [_ spec (ipairs validation.field-specs)]
      (local field-label spec.label)
      (table.insert grid-children {:widget (fn [child-ctx] ((Text {:text field-label}) child-ctx))
                                   :align-y :end}))
    (each [_ spec (ipairs validation.field-specs)]
      (local field-key spec.key)
      (table.insert grid-children {:widget (fn [_] (. field-widgets field-key))
                                   :align-x :stretch}))

    (local grid
      ((Grid {:rows (length validation.field-specs)
              :columns 2
              :xmode :even
              :ymode :tight
              :align-x :stretch
              :align-y :start
              :xspacing 0.8
              :yspacing 0.4
              :column-specs [{:flex 0}
                             {:flex 1}]
              :children grid-children})
       build-ctx))

    (local action-row
      ((Flex {:axis 1
              :xalign :stretch
              :xspacing 0.4
              :children [(FlexChild (fn [_] status-label) 1)
                         (FlexChild (fn [_] apply-button) 0)]})
       build-ctx))

    (local content
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (fn [_] info-label) 0)
                         (FlexChild (fn [_] grid) 1)
                         (FlexChild (fn [_] action-row) 0)]})
       build-ctx))
    (local changed-handler
      (and changed-signal
           refresh-on-change?
           (fn [_payload]
             (local applied-change? pending-apply?)
             (set pending-apply? false)
             (refresh-from-target {:applied? applied-change?}))))
    (when changed-handler
      (changed-signal:connect changed-handler))

    (refresh-from-target {:applied? false})

    (local root-entity
      (if wrap-scroll?
          ((ScrollView {:child (fn [_] content)
                        :padding false
                        :scrollbar-policy :as-needed
                        :name name})
           build-ctx)
          {:layout content.layout
           :drop (fn [_self]
                   (content:drop))}))

    (set view.layout root-entity.layout)
    (set view.fields fields)
    (set view.error-labels error-labels)
    (set view.status-label status-label)
    (set view.get-draft
         (fn [_self]
           (clone-table draft)))
    (set view.set-draft-values
         (fn [_self next-values]
           (local keys [])
           (each [key value (pairs (or next-values {}))]
             (set (. draft key) value)
             (table.insert keys key))
           (set syncing? true)
           (sync-visible-fields keys)
           (set syncing? false)
           (sync-validation-state)
           (set applied? false)
           (set apply-failed? false)
           (update-status-and-actions)
           (on-draft-changed (clone-table draft)
                             (validation.validate-draft draft))))
    (when wrap-scroll?
      (set view.scroll-view root-entity))
    (set view.drop
         (fn [_self]
           (when changed-signal
             (changed-signal:disconnect changed-handler true))
           (root-entity:drop)))
    view)

  build)

TerrainEditorFormView
