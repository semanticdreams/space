(local glm (require :glm))
(local Validation (require :graph/heightfield-adjust-tool-validation))
(local {:HeightfieldTargetToolView HeightfieldTargetToolView} (require :graph/view/heightfield-target-tool-view))
(local HeightfieldPaintCapture (require :graph/view/heightfield-paint-capture))
(local TerrainPaintManager (require :graph/view/terrain-paint-manager))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn create-live-paint-controls [target build-ctx form]
  (var paint-button nil)
  (var paint-capture nil)
  (var live-scene nil)
  (var live-paint-available? false)
  (var world-changed-handler nil)
  (local paint-status
    ((Text {:text "Live painting requires this world to be active."
            :color (glm.vec4 0.7 0.7 0.7 1)})
     build-ctx))

  (fn set-paint-status [text]
    (paint-status:set-text text {:mark-measure-dirty? false}))

  (fn update-paint-ui [active?]
    (when active?
      (set-paint-status "Drag on the terrain to paint single-sample raise/lower edits.")))

  (fn drop-paint-capture []
    (when paint-capture
      (when (= (TerrainPaintManager.active-session) paint-capture)
        (TerrainPaintManager.cancel-active-session))
      (paint-capture:drop)
      (set paint-capture nil)))

  (fn build-paint-capture [scene]
    (HeightfieldPaintCapture {:scene scene
                              :terrain-id (and target target.terrain-id)
                              :on-stamp-batch (fn [sample-targets _hit]
                                                (local draft (form:get-draft))
                                                (local delta-result (Validation.validate-field :delta draft.delta))
                                                (if delta-result.ok?
                                                    (do
                                                      (target:apply-stroke-values {:targets sample-targets
                                                                                   :delta delta-result.value})
                                                      (set-paint-status
                                                        (.. "Stamped "
                                                            (tostring (length sample-targets))
                                                            " live terrain sample"
                                                            (if (= (length sample-targets) 1) "." "s."))))
                                                    (set-paint-status "Fix Height Delta before live painting.")))
                              :on-invalid-target (fn []
                                                   (set-paint-status "Drag over this terrain to paint."))
                              :on-active-changed update-paint-ui}))

  (fn refresh-live-paint []
    (local next-live-scene (and target target.get-live-scene (target:get-live-scene)))
    (local next-available? (not (not next-live-scene)))
    (local scene-changed? (not (= next-live-scene live-scene)))
    (set live-scene next-live-scene)
    (set live-paint-available? next-available?)
    (when (or scene-changed? (and paint-capture (not next-available?)))
      (drop-paint-capture))
    (when (and next-available? (not paint-capture))
      (set paint-capture (build-paint-capture live-scene)))
    (when paint-button
      (paint-button:set-enabled live-paint-available?))
    (when (not (and paint-capture (paint-capture:active?)))
      (update-paint-ui false)
      (set-paint-status
        (if live-paint-available?
            "Paint single samples directly in the scene."
            "Live painting requires this world to be active."))))

  (fn toggle-live-paint []
    (refresh-live-paint)
    (if paint-capture
        (if (paint-capture:active?)
            (TerrainPaintManager.cancel-active-session)
            (TerrainPaintManager.begin paint-capture))
        (set-paint-status "Live painting requires this world to be active.")))

  (set paint-button
       ((Button {:text "Paint Raise/Lower"
                 :variant :ghost
                 :enabled? false
                 :on-click (fn [_button _event]
                             (toggle-live-paint))})
        build-ctx))

  (set world-changed-handler
       (and target
            target.world-manager
            target.world-manager.changed
            (target.world-manager.changed:connect
              (fn [_payload]
                (refresh-live-paint)))))

  (local row
    ((Flex {:axis 1
            :xalign :stretch
            :xspacing 0.4
            :children [(FlexChild (fn [_] paint-status) 1)
                       (FlexChild (fn [_] paint-button) 0)]})
     build-ctx))

  (refresh-live-paint)

  {:layout row.layout
     :paint-button paint-button
     :paint-status paint-status
     :drop (fn [_self]
             (when (and target
                        target.world-manager
                        target.world-manager.changed
                        world-changed-handler)
               (target.world-manager.changed:disconnect world-changed-handler true)
               (set world-changed-handler nil))
             (when paint-capture
               (paint-capture:drop))
             (row:drop))})

(fn HeightfieldAdjustToolNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (local view
      ((HeightfieldTargetToolView target {:validation Validation
                                          :name "heightfield-adjust-tool-view"
                                          :info-text "Raise or lower the selected target."
                                          :extra-content-builder (fn [build-opts]
                                                                   (create-live-paint-controls
                                                                     target
                                                                     build-opts.ctx
                                                                     build-opts.form))})
       ctx))
    (when view.extra-content
      (set view.paint-button view.extra-content.paint-button)
      (set view.paint-status view.extra-content.paint-status))
    view))

HeightfieldAdjustToolNodeView
