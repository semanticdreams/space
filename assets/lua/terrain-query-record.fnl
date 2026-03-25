(local glm (require :glm))
(local HeightfieldTerrainData (require :heightfield-terrain-data))

(fn from-record-layout [record layout]
  (if (or (not record)
          (not layout)
          (not (= record.kind "heightfield-terrain")))
      record
      (do
        (local bounds (HeightfieldTerrainData.sample-bounds record))
        (local spacing (or (and record.options record.options.sample-spacing) [20 20]))
        (local spacing-x (or (. spacing 1) spacing.x 20))
        (local spacing-z (or (. spacing 2) spacing.y spacing.z 20))
        (local canonical-origin-offset
          (glm.vec3 (* bounds.min-sample-x spacing-x)
                    0
                    (* bounds.min-sample-z spacing-z)))
        (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
        (local canonical-position
          (- layout.position (rotation:rotate canonical-origin-offset)))
        (local options {})
        (each [key value (pairs (or record.options {}))]
          (set (. options key) value))
        (set options.position [canonical-position.x canonical-position.y canonical-position.z])
        (set options.rotation [rotation.w rotation.x rotation.y rotation.z])
        {:id record.id
         :kind record.kind
         :options options
         :chunks record.chunks})))

(fn from-metadata [metadata]
  (local record (and metadata metadata.record))
  (local layout (and metadata metadata.element metadata.element.layout))
  (from-record-layout record layout))

{:from-record-layout from-record-layout
 :from-metadata from-metadata}
