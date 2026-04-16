(local glm (require :glm))
(local SearchView (require :search-view))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))

(fn WorldNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "WorldNodeView requires a build context")
    (local view {})
    (local world-id (and target target.world-id))
    (local world-name (and target target.label))
    (local header-text (or world-name world-id "world"))
    (local info-text (.. "id: " (or world-id "unknown")))
    (local header-label
      ((Text {:text header-text
              :color (glm.vec4 0.9 0.9 0.9 1)})
       build-ctx))
    (local info-label
      ((Text {:text info-text
              :color (glm.vec4 0.6 0.6 0.6 1)})
       build-ctx))
    (local activate-button
      ((Button {:icon "play_arrow"
                :text "Activate"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.activate)
                              (target:activate)))})
       build-ctx))
    (local close-button
      ((Button {:icon "close"
                :text "Close"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.close)
                              (target:close)))})
       build-ctx))
    (local search
      ((SearchView {:items []
                    :name "world-node-categories"
                    :num-per-page 10
                    :builder (fn [item child-ctx]
                               (local label (tostring (. item 2)))
                               ((Button {:text label
                                         :variant :ghost
                                         :on-click (fn [_button _event]
                                                     (when (and target target.add-category-node)
                                                       (target:add-category-node (. item 1))))})
                                child-ctx))})
       build-ctx))
    (local button-flex
      ((Flex {:axis 0
              :xspacing 0.2
              :children [(FlexChild (fn [_] activate-button) 0)
                         (FlexChild (fn [_] close-button) 0)]})
       build-ctx))
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] header-label) 0)
                         (FlexChild (fn [_] info-label) 0)
                         (FlexChild (fn [_] button-flex) 0)
                         (FlexChild (fn [_] search) 1)]})
       build-ctx))
    (set view.search search)
    (set view.layout flex.layout)
    (set view.set-categories
         (fn [_self categories]
           (local items [])
           (each [_ cat (ipairs (or categories []))]
             (table.insert items [cat cat.label]))
           (search:set-items items)))
    (set view.refresh-categories
         (fn [self]
           (local categories
             (if (and target target.emit-categories)
                 (target:emit-categories)
                 []))
           (self:set-categories categories)))
    (local categories-signal (and target target.categories-changed))
    (local categories-handler
      (and categories-signal
           (fn [categories]
             (view:set-categories categories))))
    (when categories-signal
      (categories-signal:connect categories-handler))
    (search.submitted:connect
      (fn [item]
        (when (and target target.add-category-node item)
          (target:add-category-node (. item 1)))))
    (set view.drop
         (fn [_self]
           (when categories-signal
             (categories-signal:disconnect categories-handler true))
           (flex:drop)))
    (view:refresh-categories)
    view))
WorldNodeView
