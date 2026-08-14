(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local ActivitySurfaceNodeView (require :graph/view/views/activity-surface))
(local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
(local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
(local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
(local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
(local {:LightsNode LightsNode} (require :graph/nodes/lights))

(local M {})

(fn surface-key-prefix [surface-key]
  (if (= surface-key "scene") "activity-scene"
      (= surface-key "hud") "activity-hud"
      (= surface-key "canvas") "activity-canvas"
      (error (.. "ActivitySurfaceNode unsupported surface " (tostring surface-key)))))

(fn M.ActivitySurfaceNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "ActivitySurfaceNode requires :world-id"))
  (local activity-id (assert options.activity-id "ActivitySurfaceNode requires :activity-id"))
  (local surface-key (assert options.surface-key "ActivitySurfaceNode requires :surface-key"))
  (local world-manager (assert options.world-manager "ActivitySurfaceNode requires :world-manager"))
  (local key (or options.key (.. (surface-key-prefix surface-key) ":" world-id ":" activity-id)))
  (local node (GraphNode {:key key
                          :label surface-key
                           :color (glm.vec4 0.46 0.42 0.66 1)
                           :sub-color (glm.vec4 0.36 0.32 0.56 1)
                           :size 8.0
                           :view ActivitySurfaceNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.surface-key surface-key)
  (set node.world-manager world-manager)
  (set node.asset-path-resolver options.asset-path-resolver)
  (set node.categories-changed (Signal))
  (set node.emit-categories
       (fn [self]
         (local categories
           (if (= self.surface-key "scene")
               [{:key "activity-scene-panels" :label "scene panels" :kind ScenePanelsNode}
                {:key "activity-terrains" :label "terrains" :kind TerrainsNode}
                {:key "activity-skybox" :label "skybox" :kind SkyboxNode}
                {:key "activity-background" :label "background" :kind BackgroundNode}
                {:key "activity-lights" :label "lights" :kind LightsNode}]
               []))
         (self.categories-changed:emit categories)
         categories))
  (set node.add-category-node
       (fn [self category]
         (local graph self.graph)
         (when (and graph category category.kind)
           (local category-key (.. category.key ":" self.world-id ":" self.activity-id))
           (local category-node
             (or (graph:lookup category-key)
                 (category.kind {:world-id self.world-id
                                 :activity-id self.activity-id
                                 :world-manager self.world-manager
                                 :asset-path-resolver self.asset-path-resolver
                                 :key category-key})))
           (graph:add-edge (GraphEdge {:source self :target category-node})))))
  (set node.drop
       (fn [self]
         (when self.categories-changed
           (self.categories-changed:clear))))
  node)

M
