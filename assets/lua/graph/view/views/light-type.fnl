(local glm (require :glm))
(local SearchView (require :search-view))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))

(fn LightTypeNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local items (or options.items []))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "LightTypeNodeView requires a build context")
    (local view {})
    (local show-add-controls?
      (if (and target target.show-add-controls?)
          (target:show-add-controls?)
          true))
    (local add-button
      (if show-add-controls?
          ((Button {:text "Add Light"
                    :variant :ghost
                    :enabled? (and target (target:can-add-light?))
                    :on-click (fn [_button _event]
                                (when (and target target.add-light)
                                  (target:add-light)))})
           build-ctx)
          nil))
    (local error-label
      (if show-add-controls?
          ((Text {:text (if target (target:limit-error-text) "")
                  :color (glm.vec4 0.92 0.38 0.38 1)})
           build-ctx)
          nil))
    (local search
      ((SearchView {:items []
                    :name "light-type-node-view"
                    :num-per-page 10
                    :builder (fn [item child-ctx]
                               ((Button {:text (tostring (. item 2))
                                         :variant :ghost
                                         :on-click (fn [_button _event]
                                                     (when (and target target.open-light-node)
                                                       (target:open-light-node (. item 1))))})
                                child-ctx))})
       build-ctx))
    (local children [])
    (when add-button
      (table.insert children (FlexChild (fn [_] add-button) 0)))
    (when error-label
      (table.insert children (FlexChild (fn [_] error-label) 0)))
    (table.insert children (FlexChild (fn [_] search) 1))
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children children})
       build-ctx))
    (set view.layout flex.layout)
    (set view.search search)
    (set view.add-button add-button)
    (set view.error-label error-label)
    (set view.set-items
         (fn [_self new-items]
           (search:set-items new-items)
           (when add-button
             (add-button:set-enabled (and target (target:can-add-light?))))
           (when error-label
             (error-label:set-text (if target (target:limit-error-text) "")
                                   {:mark-measure-dirty? false}))))
    (set view.refresh-items
         (fn [self]
           (local refreshed
             (if (and target target.emit-items)
                 (target:emit-items)
                 items))
           (self:set-items refreshed)))
    (local items-signal (and target target.items-changed))
    (local items-handler
      (and items-signal
           (fn [new-items]
             (view:set-items new-items))))
    (when items-signal
      (items-signal:connect items-handler))
    (search.submitted:connect
      (fn [item]
        (when (and target target.open-light-node item)
          (target:open-light-node (. item 1)))))
    (set view.drop
         (fn [_self]
           (when items-signal
             (items-signal:disconnect items-handler true))
           (flex:drop)))
    (view:refresh-items)
    view))

LightTypeNodeView
