(local glm (require :glm))
(local Card (require :card))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))

(fn ScenePanelNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "ScenePanelNodeView requires a build context")
    (local view {})
    (local panel-kind (and target target.panel-kind))
    (local panel-index (and target target.panel-index))
    (local header-text (or panel-kind "scene panel"))
    (local info-text (.. "index: " (or panel-index "?") " | kind: " (or panel-kind "unknown")))
    (local info-label-builder
      (Text {:text info-text
             :color (glm.vec4 0.6 0.6 0.6 1)}))
    (local remove-button-builder
      (Button {:icon "delete"
               :text "Remove"
               :variant :ghost
               :on-click (fn [_button _event]
                           (when (and target target.actions)
                             (local action (. target.actions 1))
                             (when (and action action.fn)
                               (action.fn nil nil))))}))
    (local content-flex-builder
      (Flex {:axis 2
             :xalign :stretch
             :yspacing 0.3
             :children [(FlexChild info-label-builder 0)
                        (FlexChild remove-button-builder 0)]}))
    (local card-builder
      (Card {:title header-text
             :child content-flex-builder}))
    (local card (card-builder build-ctx))
    (local info-label (info-label-builder build-ctx))
    (local remove-button (remove-button-builder build-ctx))
    (local content-flex (content-flex-builder build-ctx))
    (set view.layout card.layout)
    (set view.drop
         (fn [_self]
           (info-label:drop)
           (remove-button:drop)
           (content-flex:drop)
           (card:drop)))
    view))
ScenePanelNodeView
