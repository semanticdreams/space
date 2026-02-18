(local Input (require :input))

(fn StringEntityNodePreview [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "StringEntityNodePreview requires a build context")
    (local view {})
    (local entity (and target target.get-entity (target:get-entity)))

    (local input
      ((Input {:text ""
               :placeholder "Value..."
               :multiline? true
               :min-lines 3
               :max-lines 3
               :on-change (fn [_input new-value]
                            (when (and target target.update-value)
                              (target:update-value new-value)))})
       build-ctx))

    (local initial-value (or (and entity entity.value) ""))
    (when (and input input.set-text (> (string.len initial-value) 0))
      (input:set-text initial-value {:reset-cursor? false}))

    (set view.layout input.layout)
    (set view.input input)
    (set view.drop
         (fn [_self]
           (input:drop)))
    view))

StringEntityNodePreview
