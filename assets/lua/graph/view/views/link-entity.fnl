(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local gl (require :gl))
(local json (require :json))
(local Utils (require :graph/view/utils))

(fn get-selected-key []
  (local selected (or (and app app.graph-view
                           app.graph-view.selection
                           app.graph-view.selection.selected-nodes)
                      []))
  (if (= (length selected) 1)
      (or (. selected 1 :key) "")
      nil))

(fn LinkEntityNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "LinkEntityNodeView requires a build context")
    (local view {})
    (local entity (and target target.get-entity (target:get-entity)))

    ;; Create source input first
    (local source-input
      ((Input {:text ""
               :placeholder "Source node key..."
               :on-change (fn [_input new-value]
                            (when (and target target.update-source)
                              (target:update-source new-value)))})
       build-ctx))
    (local initial-source (or (and entity entity.source-key) ""))
    (when (and source-input source-input.set-text (> (string.len initial-source) 0))
      (source-input:set-text initial-source {:reset-cursor? false}))

    ;; Create target input before swap button so it's in scope
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

    ;; Use Selected buttons
    (local use-selected-source-button
      ((Button {:icon "my_location"
                :text "Use Selected"
                :variant :ghost
                :on-click (fn [_button _event]
                            (local key (get-selected-key))
                            (when key
                              (source-input:set-text key {:reset-cursor? false})
                              (when (and target target.update-source)
                                (target:update-source key))))})
       build-ctx))

    (local use-selected-target-button
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

    ;; Source row
    (local source-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] source-input) 1)
                         (FlexChild (fn [_] use-selected-source-button) 0)]})
       build-ctx))

    ;; Swap button (now target-input is in scope)
    (local swap-button
      ((Button {:icon "swap_vert"
                :text "Swap"
                :variant :ghost
                :on-click (fn [_button _event]
                            (local current (and target target.get-entity (target:get-entity)))
                            (when current
                              (local old-source (or current.source-key ""))
                              (local old-target (or current.target-key ""))
                              (source-input:set-text old-target {:reset-cursor? false})
                              (target-input:set-text old-source {:reset-cursor? false})
                              (when (and target target.update-source target.update-target)
                                (target:update-source old-target)
                                (target:update-target old-source))))})
       build-ctx))

    ;; Target row
    (local target-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] target-input) 1)
                         (FlexChild (fn [_] use-selected-target-button) 0)]})
       build-ctx))

    ;; Metadata display (read-only)
    (local metadata-input
      ((Input {:text ""
               :placeholder "No metadata"
               :multiline? true
               :min-lines 2
               :max-lines 8
               :editable? false})
       build-ctx))
    (local metadata (or (and entity entity.metadata) {}))
    (local (ok metadata-str) (pcall json.dumps metadata))
    (when (and ok metadata-str (> (string.len metadata-str) 2))
      (metadata-input:set-text metadata-str {:reset-cursor? false}))

    ;; Delete button
    (local delete-button
      ((Button {:icon "delete"
                :text "Delete"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.delete-entity)
                              (target:delete-entity)))})
       build-ctx))

    ;; Main layout
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (fn [_] source-row) 0)
                         (FlexChild (fn [_] swap-button) 0)
                         (FlexChild (fn [_] target-row) 0)
                         (FlexChild (fn [_] metadata-input) 0)
                         (FlexChild (fn [_] delete-button) 0)]})
       build-ctx))

    (set view.source-input source-input)
    (set view.target-input target-input)
    (set view.metadata-input metadata-input)
    (set view.layout flex.layout)

    (var deleted-handler nil)
    (local deleted-signal (and target target.entity-deleted))
    (when deleted-signal
      (set deleted-handler
           (deleted-signal:connect
             (fn [_deleted]
               nil))))

    (set view.drop
         (fn [_self]
           (when (and deleted-signal deleted-handler)
             (deleted-signal:disconnect deleted-handler true)
             (set deleted-handler nil))
           (source-input:drop)
           (use-selected-source-button:drop)
           (source-row:drop)
           (swap-button:drop)
           (target-input:drop)
           (use-selected-target-button:drop)
           (target-row:drop)
           (metadata-input:drop)
           (delete-button:drop)
           (flex:drop)))

    view))

LinkEntityNodeView
