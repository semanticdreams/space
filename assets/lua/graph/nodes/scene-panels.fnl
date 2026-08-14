(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local ScenePanelsNodeView (require :graph/view/views/scene-panels))
(local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
(local WorldData (require :graph/world-data))

(local M {})

(fn scene-panel-key [self panel-index]
  (.. "activity-scene-panel:" self.world-id ":" self.activity-id ":" panel-index))

(fn M.ScenePanelsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "ScenePanelsNode requires :world-id"))
  (local activity-id (assert options.activity-id "ScenePanelsNode requires :activity-id"))
  (local world-manager (assert options.world-manager "ScenePanelsNode requires :world-manager"))
  (local key (or options.key (.. "activity-scene-panels:" world-id ":" activity-id)))
  (local node (GraphNode {:key key
                           :label "scene panels"
                           :color (glm.vec4 0.55 0.45 0.75 1)
                           :sub-color (glm.vec4 0.45 0.35 0.65 1)
                           :size 8.0
                           :view ScenePanelsNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.items-changed (Signal))
  (fn collect-items [self]
    (WorldData.list-scene-panels self.world-manager self.world-id self.activity-id))
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
                                                :activity-id self.activity-id
                                                :world-manager self.world-manager
                                               :panel-index entry.index
                                               :panel entry.metadata
                                               :panel-record entry.panel
                                               :label entry.kind
                                               :key (scene-panel-key self entry.index)}))
           (graph:add-edge (GraphEdge {:source self
                                       :target panel-node})))))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (var changed-handler nil)
  (set changed-handler
        (world-manager.changed:connect
          (fn [_payload]
            (if (WorldData.resolve-activity-surface-state world-manager world-id activity-id "scene")
                (node:emit-items)
                (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.items-changed
           (self.items-changed:clear))))
  node)

M
