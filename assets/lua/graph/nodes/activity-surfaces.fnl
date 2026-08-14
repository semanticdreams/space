(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local ActivitySurfacesNodeView (require :graph/view/views/activity-surfaces))
(local {:ActivitySurfaceNode ActivitySurfaceNode} (require :graph/nodes/activity-surface))
(local WorldData (require :graph/world-data))

(local M {})

(fn surface-node-key [world-id activity-id surface-key]
  (.. (if (= surface-key "scene") "activity-scene" (= surface-key "hud") "activity-hud" "activity-canvas")
      ":" world-id ":" activity-id))

(fn M.ActivitySurfacesNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "ActivitySurfacesNode requires :world-id"))
  (local activity-id (assert options.activity-id "ActivitySurfacesNode requires :activity-id"))
  (local world-manager (assert options.world-manager "ActivitySurfacesNode requires :world-manager"))
  (local key (or options.key (.. "activity-surfaces:" world-id ":" activity-id)))
  (local node (GraphNode {:key key
                          :label "surfaces"
                           :color (glm.vec4 0.5 0.45 0.72 1)
                           :sub-color (glm.vec4 0.4 0.35 0.62 1)
                           :size 8.0
                           :view ActivitySurfacesNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.asset-path-resolver options.asset-path-resolver)
  (set node.items-changed (Signal))
  (set node.collect-items
       (fn [self]
         (icollect [_ surface (ipairs (WorldData.list-activity-surfaces self.world-manager self.world-id self.activity-id))]
           [surface (or surface.label surface.surface-key)])))
  (set node.emit-items
       (fn [self]
         (local items (self:collect-items))
         (self.items-changed:emit items)
         items))
  (set node.add-surface-node
       (fn [self surface]
         (local graph self.graph)
         (local surface-key (and surface surface.surface-key))
         (when (and graph surface-key)
           (local key (surface-node-key self.world-id self.activity-id surface-key))
           (local surface-node
             (or (graph:lookup key)
                 (and graph.load-by-key (graph:load-by-key key))
                 (ActivitySurfaceNode {:world-id self.world-id
                                       :activity-id self.activity-id
                                       :surface-key surface-key
                                       :world-manager self.world-manager
                                       :asset-path-resolver self.asset-path-resolver
                                       :key key})))
           (when surface-node
             (graph:add-edge (GraphEdge {:source self :target surface-node})))
           surface-node)))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (if (WorldData.resolve-activity-session world-manager world-id activity-id)
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

{:ActivitySurfacesNode M.ActivitySurfacesNode
 :surface-node-key surface-node-key}
