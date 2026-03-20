(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local WorldNodeView (require :graph/view/views/world))
(local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
(local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
(local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))

(local M {})

(fn M.WorldNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "WorldNode requires :world-id"))
  (local world-manager (assert options.world-manager "WorldNode requires :world-manager"))
  (local world-entry (or options.world-entry
                          (and world-manager.active-world
                               (world-manager:active-world))))
  (local key (or options.key (.. "world:" world-id)))
  (local name (or (and world-entry world-entry.name) world-id))
  (local node (GraphNode {:key key
                          :label name
                          :color (glm.vec4 0.8 0.6 0.2 1)
                          :sub-color (glm.vec4 0.7 0.5 0.1 1)
                          :size 9.0
                          :view WorldNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.world-entry world-entry)
  (set node.changed (Signal))
  (set node.categories-changed (Signal))
  (fn emit-categories [self]
    (local categories
      [{:key "scene-panels" :label "scene panels" :kind ScenePanelsNode}
       {:key "hud-panels" :label "hud panels" :kind HudPanelsNode}
       {:key "terrains" :label "terrains" :kind TerrainsNode}])
    (when self.categories-changed
      (self.categories-changed:emit categories))
    categories)
  (set node.emit-categories emit-categories)
  (set node.add-category-node
       (fn [self category]
         (local graph self.graph)
         (when (and graph category category.kind)
           (local category-node (category.kind {:world-id self.world-id}))
           (graph:add-edge (GraphEdge {:source self :target category-node})))))
  (set node.activate
       (fn [self]
         (local tabs (self.world-manager:list-tabs))
         (var target-idx nil)
         (each [_ tab (ipairs tabs)]
           (when (and (not target-idx) (= tab.id self.world-id))
             (set target-idx tab.index)))
         (when target-idx
           (self.world-manager:activate-index target-idx))))
  (set node.close
       (fn [self]
         (local tabs (self.world-manager:list-tabs))
         (var target-idx nil)
         (each [_ tab (ipairs tabs)]
           (when (and (not target-idx) (= tab.id self.world-id))
             (set target-idx tab.index)))
         (when target-idx
           (self.world-manager:close-world-index target-idx))))
  (set node.actions
       [{:name "Activate"
         :icon "play_arrow"
         :fn (fn [_button _event]
               (node:activate))}
        {:name "Close"
         :icon "close"
         :fn (fn [_button _event]
               (node:close))}])
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))
         (when self.categories-changed
           (self.categories-changed:clear))))
  node)

M
