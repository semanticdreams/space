(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local gl (require :gl))
(local Utils (require :graph/view/utils))

(fn make-title [entity]
  (if (and entity entity.value (> (string.len entity.value) 0))
      (Utils.truncate-with-ellipsis entity.value 50)
      (or (and entity entity.id) "string entity")))

(fn StringEntityNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "StringEntityNodeView requires a build context")
    (local view {})
    (local entity (and target target.get-entity (target:get-entity)))

    (local copy-value-button
      ((Button {:icon "content_copy"
                :text "Copy Value"
                :variant :ghost
                :on-click (fn [_button _event]
                            (local current (and target target.get-entity (target:get-entity)))
                            (when (and current current.value)
                              (gl.clipboard-set current.value)))})
       build-ctx))

    (local copy-id-button
      ((Button {:icon "tag"
                :text "Copy ID"
                :variant :ghost
                :on-click (fn [_button _event]
                            (local current (and target target.get-entity (target:get-entity)))
                            (when (and current current.id)
                              (gl.clipboard-set current.id)))})
       build-ctx))

    (local delete-button
      ((Button {:icon "delete"
                :text "Delete"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.delete-entity)
                              (target:delete-entity)))})
       build-ctx))

    (local action-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] copy-value-button) 0)
                         (FlexChild (fn [_] copy-id-button) 0)
                         (FlexChild (fn [_] delete-button) 0)]})
       build-ctx))

    (local input
      ((Input {:text ""
               :placeholder "Enter value..."
               :multiline? true
               :min-lines 3
               :max-lines 20
               :on-change (fn [_input new-value]
                            (when (and target target.update-value)
                              (target:update-value new-value)))})
       build-ctx))
    (local initial-value (or (and entity entity.value) ""))
    (when (and input input.set-text (> (string.len initial-value) 0))
      (input:set-text initial-value {:reset-cursor? false}))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.5
              :children [(FlexChild (fn [_] action-row) 0)
                         (FlexChild (fn [_] input) 1)]})
       build-ctx))

    (set view.input input)
    (set view.action-row action-row)
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
           (input:drop)
           (copy-value-button:drop)
           (copy-id-button:drop)
           (delete-button:drop)
           (action-row:drop)
           (flex:drop)))

    view))

StringEntityNodeView
