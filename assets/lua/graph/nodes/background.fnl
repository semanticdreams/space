(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local BackgroundNodeView (require :graph/view/views/background))
(local BackgroundState (require :background-state))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.BackgroundNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "BackgroundNode requires :world-id"))
  (local world-manager (assert options.world-manager "BackgroundNode requires :world-manager"))
  (local background-record
    (BackgroundState.normalize-complete-state
      (or options.background-record
          (WorldData.get-background world-manager world-id))
      (.. "BackgroundNode[" world-id "]")))
  (local key (or options.key (.. "background:" world-id)))
  (local node (GraphNode {:key key
                          :label "background"
                          :color (glm.vec4 0.18 0.18 0.24 1)
                          :sub-color (glm.vec4 0.12 0.12 0.18 1)
                          :size 8.0
                          :view BackgroundNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.background-record (BackgroundState.clone-state background-record))
  (set node.changed (Signal))
  (set node.get-record
       (fn [self]
         (BackgroundState.clone-state self.background-record)))
  (set node.apply-values
       (fn [self next-background]
         (local updated
           (WorldData.update-background self.world-manager self.world-id next-background))
         (when updated
           (set self.background-record (BackgroundState.clone-state updated)))
         updated))
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (local entry (WorldData.resolve-world-entry world-manager world-id))
           (if entry
               (do
                 (set node.background-record
                      (BackgroundState.clone-state
                        (WorldData.get-background world-manager world-id)))
                 (node.changed:emit node.background-record))
               (when (and node.graph node.graph.remove-nodes)
                 (node.graph:remove-nodes [node]))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))))
  node)

M
