(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainSpace (require :heightfield-terrain-space))
(local HeightfieldResizeToolNodeView (require :graph/view/views/heightfield-resize-tool))
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

(fn M.HeightfieldResizeToolNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HeightfieldResizeToolNode requires :world-id"))
  (local world-manager (assert options.world-manager "HeightfieldResizeToolNode requires :world-manager"))
  (local terrain-id (assert options.terrain-id "HeightfieldResizeToolNode requires :terrain-id"))
  (local key (or options.key (.. "terrain-tool:" world-id ":" terrain-id ":resize-terrain")))
  (local node (GraphNode {:key key
                          :label "resize terrain"
                          :color (glm.vec4 0.37 0.48 0.58 1)
                          :sub-color (glm.vec4 0.25 0.35 0.44 1)
                          :size 7.5
                          :view HeightfieldResizeToolNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.terrain-id terrain-id)
  (set node.terrain-kind "heightfield-terrain")
  (set node.changed (Signal))
  (set node.get-record
       (fn [self]
         (local resolved (WorldData.find-terrain self.world-manager self.world-id self.terrain-id))
         (or (and resolved resolved.record) {})))
  (set node.apply-values
       (fn [self validated]
         (local updated
           (WorldData.update-terrain-record self.world-manager self.world-id self.terrain-id
             (fn [record]
               (HeightfieldTerrainData.resize-record! record validated))))
         (when updated
           (self.changed:emit (clone-table updated)))
         updated))
  (set node.apply-values-centered-on-origin
       (fn [self validated]
         (local updated
           (WorldData.update-terrain-record self.world-manager self.world-id self.terrain-id
             (fn [record]
               (HeightfieldTerrainData.resize-record! record validated)
               (local centered-record (HeightfieldTerrainSpace.record-centered-on-origin-xz record))
               (set record.options centered-record.options))))
         (when updated
           (self.changed:emit (clone-table updated)))
         updated))
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))))
  node)

{:HeightfieldResizeToolNode M.HeightfieldResizeToolNode}
