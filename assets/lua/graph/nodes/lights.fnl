(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local LightsNodeView (require :graph/view/views/lights))
(local {:LightTypeNode LightTypeNode} (require :graph/nodes/light-type))
(local WorldData (require :graph/world-data))

(local M {})

(fn light-type-node-key [self type-key]
  (.. "activity-light-type:" self.world-id ":" self.activity-id ":" type-key))

(fn M.LightsNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "LightsNode requires :world-id"))
  (local activity-id (assert options.activity-id "LightsNode requires :activity-id"))
  (local world-manager (assert options.world-manager "LightsNode requires :world-manager"))
  (local key (or options.key (.. "activity-lights:" world-id ":" activity-id)))
  (local node (GraphNode {:key key
                          :label "lights"
                          :color (glm.vec4 0.8 0.72 0.3 1)
                          :sub-color (glm.vec4 0.68 0.58 0.2 1)
                          :size 8.0
                          :view LightsNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.items-changed (Signal))
  (set node.collect-items
       (fn [self]
          (WorldData.list-light-types self.world-manager self.world-id self.activity-id)))
  (set node.emit-items
       (fn [self]
         (local items (self:collect-items))
         (self.items-changed:emit items)
         items))
  (set node.add-type-node
       (fn [self entry]
         (local graph self.graph)
         (when (and graph entry entry.type-key)
            (local light-type-node
               (LightTypeNode {:world-id self.world-id
                               :activity-id self.activity-id
                               :world-manager self.world-manager
                              :type-key entry.type-key
                              :key (light-type-node-key self entry.type-key)}))
           (graph:add-edge (GraphEdge {:source self
                                       :target light-type-node})))))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (if (WorldData.resolve-world-entry world-manager world-id)
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
