(local glm (require :glm))

(fn bounds-corners [bounds]
  (local size (or (and bounds bounds.size) (glm.vec3 0 0 0)))
  (local rotation (or (and bounds bounds.rotation) (glm.quat 1 0 0 0)))
  (local position (or (and bounds bounds.position) (glm.vec3 0 0 0)))
  (local points [])
  (for [ix 0 1]
    (for [iy 0 1]
      (for [iz 0 1]
        (local local-point
          (glm.vec3 (if (= ix 0) 0 size.x)
                    (if (= iy 0) 0 size.y)
                    (if (= iz 0) 0 size.z)))
        (local rotated (rotation:rotate local-point))
        (table.insert points (+ position rotated)))))
  points)

(fn bounds-aabb-min-max [parent child]
  (local rotation (or (and parent parent.rotation) (glm.quat 1 0 0 0)))
  (local inverse (rotation:inverse))
  (local parent-pos (or (and parent parent.position) (glm.vec3 0 0 0)))
  (local min-corner (glm.vec3 500000 500000 500000))
  (local max-corner (glm.vec3 -500000 -500000 -500000))
  (fn finite-number? [value]
    (and (= (type value) :number)
         (= value value)
         (not (= value math.huge))
         (not (= value (- math.huge)))))
  (fn assert-finite-vec3 [vec label]
    (when (or (not vec)
              (not (finite-number? vec.x))
              (not (finite-number? vec.y))
              (not (finite-number? vec.z)))
      (error (.. "BoundsUtils bounds has non-finite " label))))
  (each [_ point (ipairs (bounds-corners child))]
    (local local-point (inverse:rotate (- point parent-pos)))
    (assert-finite-vec3 local-point "local-point")
    (for [axis 1 3]
      (local value (. local-point axis))
      (when (< value (. min-corner axis))
        (set (. min-corner axis) value))
      (when (> value (. max-corner axis))
        (set (. max-corner axis) value))))
  {:min min-corner :max max-corner})

(fn bounds-aabb-in-parent [parent child]
  (local rotation (or (and parent parent.rotation) (glm.quat 1 0 0 0)))
  (local parent-pos (or (and parent parent.position) (glm.vec3 0 0 0)))
  (local parent-size (or (and parent parent.size) (glm.vec3 0 0 0)))
  (local min-max (bounds-aabb-min-max parent child))
  (local min-corner (or (and min-max min-max.min) (glm.vec3 0 0 0)))
  (local max-corner (or (and min-max min-max.max) (glm.vec3 0 0 0)))
  (local clamped-min
    (glm.vec3 (math.max 0 min-corner.x)
              (math.max 0 min-corner.y)
              (math.max 0 min-corner.z)))
  (local clamped-max
    (glm.vec3 (math.min parent-size.x max-corner.x)
              (math.min parent-size.y max-corner.y)
              (math.min parent-size.z max-corner.z)))
  (local size
    (glm.vec3 (math.max 0 (- clamped-max.x clamped-min.x))
              (math.max 0 (- clamped-max.y clamped-min.y))
              (math.max 0 (- clamped-max.z clamped-min.z))))
  (local position (rotation:rotate clamped-min))
  {:position (+ parent-pos position)
   :rotation rotation
   :size size})

{:bounds-corners bounds-corners
 :bounds-aabb-min-max bounds-aabb-min-max
 :bounds-aabb-in-parent bounds-aabb-in-parent}
