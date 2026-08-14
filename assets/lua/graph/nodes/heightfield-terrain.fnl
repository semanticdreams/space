(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HeightfieldTerrainNodeView (require :graph/view/views/heightfield-terrain))
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

(fn M.HeightfieldTerrainNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HeightfieldTerrainNode requires :world-id"))
  (local activity-id (assert options.activity-id "HeightfieldTerrainNode requires :activity-id"))
  (local world-manager (assert options.world-manager "HeightfieldTerrainNode requires :world-manager"))
  (local terrain-id (assert options.terrain-id "HeightfieldTerrainNode requires :terrain-id"))
  (local resolved (or options.terrain-entry
                       (WorldData.find-terrain world-manager world-id activity-id terrain-id)
                      {}))
  (local terrain-record (or options.terrain-record resolved.record {}))
  (assert (= (or terrain-record.kind resolved.kind) "heightfield-terrain")
          "HeightfieldTerrainNode requires a heightfield-terrain record")
  (local key (or options.key (.. "activity-terrain-editor:" world-id ":" activity-id ":" terrain-id)))
  (local node (GraphNode {:key key
                          :label "heightfield terrain properties"
                          :color (glm.vec4 0.34 0.58 0.4 1)
                          :sub-color (glm.vec4 0.22 0.42 0.28 1)
                          :size 8.0
                          :view HeightfieldTerrainNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.terrain-id terrain-id)
  (set node.terrain-kind "heightfield-terrain")
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
             (set record.name validated.name)
             (when (not record.options)
               (set record.options {}))
             (set record.options.position validated.position)
             (set record.options.rotation validated.rotation)
             (set record.options.opacity validated.opacity)
             (set record.options.physics validated.physics)
             (set record.options.sample-spacing validated.sample-spacing)))))
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
           (if (and current (= current.kind "heightfield-terrain"))
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
