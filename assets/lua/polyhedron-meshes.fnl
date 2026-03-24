(local glm (require :glm))

(local golden-ratio (/ (+ 1 (math.sqrt 5)) 2))

(local icosahedron-vertices
  [(glm.vec3 -1 golden-ratio 0)
   (glm.vec3 1 golden-ratio 0)
   (glm.vec3 -1 (- golden-ratio) 0)
   (glm.vec3 1 (- golden-ratio) 0)
   (glm.vec3 0 -1 golden-ratio)
   (glm.vec3 0 1 golden-ratio)
   (glm.vec3 0 -1 (- golden-ratio))
   (glm.vec3 0 1 (- golden-ratio))
   (glm.vec3 golden-ratio 0 -1)
   (glm.vec3 golden-ratio 0 1)
   (glm.vec3 (- golden-ratio) 0 -1)
   (glm.vec3 (- golden-ratio) 0 1)])

(local icosahedron-faces
  [[0 11 5]
   [0 5 1]
   [0 1 7]
   [0 7 10]
   [0 10 11]
   [1 5 9]
   [5 11 4]
   [11 10 2]
   [10 7 6]
   [7 1 8]
   [3 9 4]
   [3 4 2]
   [3 2 6]
   [3 6 8]
   [3 8 9]
   [4 9 5]
   [2 4 11]
   [6 2 10]
   [8 6 7]
   [9 8 1]])

(fn copy-vec3 [v]
  (glm.vec3 v.x v.y v.z))

(fn lerp-vec3 [a b t]
  (+ (* a (glm.vec3 (- 1 t)))
     (* b (glm.vec3 t))))

(fn face-center [face]
  (/ (+ (. face 1) (. face 2) (. face 3))
     (glm.vec3 3 3 3)))

(fn polygon-normal [vertices]
  (if (< (length vertices) 3)
      (glm.vec3 0 0 0)
      (glm.cross (- (. vertices 2) (. vertices 1))
                 (- (. vertices 3) (. vertices 1)))))

(fn reverse-array [items]
  (local reversed [])
  (for [idx (length items) 1 -1]
    (table.insert reversed (. items idx)))
  reversed)

(fn orient-polygon-outward [vertices outward]
  (local normal (polygon-normal vertices))
  (if (< (glm.dot normal outward) 0)
      (reverse-array vertices)
      vertices))

(fn sort-polygon-vertices [vertices outward]
  (local normal (glm.normalize outward))
  (local centroid
    (/ (accumulate [sum (glm.vec3 0 0 0) _ vertex (ipairs vertices)]
                   (+ sum vertex))
       (glm.vec3 (length vertices)
                 (length vertices)
                 (length vertices))))
  (local reference-axis
    (if (< (math.abs normal.y) 0.9)
        (glm.vec3 0 1 0)
        (glm.vec3 1 0 0)))
  (local tangent-u (glm.normalize (glm.cross reference-axis normal)))
  (local tangent-v (glm.cross normal tangent-u))
  (local keyed [])
  (each [_ vertex (ipairs vertices)]
    (local direction (- vertex centroid))
    (table.insert keyed {:vertex vertex
                         :angle (math.atan (glm.dot direction tangent-v)
                                           (glm.dot direction tangent-u))}))
  (table.sort keyed (fn [a b] (< a.angle b.angle)))
  (icollect [_ entry (ipairs keyed)] entry.vertex))

(fn append-unique-neighbor [neighbors value]
  (var exists? false)
  (each [_ current (ipairs neighbors)]
    (when (= current value)
      (set exists? true)))
  (when (not exists?)
    (table.insert neighbors value)))

(fn normalize-faces [faces]
  (var radius 0.0)
  (each [_ face (ipairs faces)]
    (each [_ vertex (ipairs face.vertices)]
      (set radius (math.max radius (glm.length vertex)))))
  (local scale
    (if (> radius 0)
        (/ 1 radius)
        1))
  (icollect [_ face (ipairs faces)]
            {:kind face.kind
             :vertices (icollect [_ vertex (ipairs face.vertices)]
                                 (* vertex (glm.vec3 scale))) }))

(fn triangulate-face [face resolve-color]
  (local color (resolve-color face))
  (local centroid
    (/ (accumulate [sum (glm.vec3 0 0 0) _ vertex (ipairs face.vertices)]
                   (+ sum vertex))
       (glm.vec3 (length face.vertices)
                 (length face.vertices)
                 (length face.vertices))))
  (local triangles [])
  (for [idx 2 (- (length face.vertices) 1)]
    (table.insert triangles {:a centroid
                             :b (. face.vertices idx)
                             :c (. face.vertices (+ idx 1))
                             :color color
                             :kind face.kind}))
  triangles)

(fn triangulate-faces [faces resolve-color]
  (accumulate [triangles [] _ face (ipairs faces)]
              (do
                (each [_ triangle (ipairs (triangulate-face face resolve-color))]
                  (table.insert triangles triangle))
                triangles)))

(fn merge-face-lists [left right]
  (local merged [])
  (each [_ face (ipairs left)]
    (table.insert merged face))
  (each [_ face (ipairs right)]
    (table.insert merged face))
  merged)

(fn truncated-icosahedron [_opts]
  (local cut-points {})
  (each [i vertex (ipairs icosahedron-vertices)]
    (local keymap {})
    (set (. cut-points (- i 1)) keymap)
    (each [j neighbor (ipairs icosahedron-vertices)]
      (when (not (= i j))
        (set (. keymap (- j 1))
             (lerp-vec3 vertex neighbor (/ 1 3))))))

  (local hexagons
    (icollect [_ face-indices (ipairs icosahedron-faces)]
              (do
                (local a (. face-indices 1))
                (local b (. face-indices 2))
                (local c (. face-indices 3))
                (local outward
                  (face-center [(copy-vec3 (. icosahedron-vertices (+ a 1)))
                                (copy-vec3 (. icosahedron-vertices (+ b 1)))
                                (copy-vec3 (. icosahedron-vertices (+ c 1)))]))
                (local vertices
                  [(. (. cut-points a) b)
                   (. (. cut-points b) a)
                   (. (. cut-points b) c)
                   (. (. cut-points c) b)
                   (. (. cut-points c) a)
                   (. (. cut-points a) c)])
                {:kind :hexagon
                 :vertices
                 (orient-polygon-outward
                   (sort-polygon-vertices vertices outward)
                   outward)})))

  (local neighbor-map {})
  (each [index _vertex (ipairs icosahedron-vertices)]
    (set (. neighbor-map (- index 1)) []))
  (each [_ face-indices (ipairs icosahedron-faces)]
    (local a (. face-indices 1))
    (local b (. face-indices 2))
    (local c (. face-indices 3))
    (append-unique-neighbor (. neighbor-map a) b)
    (append-unique-neighbor (. neighbor-map a) c)
    (append-unique-neighbor (. neighbor-map b) a)
    (append-unique-neighbor (. neighbor-map b) c)
    (append-unique-neighbor (. neighbor-map c) a)
    (append-unique-neighbor (. neighbor-map c) b))

  (local pentagons
    (icollect [vertex-index vertex (ipairs icosahedron-vertices)]
              (do
                (local neighbors (. neighbor-map (- vertex-index 1)))
                (local vertices
                  (icollect [_ neighbor-index (ipairs neighbors)]
                            (. (. cut-points (- vertex-index 1)) neighbor-index)))
                {:kind :pentagon
                 :vertices
                 (orient-polygon-outward
                   (sort-polygon-vertices vertices vertex)
                   vertex)})))

  {:faces (normalize-faces (merge-face-lists pentagons hexagons))
   :triangulate-faces triangulate-faces})

{:truncated-icosahedron truncated-icosahedron
 :triangulate-faces triangulate-faces}
