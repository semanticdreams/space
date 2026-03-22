(local glm (require :glm))
(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn format-values [items]
  (if (= (type items) :table)
      (table.concat (icollect [_ value (ipairs items)] (tostring value)) ", ")
      "?"))

(fn summary-text [target]
  (local record (and target target.terrain-record))
  (local options (or (and record record.options) {}))
  (local parts [])
  (table.insert parts (.. "id: " (or (and target target.terrain-id) "?")))
  (table.insert parts (.. "kind: " (or (and target target.terrain-kind) "unknown")))
  (when options.position
    (table.insert parts (.. "position: " (format-values options.position))))
  (when options.scale
    (table.insert parts (.. "scale: " (format-values options.scale))))
  (table.concat parts "\n"))

(fn TerrainNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "TerrainNodeView requires a build context")
    (local view {})
    (local terrain-kind (and target target.terrain-kind))
    (local header-text "terrain")
    (local header-label
      ((Text {:text header-text
              :color (glm.vec4 0.9 0.9 0.9 1)})
       build-ctx))
    (local info-label
      ((Text {:text (summary-text target)
              :color (glm.vec4 0.6 0.6 0.6 1)})
       build-ctx))
    (local open-button
      ((Button {:text "Open Editor"
                :variant :ghost
                :enabled? (not (not (and target target.open-editor target.has-editor?)))
                :on-click (fn [_button _event]
                            (when (and target target.open-editor target.has-editor?)
                              (target:open-editor)))})
       build-ctx))
    (local remove-button
      ((Button {:text "Remove"
                :variant :ghost
                :enabled? (not (not (and target target.remove-terrain)))
                :on-click (fn [_button _event]
                            (when (and target target.remove-terrain)
                              (target:remove-terrain)))})
       build-ctx))
    (local action-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] open-button) 0)
                         (FlexChild (fn [_] remove-button) 0)]})
       build-ctx))
    (local content-flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] header-label) 0)
                         (FlexChild (fn [_] info-label) 0)
                         (FlexChild (fn [_] action-row) 0)]})
       build-ctx))
    (local changed-signal (and target target.changed))
    (local changed-handler
      (and changed-signal
           (fn [_payload]
             (info-label:set-text (summary-text target)))))
    (when changed-signal
      (changed-signal:connect changed-handler))
    (local scroll-view
      ((ScrollView {:child (fn [_] content-flex)
                    :padding false
                    :scrollbar-policy :as-needed
                    :name "terrain-node-view"})
       build-ctx))
    (set view.layout scroll-view.layout)
    (set view.scroll-view scroll-view)
    (set view.drop
         (fn [_self]
             (when changed-signal
               (changed-signal:disconnect changed-handler true))
             (scroll-view:drop)))
    view))
TerrainNodeView
