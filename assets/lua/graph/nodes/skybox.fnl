(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local SkyboxNodeView (require :graph/view/views/skybox))
(local SkyboxState (require :skybox-state))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.SkyboxNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "SkyboxNode requires :world-id"))
  (local activity-id (assert options.activity-id "SkyboxNode requires :activity-id"))
  (local world-manager (assert options.world-manager "SkyboxNode requires :world-manager"))
  (local asset-path-resolver
    (assert options.asset-path-resolver
            (.. "SkyboxNode[" world-id "] requires :asset-path-resolver")))
  (local theme-items-provider
    (or options.theme-items-provider
        (fn []
          (local items [])
          (when (and app app.themes app.themes.list-themes)
            (each [_ theme-key (ipairs (app.themes:list-themes))]
              (local key (SkyboxState.normalize-theme-key
                           theme-key
                           (.. "SkyboxNode[" world-id "] theme key")))
              (table.insert items [key key])))
          (table.sort items
                      (fn [left right]
                        (< (. left 1) (. right 1))))
          items)))
  (local skybox-record
    (SkyboxState.normalize-complete-state
      (or options.skybox-record
           (WorldData.get-skybox world-manager world-id activity-id))
      (.. "SkyboxNode[" world-id "]")))
  (local key (or options.key (.. "activity-skybox:" world-id ":" activity-id)))
  (local node (GraphNode {:key key
                          :label "skybox"
                          :color (glm.vec4 0.26 0.48 0.7 1)
                          :sub-color (glm.vec4 0.18 0.36 0.56 1)
                          :size 8.0
                          :view SkyboxNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.asset-path-resolver asset-path-resolver)
  (set node.skybox-record (SkyboxState.clone-state skybox-record))
  (set node.changed (Signal))
  (set node.get-record
       (fn [self]
         (SkyboxState.clone-state self.skybox-record)))
  (set node.available-items
       (fn [self]
         (SkyboxState.available-items self.asset-path-resolver)))
  (set node.available-themes
       (fn [_self]
         (theme-items-provider)))
  (set node.apply-values
       (fn [self next-skybox]
         (local updated
            (WorldData.update-skybox self.world-manager self.world-id self.activity-id next-skybox))
         (when updated
           (set self.skybox-record (SkyboxState.clone-state updated)))
         updated))
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (local entry (WorldData.resolve-world-entry world-manager world-id))
           (if entry
               (do
                 (set node.skybox-record
                      (SkyboxState.clone-state
                         (WorldData.get-skybox world-manager world-id activity-id)))
                 (node.changed:emit node.skybox-record))
               (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))))
  node)

M
