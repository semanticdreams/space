(local glm (require :glm))
(local Card (require :card))
(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))

(fn TerrainNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "TerrainNodeView requires a build context")
    (local view {})
    (local terrain-kind (and target target.terrain-kind))
    (local terrain-id (and target target.terrain-id))
    (local header-text (or terrain-kind "terrain"))
    (local info-text (.. "id: " (or terrain-id "?") " | kind: " (or terrain-kind "unknown")))
    (local info-label-builder
      (Text {:text info-text
             :color (glm.vec4 0.6 0.6 0.6 1)}))
    (local content-flex-builder
      (Flex {:axis 2
             :xalign :stretch
             :yspacing 0.3
             :children [(FlexChild info-label-builder 0)]}))
    (local card-builder
      (Card {:title header-text
             :child content-flex-builder}))
    (local card (card-builder build-ctx))
    (local info-label (info-label-builder build-ctx))
    (local content-flex (content-flex-builder build-ctx))
    (set view.layout card.layout)
    (set view.drop
         (fn [_self]
           (info-label:drop)
           (content-flex:drop)
           (card:drop)))
    view))
TerrainNodeView
