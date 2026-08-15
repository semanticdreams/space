(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:ActivitySurfacesNode ActivitySurfacesNode} (require :graph/nodes/activity-surfaces))

(local M {})

(fn M.WorldActivityNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "WorldActivityNode requires :world-id"))
  (local activity-id (assert options.activity-id "WorldActivityNode requires :activity-id"))
  (local world-manager (assert options.world-manager "WorldActivityNode requires :world-manager"))
  (local key (or options.key (.. "world-activity:" world-id ":" activity-id)))
  (local node (GraphNode {:key key
                          :label (.. activity-id " activity")
                          :color (glm.vec4 0.64 0.48 0.22 1)
                          :sub-color (glm.vec4 0.52 0.36 0.12 1)
                          :size 8.0}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.open-surfaces
       (fn [self]
         (local graph self.graph)
         (when graph
           (local surfaces-key (.. "activity-surfaces:" self.world-id ":" self.activity-id))
           (local surfaces-node
             (or (graph:lookup surfaces-key)
                 (and graph.load-by-key (graph:load-by-key surfaces-key))
                 (ActivitySurfacesNode {:world-id self.world-id
                                        :activity-id self.activity-id
                                        :world-manager self.world-manager
                                        :key surfaces-key})))
           (when surfaces-node
             (graph:add-edge (GraphEdge {:source self :target surfaces-node})))
           surfaces-node)))
  (set node.actions
       [{:name "Open Surfaces"
         :icon "open_in_new"
         :fn (fn [_button _event]
               (node:open-surfaces))}])
  node)

M
