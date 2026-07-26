(local glm (require :glm))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local Stack (require :stack))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn GraphMapSidebar [opts]
    (local options (or opts {}))
    (local manager (assert options.manager "GraphMapSidebar requires :manager"))
    (local selected-count-provider options.selected-count-provider)

    (fn build [ctx]
        (var root-layout nil)
        (var content-entity nil)
        (var rebuild-requested? false)
        (var maps-changed-handler nil)
        (var active-map nil)
        (var active-node-added-handler nil)
        (var active-node-removed-handler nil)
        (var active-node-replaced-handler nil)
        (var active-edge-added-handler nil)
        (var active-edge-removed-handler nil)
        (var visible-labels [])
        (var last-selected-count nil)
        (assert ctx.clickables "GraphMapSidebar requires ctx.clickables")
        (local theme (and ctx ctx.theme))

        (fn record-label [label]
            (table.insert visible-labels label)
            label)

        (fn current-selected-count []
            (if selected-count-provider
                (selected-count-provider)
                0))

        (fn panel-bg []
            (local card-theme (and theme theme.card))
            (or (and card-theme card-theme.background)
                (glm.vec4 0.12 0.14 0.18 0.96)))

        (fn text-builder [label color scale]
            (record-label label)
            (fn [ic] ((Text {:text label :color color :scale (or scale 0.82)}) ic)))

        (fn drop-content []
            (when content-entity
                (when (and content-entity.drop content-entity)
                    (content-entity:drop))
                (set content-entity nil)))

        (fn request-rebuild [_payload]
            (set rebuild-requested? true))

        (fn disconnect-active-map []
            (when active-map
                (when active-node-added-handler
                    (active-map.node-added:disconnect active-node-added-handler true)
                    (set active-node-added-handler nil))
                (when active-node-removed-handler
                    (active-map.node-removed:disconnect active-node-removed-handler true)
                    (set active-node-removed-handler nil))
                (when active-node-replaced-handler
                    (active-map.node-replaced:disconnect active-node-replaced-handler true)
                    (set active-node-replaced-handler nil))
                (when active-edge-added-handler
                    (active-map.edge-added:disconnect active-edge-added-handler true)
                    (set active-edge-added-handler nil))
                (when active-edge-removed-handler
                    (active-map.edge-removed:disconnect active-edge-removed-handler true)
                    (set active-edge-removed-handler nil))
                (set active-map nil)))

        (fn sync-active-map []
            (local current (manager:get-active-map))
            (when (not (= current active-map))
                (disconnect-active-map)
                (set active-map current)
                (when active-map
                    (set active-node-added-handler (active-map.node-added:connect request-rebuild))
                    (set active-node-removed-handler (active-map.node-removed:connect request-rebuild))
                    (set active-node-replaced-handler (active-map.node-replaced:connect request-rebuild))
                    (set active-edge-added-handler (active-map.edge-added:connect request-rebuild))
                    (set active-edge-removed-handler (active-map.edge-removed:connect request-rebuild)))))

        (fn rebuild-children []
            (sync-active-map)
            (drop-content)
            (set visible-labels [])
            (local maps (manager:list-maps))
            (local active-id manager.active-map-id)
            (local maps-count (length maps))
            (local selected-count (current-selected-count))
            (set last-selected-count selected-count)
            (local default-text-color (or (and theme theme.text theme.text.default)
                                          (glm.vec4 0.95 0.95 0.95 1.0)))
            (local accent-color (or (and theme theme.accent)
                                    (glm.vec4 0.2 0.6 1.0 1.0)))
            (local muted-color (glm.vec4 0.55 0.55 0.55 1.0))

            (fn build-title []
                (fn [ic]
                    ((Padding {:edge-insets [0.35 0.25 0.2 0.25]
                               :child (text-builder "Graph Maps" muted-color 0.85)})
                     ic)))

            (fn build-switch-title []
                (fn [ic]
                    ((Padding {:edge-insets [0.05 0.25 0.1 0.25]
                               :child (text-builder "Switch Map" muted-color 0.72)})
                     ic)))

            (fn build-selected-count []
                (fn [ic]
                    ((Padding {:edge-insets [0.05 0.25 0.2 0.25]
                               :child (text-builder (.. "Selected: " selected-count)
                                                    default-text-color
                                                    0.72)})
                     ic)))

            (fn build-map-row [entry]
                (local map-name (or entry.name entry.id))
                (local is-active? (= entry.id active-id))
                (local node-count (or entry.node-count 0))
                (local edge-count (or entry.edge-count 0))
                (local marker (if is-active? " *" ""))
                (local label (.. map-name marker "  " node-count "n/" edge-count "e"))
                (record-label label)
                (fn [ic]
                    ((Padding {:edge-insets [0.15 0.25 0.15 0.25]
                               :child (fn [ic2]
                                           ((Button {:text label
                                                     :padding [0.2 0.25]
                                                     :enabled? (not is-active?)
                                                     :focusable? true
                                                     :variant :ghost
                                                     :on-click (fn [_ _] (manager:switch-map! entry.id))})
                                            ic2))})
                     ic)))

            (fn build-separator []
                (fn [ic]
                    ((Rectangle {:color (glm.vec4 0.25 0.25 0.3 1.0)
                                 :size (glm.vec3 0 0 0)})
                     ic)))

            (fn build-action-button [label on-click enabled? variant]
                (record-label label)
                (fn [ic]
                    ((Button {:text label
                              :padding [0.3 0.22]
                              :focusable? false
                              :enabled? (if (= enabled? nil) true enabled?)
                              :on-click on-click
                              :variant (or variant :secondary)})
                     ic)))

            (fn build-actions []
                (fn [ic]
                    ((Padding {:edge-insets [0.3 0.25 0.25 0.25]
                               :child (fn [ic2]
                                           ((Flex {:direction :horizontal
                                                    :gap 0.25
                                                    :children
                                                    [(FlexChild (build-action-button "New"
                                                                                      (fn [_ _]
                                                                                           (local sid (.. "map-" (tostring manager.next-map-id)))
                                                                                          (manager:create-map! sid sid)
                                                                                          (manager:switch-map! sid))
                                                                                      true)
                                                                0)
                                                     (FlexChild (build-action-button "Rename"
                                                                                      (fn [_ _]
                                                                                          (manager:rename-map! manager.active-map-id (.. (or manager.active-map-name manager.active-map-id) "*")))
                                                                                      true)
                                                                0)
                                                      (FlexChild (build-action-button "Delete Map"
                                                                                       (fn [_ _]
                                                                                           (local target-id manager.active-map-id)
                                                                                          (var other-id nil)
                                                                                          (each [_ m (ipairs (manager:list-maps))]
                                                                                              (when (and (not other-id) (not= m.id target-id))
                                                                                                  (set other-id m.id)))
                                                                                          (when other-id
                                                                                              (manager:switch-map! other-id)
                                                                                              (manager:delete-map! target-id)))
                                                                                      (> maps-count 1)
                                                                                      :danger)
                                                                0)]})
                                            ic2))})
                     ic)))

            (local content-children
                [(FlexChild (build-title) 0)
                 (FlexChild (build-actions) 0)
                 (FlexChild (build-switch-title) 0)])
            (each [_ entry (ipairs maps)]
                (table.insert content-children (FlexChild (build-map-row entry) 0)))
            (table.insert content-children (FlexChild (build-separator) 0))
            (table.insert content-children (FlexChild (build-selected-count) 0))
            (root-layout:clear-children)
            (set content-entity
                 ((Stack {:children
                          [(fn [ic] ((Rectangle {:color (panel-bg)}) ic))
                           (fn [ic] ((Flex {:axis 2 :spacing 0.0 :children content-children}) ic))]})
                  ctx))
            (when content-entity
                (root-layout:add-child content-entity.layout)))

        (fn measurer [self]
            (if content-entity
                (do
                    (content-entity.layout:measurer)
                    (set self.measure content-entity.layout.measure))
                (set self.measure (glm.vec3 0 0 0))))

        (fn layouter [self]
            (local allocated-size
                (glm.vec3 (math.max self.measure.x (or self.size.x 0))
                          (math.max self.measure.y (or self.size.y 0))
                          (math.max self.measure.z (or self.size.z 0))))
            (set self.size allocated-size)
            (when content-entity
                (set content-entity.layout.position self.position)
                (set content-entity.layout.size allocated-size)
                (set content-entity.layout.rotation self.rotation)
                (set content-entity.layout.clip-region self.clip-region)
                (set content-entity.layout.depth-offset-index self.depth-offset-index)
                (content-entity.layout:layouter)))

        (set root-layout
             (Layout {:name "graph-map-sidebar"
                      :measurer measurer
                      :layouter layouter
                      :children []}))

        (set maps-changed-handler
             (manager.maps-changed:connect (fn [_payload]
                                               (set rebuild-requested? true))))

        (rebuild-children)
        (set rebuild-requested? false)

        {:layout root-layout
         :visible-labels (fn [_self]
                             (icollect [_ label (ipairs visible-labels)] label))
         :update (fn [_self]
                     (local selected-count (current-selected-count))
                     (when (not (= selected-count last-selected-count))
                         (set rebuild-requested? true))
                     (when rebuild-requested?
                         (set rebuild-requested? false)
                         (rebuild-children)
                         (when root-layout
                             (root-layout:mark-measure-dirty))))
          :drop (fn [_self]
                    (when maps-changed-handler
                        (manager.maps-changed:disconnect maps-changed-handler true)
                        (set maps-changed-handler nil))
                    (disconnect-active-map)
                    (drop-content)
                    (root-layout:drop))})

    build)

{:GraphMapSidebar GraphMapSidebar}
