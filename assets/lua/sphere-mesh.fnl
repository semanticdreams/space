(local glm (require :glm))

(fn scalar-key [value]
  (string.format "%.17g" (or value 0)))

(fn vec4-key [value]
  (local v (or value (glm.vec4 0 0 0 0)))
  (.. (scalar-key v.x) ":" (scalar-key v.y) ":" (scalar-key v.z) ":" (scalar-key v.w)))

(fn build-mesh [opts]
  (local options (or opts {}))
  (local color (or options.color (glm.vec4 0.5 0.75 1.0 1.0)))
  (local segments (math.max 3 (math.floor (or options.segments 24))))
  (local rings (math.max 2 (math.floor (or options.rings 16))))
  (local vertices [])
  (local indices [])

  (fn point-on-unit-sphere [theta phi]
    (local sin-theta (math.sin theta))
    (glm.vec3 (* sin-theta (math.cos phi))
              (math.cos theta)
              (* sin-theta (math.sin phi))))

  (fn append-vertex [position]
    (local normal
      (if (> (glm.length position) 1e-6)
          (glm.normalize position)
          (glm.vec3 0 1 0)))
    (table.insert vertices {:color color
                            :normal normal
                            :position position})
    (- (length vertices) 1))

  (local theta-step (/ math.pi rings))
  (local phi-step (/ (* 2 math.pi) segments))
  (for [ring 0 (- rings 1)]
    (local theta-1 (* ring theta-step))
    (local theta-2 (* (+ ring 1) theta-step))
    (for [segment 0 (- segments 1)]
      (local phi-1 (* segment phi-step))
      (local phi-2 (* (+ segment 1) phi-step))
      (local p1 (point-on-unit-sphere theta-1 phi-1))
      (local p2 (point-on-unit-sphere theta-2 phi-1))
      (local p3 (point-on-unit-sphere theta-2 phi-2))
      (local p4 (point-on-unit-sphere theta-1 phi-2))
      (local i1 (append-vertex p1))
      (local i2 (append-vertex p2))
      (local i3 (append-vertex p3))
      (local i4 (append-vertex p4))
      (table.insert indices i1)
      (table.insert indices i2)
      (table.insert indices i3)
      (table.insert indices i1)
      (table.insert indices i3)
      (table.insert indices i4)))

  {:vertices vertices
   :indices indices})

{:build-mesh build-mesh
 :scalar-key scalar-key
 :vec4-key vec4-key}
