(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))

(fn CodeEntityNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "CodeEntityNodeView requires a build context")
    (local view {})
    (local entity (and target target.get-entity (target:get-entity)))

    (local source-input
      ((Input {:text ""
               :placeholder "Source..."
               :multiline? true
               :min-lines 5
               :max-lines 30
               :on-change (fn [_input new-value]
                            (when (and target target.update-source)
                              (target:update-source new-value)))})
       build-ctx))
    (when (and source-input source-input.set-text entity)
      (source-input:set-text (or entity.source "") {:reset-cursor? false}))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (fn [_] source-input) 1)]})
       build-ctx))

    (set view.layout flex.layout)
    (set view.drop
         (fn [_self]
           (source-input:drop)
           (flex:drop)))
    view))

CodeEntityNodeView
