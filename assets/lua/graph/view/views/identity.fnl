(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))

(fn get-selected-key []
  (local selected (or (and app app.graph-view
                           app.graph-view.selection
                           app.graph-view.selection.selected-nodes)
                      []))
  (if (= (length selected) 1)
      (or (. selected 1 :key) "")
      nil))

(fn IdentityNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "IdentityNodeView requires a build context")
    (local view {})
    (local entity (and target target.get-entity (target:get-entity)))

    (local target-input
      ((Input {:text ""
               :placeholder "Target node key..."
               :on-change (fn [_input new-value]
                            (when (and target target.update-target)
                              (target:update-target new-value)))})
       build-ctx))
    (local initial-target (or (and entity entity.target-key) ""))
    (when (and target-input target-input.set-text (> (string.len initial-target) 0))
      (target-input:set-text initial-target {:reset-cursor? false}))

    (local use-selected-button
      ((Button {:icon "my_location"
                :text "Use Selected"
                :variant :ghost
                :on-click (fn [_button _event]
                            (local key (get-selected-key))
                            (when key
                              (target-input:set-text key {:reset-cursor? false})
                              (when (and target target.update-target)
                                (target:update-target key))))})
       build-ctx))

    (local open-target-button
      ((Button {:icon "open_in_new"
                :text "Open Target"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.open-target)
                              (target:open-target)))})
       build-ctx))

    (local delete-button
      ((Button {:icon "delete"
                :text "Delete Identity"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.delete-entity)
                              (target:delete-entity)))})
       build-ctx))

    (local target-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] target-input) 1)
                         (FlexChild (fn [_] use-selected-button) 0)]})
       build-ctx))

    (local button-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] open-target-button) 0)
                         (FlexChild (fn [_] delete-button) 0)]})
       build-ctx))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (fn [_] target-row) 0)
                         (FlexChild (fn [_] button-row) 0)]})
       build-ctx))

    (set view.target-input target-input)
    (set view.layout flex.layout)

    (set view.drop
         (fn [_self]
           (flex:drop)))
    view))

IdentityNodeView
