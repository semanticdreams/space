(local glm (require :glm))
(local PolyhedronMeshes (require :polyhedron-meshes))
(local PolyhedronWidget (require :polyhedron-widget))

(local cached-geometry (PolyhedronMeshes.truncated-icosahedron))

(fn face-centroid [vertices]
  (/ (accumulate [sum (glm.vec3 0 0 0) _ vertex (ipairs vertices)]
                 (+ sum vertex))
     (glm.vec3 (length vertices)
               (length vertices)
               (length vertices))))

(fn lerp-vec3 [a b t]
  (+ (* a (glm.vec3 (- 1 t)))
     (* b (glm.vec3 t))))

(fn resolve-face-color [options face]
  (if (= face.kind :pentagon)
      (or options.pentagon-color (glm.vec4 0.08 0.08 0.08 1.0))
      (or options.hexagon-color
          options.color
          (glm.vec4 0.96 0.96 0.92 1.0))))

(fn triangulate-face [vertices color]
  (local centroid (face-centroid vertices))
  (local triangles [])
  (for [idx 1 (length vertices)]
    (local next-idx
      (if (= idx (length vertices))
          1
          (+ idx 1)))
    (table.insert triangles {:a centroid
                             :b (. vertices idx)
                             :c (. vertices next-idx)
                             :color color}))
  triangles)

(fn triangulate-face-ring [outer inner color]
  (local triangles [])
  (for [idx 1 (length outer)]
    (local next-idx
      (if (= idx (length outer))
          1
          (+ idx 1)))
    (table.insert triangles {:a (. outer idx)
                             :b (. inner idx)
                             :c (. inner next-idx)
                             :color color})
    (table.insert triangles {:a (. outer idx)
                             :b (. inner next-idx)
                             :c (. outer next-idx)
                             :color color}))
  triangles)

(fn append-triangles [dst triangles]
  (each [_ triangle (ipairs triangles)]
    (table.insert dst triangle))
  dst)

(fn styled-face-triangles [options face]
  (local fill-color (resolve-face-color options face))
  (local seam-color (or options.seam-color (glm.vec4 0.72 0.72 0.72 1.0)))
  (local inset-factor (or options.seam-inset 0.05))
  (local centroid (face-centroid face.vertices))
  (local inner
    (icollect [_ vertex (ipairs face.vertices)]
              (lerp-vec3 vertex centroid inset-factor)))
  (local triangles [])
  (append-triangles triangles (triangulate-face-ring face.vertices inner seam-color))
  (append-triangles triangles (triangulate-face inner fill-color))
  triangles)

(fn SoccerBallVisual [opts]
  (local options (or opts {}))
  (local triangles [])
  (each [_ face (ipairs cached-geometry.faces)]
    (append-triangles triangles (styled-face-triangles options face)))

  (PolyhedronWidget {:name "soccer-ball"
                     :size options.size
                     :triangles triangles}))

SoccerBallVisual
