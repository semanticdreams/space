(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local WorldActivitiesNodeView (require :graph/view/views/world-activities))
(local {:WorldActivityNode WorldActivityNode} (require :graph/nodes/world-activity))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.WorldActivitiesNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "WorldActivitiesNode requires :world-id"))
  (local world-manager (assert options.world-manager "WorldActivitiesNode requires :world-manager"))
  (local key (or options.key (.. "world-activities:" world-id)))
  (local node (GraphNode {:key key
                          :label "activities"
                           :color (glm.vec4 0.7 0.5 0.2 1)
                           :sub-color (glm.vec4 0.6 0.4 0.1 1)
                           :size 8.0
                           :view WorldActivitiesNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.items-changed (Signal))
  (set node.changed (Signal))
  (set node.collect-items
       (fn [self]
         (icollect [_ activity (ipairs (WorldData.list-activities self.world-manager self.world-id))]
           [activity (or activity.label activity.id)])))
  (set node.emit-items
       (fn [self]
         (local items (self:collect-items))
         (self.items-changed:emit items)
         items))
  (set node.add-activity-node
       (fn [self activity]
         (local graph self.graph)
         (local activity-id (and activity activity.id))
         (when (and graph activity-id)
           (local activity-key (.. "world-activity:" self.world-id ":" activity-id))
           (local activity-node
             (or (graph:lookup activity-key)
                 (WorldActivityNode {:world-id self.world-id
                                     :activity-id activity-id
                                     :world-manager self.world-manager
                                     :key activity-key})))
           (graph:add-edge (GraphEdge {:source self :target activity-node})))))
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
               (do
                 (node:emit-items)
                 (node.changed:emit node))
               (when (and node.graph node.graph.remove-nodes)
                 (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.items-changed
           (self.items-changed:clear))
         (when self.changed
           (self.changed:clear))))
  node)

M
