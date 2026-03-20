(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local ScenePanelsNodeView (require :graph/view/views/scene-panels))
(local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))

(local M {})

(fn M.ScenePanelsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "ScenePanelsNode requires :world-id"))
  (local key (or options.key (.. "scene-panels:" world-id)))
  (local node (GraphNode {:key key
                           :label "scene panels"
                           :color (glm.vec4 0.55 0.45 0.75 1)
                           :sub-color (glm.vec4 0.45 0.35 0.65 1)
                           :size 8.0
                           :view ScenePanelsNodeView}))
  (set node.world-id world-id)
  (set node.items-changed (Signal))
  (fn collect-items [self]
    (local scene (and app.scene))
    (local children (and scene scene.scene-children))
    (local produced [])
    (each [idx metadata (ipairs (or children []))]
      (local persistence (and metadata metadata.persistence))
      (local kind (or (and persistence persistence.kind) "unknown"))
      (local label (.. kind " [" idx "]"))
      (table.insert produced [{:index idx
                               :kind kind
                               :metadata metadata}
                              label]))
    produced)
  (fn emit-items [self]
    (local items (collect-items self))
    (self.items-changed:emit items)
    items)
  (set node.collect-items collect-items)
  (set node.emit-items emit-items)
  (set node.add-panel-node
       (fn [self entry]
         (local graph self.graph)
         (when (and graph entry entry.index)
           (local panel-node (ScenePanelNode {:world-id self.world-id
                                              :panel-index entry.index
                                              :panel entry.metadata}))
           (graph:add-edge (GraphEdge {:source self
                                       :target panel-node})))))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (set node.drop
       (fn [self]
         (when self.items-changed
           (self.items-changed:clear))))
  node)

M
