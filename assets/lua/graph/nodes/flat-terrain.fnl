(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local FlatTerrainNodeView (require :graph/view/views/flat-terrain))
(local WorldData (require :graph/world-data))

(local M {})

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn M.FlatTerrainNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "FlatTerrainNode requires :world-id"))
  (local activity-id (or options.activity-id "sandbox"))
  (local world-manager (assert options.world-manager "FlatTerrainNode requires :world-manager"))
  (local terrain-id (assert options.terrain-id "FlatTerrainNode requires :terrain-id"))
  (local resolved (or options.terrain-entry
                       (WorldData.find-terrain world-manager world-id activity-id terrain-id)
                      {}))
  (local terrain-record (or options.terrain-record resolved.record {}))
  (assert (= (or terrain-record.kind resolved.kind) "flat-terrain")
          "FlatTerrainNode requires a flat-terrain record")
  (local key (or options.key (.. "terrain-editor:" world-id ":" terrain-id)))
  (local node (GraphNode {:key key
                           :label "flat terrain"
                           :color (glm.vec4 0.35 0.65 0.45 1)
                           :sub-color (glm.vec4 0.25 0.5 0.35 1)
                           :size 8.0
                           :view FlatTerrainNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.terrain-id terrain-id)
  (set node.terrain-kind "flat-terrain")
  (set node.terrain-record (clone-table terrain-record))
  (set node.changed (Signal))
  (set node.get-record
       (fn [self]
         (or self.terrain-record {})))
  (set node.update-record
       (fn [self updater]
         (local updated
            (WorldData.update-terrain-record self.world-manager self.world-id self.activity-id self.terrain-id updater))
          (when updated
            (set self.terrain-record updated)
            (self.changed:emit updated))
          updated))
  (set node.apply-values
        (fn [self validated]
          (self:update-record
            (fn [record]
              (when (not record.options)
                (set record.options {}))
              (set record.options.width validated.width)
              (set record.options.length validated.length)
              (set record.options.scale validated.scale)
              (set record.options.position validated.position)
              (set record.options.rotation validated.rotation)
              (set record.options.opacity validated.opacity)
              (set record.options.physics-thickness validated.physics-thickness)))))
  (set node.remove-terrain
       (fn [self]
          (WorldData.remove-terrain self.world-manager self.world-id self.activity-id self.terrain-id)))
  (set node.actions
        [{:name "Delete Terrain"
         :fn (fn [_button _event]
               (when (node:remove-terrain)
                  (when (and node.graph node.graph.remove-nodes)
                    (node.graph:remove-nodes [node] {:cause "shared-delete"}))))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
            (local current (WorldData.find-terrain world-manager world-id activity-id terrain-id))
           (if (and current (= current.kind "flat-terrain"))
               (do
                 (set node.terrain-record (clone-table (or current.record {})))
                 (node.changed:emit node.terrain-record))
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
