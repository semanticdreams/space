(local glm (require :glm))
(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local SearchView (require :search-view))
(local Text (require :text))
(local HeightfieldTerrainData (require :heightfield-terrain-data))

(fn format-values [items]
  (if (= (type items) :table)
      (table.concat (icollect [_ value (ipairs items)] (tostring value)) ", ")
      "?"))

(fn summary-text [target]
  (local record (and target target.terrain-record))
  (local options (or (and record record.options) {}))
  (local parts [])
  (table.insert parts (.. "id: " (or (and target target.terrain-id) "?")))
  (when (and record record.name)
    (table.insert parts (.. "name: " record.name)))
  (table.insert parts (.. "kind: " (or (and target target.terrain-kind) "unknown")))
  (when options.position
    (table.insert parts (.. "position: " (format-values options.position))))
  (when options.rotation
    (table.insert parts (.. "rotation: " (format-values options.rotation))))
  (when (not (= options.opacity nil))
    (table.insert parts (.. "opacity: " (tostring options.opacity))))
  (when (not (= options.physics nil))
    (table.insert parts (.. "physics: " (if options.physics "enabled" "disabled"))))
  (when options.sample-spacing
    (table.insert parts (.. "sample spacing: " (format-values options.sample-spacing))))
  (when options.chunk-samples
    (table.insert parts (.. "chunk samples: " (format-values options.chunk-samples))))
  (when (= (and record record.kind) "heightfield-terrain")
    (local bounds (HeightfieldTerrainData.sample-bounds record))
    (table.insert parts
      (.. "coverage samples: "
           (tostring bounds.min-sample-x) ", " (tostring bounds.min-sample-z)
           " to "
           (tostring bounds.max-sample-x) ", " (tostring bounds.max-sample-z))))
  (when record.chunks
    (table.insert parts (.. "chunks: " (tostring (length record.chunks)))))
  (when (not (= options.default-height nil))
    (table.insert parts (.. "default height: " (tostring options.default-height))))
  (table.concat parts "\n"))

(fn TerrainNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "TerrainNodeView requires a build context")
    (local view {})
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
      ((Button {:text "Properties"
                :variant :ghost
                :enabled? (not (not (and target target.open-editor target.has-editor?)))
                :on-click (fn [_button _event]
                            (when (and target target.open-editor target.has-editor?)
                              (target:open-editor)))})
       build-ctx))
    (local remove-button
      ((Button {:text "Delete Terrain"
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
    (local tools-search
      ((SearchView {:items []
                    :name "terrain-node-tools-view"
                    :num-per-page 8
                    :builder (fn [item child-ctx]
                               (local label (tostring (. item 2)))
                               ((Button {:text label
                                         :variant :ghost
                                         :enabled? (not (not (and target target.open-tool)))
                                         :on-click (fn [_button _event]
                                                     (when (and target target.open-tool)
                                                       (target:open-tool (. (. item 1) :id))))})
                                child-ctx))})
       build-ctx))
    (local tools-label
      ((Text {:text "tools"
              :color (glm.vec4 0.8 0.8 0.8 1)})
       build-ctx))
    (local content-flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] header-label) 0)
                         (FlexChild (fn [_] info-label) 0)
                         (FlexChild (fn [_] action-row) 0)
                         (FlexChild (fn [_] tools-label) 0)
                         (FlexChild (fn [_] tools-search) 1)]})
       build-ctx))
    (local changed-signal (and target target.changed))
    (local changed-handler
      (and changed-signal
           (fn [_payload]
             (info-label:set-text (summary-text target))
             (tools-search:set-items
               (icollect [_ tool (ipairs (or (and target target.available-tools) []))]
                 [tool tool.label])))))
    (when changed-signal
      (changed-signal:connect changed-handler))
    (tools-search:set-items
      (icollect [_ tool (ipairs (or (and target target.available-tools) []))]
        [tool tool.label]))
    (tools-search.submitted:connect
      (fn [item]
        (when (and target target.open-tool item)
          (target:open-tool (. (. item 1) :id)))))
    (local scroll-view
      ((ScrollView {:child (fn [_] content-flex)
                    :padding false
                    :scrollbar-policy :as-needed
                    :name "terrain-node-view"})
       build-ctx))
	    (set view.layout scroll-view.layout)
	    (set view.scroll-view scroll-view)
    (set view.tools-search tools-search)
	    (set view.drop
	         (fn [_self]
	             (when changed-signal
	               (changed-signal:disconnect changed-handler true))
	             (scroll-view:drop)))
    view))
TerrainNodeView
