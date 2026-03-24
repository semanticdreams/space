(local glm (require :glm))
(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))
(local HeightfieldTargetCapture (require :graph/view/heightfield-target-capture))
(local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))


(fn target->draft-values [target]
  {:picked-target target})

(fn format-target [target]
  (.. (tostring (or target.sample-count (length (or target.samples []))))
      " samples across ["
      (tostring target.x0) ", " (tostring target.z0)
      "] to ["
      (tostring target.x1) ", " (tostring target.z1) "]"))

(fn selection-summary [target]
  (if target
      (format-target target)
      "No samples selected"))

(fn merge-draft-with-target [draft target]
  (if target
      (do
        (local merged {})
        (each [key value (pairs (or draft {}))]
          (set (. merged key) value))
        (each [key value (pairs (target->draft-values target))]
          (set (. merged key) value))
        merged)
      draft))

(fn HeightfieldTargetToolView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local validation (assert options.validation "HeightfieldTargetToolView requires :validation"))
  (local name (assert options.name "HeightfieldTargetToolView requires :name"))
  (local info-text (assert options.info-text "HeightfieldTargetToolView requires :info-text"))
  (local draft-from-record (or options.draft-from-record validation.draft-from-record))
  (local extra-content-builder options.extra-content-builder)

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "HeightfieldTargetToolView requires a build context")
    (var draft
      (merge-draft-with-target
        (draft-from-record (and target target.get-record (target:get-record)))
        (and target target.get-selection-target (target:get-selection-target))))
    (local form
      ((TerrainEditorFormView target {:validation validation
                                      :name name
                                      :apply-when-valid? true
                                      :refresh-on-change? false
                                      :wrap-scroll? false
                                      :read-baseline-draft (fn []
                                                             draft)
                                      :write-baseline-draft (fn [next-draft]
                                                              (set draft next-draft))
                                      :on-draft-changed
                                      (fn [_draft validation-result]
                                        (when target
                                          (if (and validation-result validation-result.ok?)
                                              (do
                                                (when target.set-selection-target
                                                  (target:set-selection-target validation-result.values.target)))
                                              (do
                                                (when target.clear-selection-target
                                                  (target:clear-selection-target))))))
                                      :info-text info-text})
       build-ctx))
    (local selection-label
      ((Text {:text (selection-summary draft.picked-target)
              :color (glm.vec4 0.7 0.7 0.7 1)})
       build-ctx))
    (local pick-status
      ((Text {:text "Pick samples from the scene."
              :color (glm.vec4 0.7 0.7 0.7 1)})
       build-ctx))
    (var pick-button nil)
    (var target-capture nil)
    (var live-scene nil)
    (var live-pick-available? false)
    (var world-changed-handler nil)

    (fn set-pick-status [text]
      (pick-status:set-text text {:mark-measure-dirty? false}))

    (fn set-selection-label [next-target]
      (selection-label:set-text (selection-summary next-target) {:mark-measure-dirty? false}))

    (fn update-pick-ui [active?]
      (when active?
        (set-pick-status "Drag on the terrain in the scene to choose samples.")))

    (fn drop-target-capture []
      (when target-capture
        (TerrainRectPickManager.cleanup-session target-capture)
        (target-capture:drop)
        (set target-capture nil)))

    (fn build-target-capture [scene]
      (HeightfieldTargetCapture {:scene scene
                                 :ctx build-ctx
                                 :terrain-id (and target target.terrain-id)
                                 :on-drag-began (fn []
                                                  (when (and target target.clear-selection-target)
                                                    (target:clear-selection-target)))
                                 :on-target-updated (fn [selection-target _result]
                                                      (if selection-target
                                                          (when (and target target.set-selection-target)
                                                            (target:set-selection-target selection-target))
                                                          (when (and target target.clear-selection-target)
                                                            (target:clear-selection-target))))
                                 :on-target (fn [resolved-target _result]
                                              (form:set-draft-values (target->draft-values resolved-target))
                                              (set-selection-label resolved-target)
                                              (when (and target target.set-selection-target)
                                                (target:set-selection-target resolved-target))
                                              (set-pick-status
                                                (.. "Picked " (format-target resolved-target))))
                                 :on-invalid-target (fn []
                                                      (when (and target target.clear-selection-target)
                                                        (target:clear-selection-target))
                                                      (set-pick-status
                                                        "Drag over this terrain to choose samples."))
                                 :on-canceled (fn []
                                                (when (and target target.clear-selection-target)
                                                  (target:clear-selection-target)))
                                 :on-active-changed (fn [active?]
                                                     (update-pick-ui active?))}))

    (fn refresh-live-pick []
      (local next-live-scene (and target target.get-live-scene (target:get-live-scene)))
      (local next-available? (not (not next-live-scene)))
      (local scene-changed? (not (= next-live-scene live-scene)))
      (set live-scene next-live-scene)
      (set live-pick-available? next-available?)
      (when (and target-capture
                 (target-capture:active?)
                 (not next-available?))
        (TerrainRectPickManager.cancel-active-session))
      (when (or scene-changed? (and target-capture (not next-available?)))
        (drop-target-capture))
      (when (and next-available? (not target-capture))
        (set target-capture (build-target-capture live-scene)))
      (when pick-button
        (pick-button:set-enabled live-pick-available?))
      (when (not (and target-capture (target-capture:active?)))
        (update-pick-ui false)
        (set-pick-status
          (if live-pick-available?
              "Pick samples from the scene."
              "Live sample picking requires this world to be active.")))
      nil)

    (fn toggle-live-pick []
      (refresh-live-pick)
      (if target-capture
          (if (target-capture:active?)
              (TerrainRectPickManager.cancel-active-session)
              (TerrainRectPickManager.begin target-capture))
          (set-pick-status "Live sample picking requires this world to be active.")))

    (set pick-button
         ((Button {:text "Pick Samples"
                   :variant :ghost
                   :enabled? false
                   :on-click (fn [_button _event]
                               (toggle-live-pick))})
          build-ctx))

    (set world-changed-handler
         (and target
              target.world-manager
              target.world-manager.changed
              (target.world-manager.changed:connect
                (fn [_payload]
                  (refresh-live-pick)))))

    (local pick-row
      ((Flex {:axis 1
              :xalign :stretch
              :xspacing 0.4
              :children [(FlexChild (fn [_] pick-status) 1)
                         (FlexChild (fn [_] pick-button) 0)]})
       build-ctx))
    (local extra-content
      (and extra-content-builder
           (extra-content-builder {:ctx build-ctx
                                   :form form
                                   :target target})))

    (local content-children
      [(FlexChild (fn [_] selection-label) 0)
       (FlexChild (fn [_] pick-row) 0)])
    (when extra-content
      (table.insert content-children (FlexChild (fn [_] extra-content) 0)))
    (table.insert content-children (FlexChild (fn [_] form) 1))

    (local content
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children content-children})
       build-ctx))
    (local root-entity
      ((ScrollView {:child (fn [_] content)
                    :padding false
                    :scrollbar-policy :as-needed
                    :name name})
       build-ctx))

    (refresh-live-pick)

    {:layout root-entity.layout
     :form form
     :fields form.fields
     :error-labels form.error-labels
     :status-label form.status-label
     :apply-button form.apply-button
     :selection-label selection-label
     :pick-button pick-button
     :pick-status pick-status
     :scroll-view root-entity
     :extra-content extra-content
     :drop (fn [_self]
             (when (and target
                        target.world-manager
                        target.world-manager.changed
                        world-changed-handler)
               (target.world-manager.changed:disconnect world-changed-handler true)
               (set world-changed-handler nil))
             (drop-target-capture)
             (root-entity:drop))})
  build)

{:HeightfieldTargetToolView HeightfieldTargetToolView
 :target->draft-values target->draft-values}
