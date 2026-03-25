(local glm (require :glm))
(local PolyhedronMeshes (require :polyhedron-meshes))

(local cached-geometry (PolyhedronMeshes.truncated-icosahedron))
(local default-fill-subdivisions 2)

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

(fn face-target-radius [vertices]
  (accumulate [radius 0 _ vertex (ipairs vertices)]
              (math.max radius (glm.length vertex))))

(fn midpoint-vertex [left right]
  {:position (* (+ left.position right.position)
                (glm.vec3 0.5 0.5 0.5))
   :boundary? (and left.boundary? right.boundary?)})

(fn resolve-fill-vertex-position [vertex target-radius]
  (if vertex.boundary?
      vertex.position
      (> (glm.length vertex.position) 1e-6)
      (* (glm.normalize vertex.position)
         (glm.vec3 target-radius target-radius target-radius))
      vertex.position))

(fn append-subdivided-fill-triangle [triangles a b c depth target-radius color]
  (if (<= depth 0)
      (table.insert triangles {:a (resolve-fill-vertex-position a target-radius)
                               :b (resolve-fill-vertex-position b target-radius)
                               :c (resolve-fill-vertex-position c target-radius)
                               :color color})
      (do
        (local ab (midpoint-vertex a b))
        (local bc (midpoint-vertex b c))
        (local ca (midpoint-vertex c a))
        (append-subdivided-fill-triangle triangles a ab ca (- depth 1) target-radius color)
        (append-subdivided-fill-triangle triangles ab b bc (- depth 1) target-radius color)
        (append-subdivided-fill-triangle triangles ca bc c (- depth 1) target-radius color)
        (append-subdivided-fill-triangle triangles ab bc ca (- depth 1) target-radius color))))

(fn triangulate-curved-face [vertices color subdivisions]
  (local centroid (face-centroid vertices))
  (local target-radius (face-target-radius vertices))
  (local triangles [])
  (for [idx 1 (length vertices)]
    (local next-idx
      (if (= idx (length vertices))
          1
          (+ idx 1)))
    (append-subdivided-fill-triangle
      triangles
      {:position centroid :boundary? false}
      {:position (. vertices idx) :boundary? true}
      {:position (. vertices next-idx) :boundary? true}
      subdivisions
      target-radius
      color))
  triangles)

(fn triangle-normal [triangle]
  (local normal (glm.cross (- triangle.b triangle.a)
                           (- triangle.c triangle.a)))
  (if (> (glm.length normal) 1e-6)
      (glm.normalize normal)
      (glm.normalize (face-centroid [triangle.a triangle.b triangle.c]))))

(fn triangle->vertices [triangle]
  (local normal (triangle-normal triangle))
  [{:color triangle.color :normal normal :position triangle.a}
   {:color triangle.color :normal normal :position triangle.b}
   {:color triangle.color :normal normal :position triangle.c}])

(fn scalar-key [value]
  (string.format "%.17g" (or value 0)))

(fn vec3-key [value]
  (local v (or value (glm.vec3 0 0 0)))
  (.. (scalar-key v.x) ":" (scalar-key v.y) ":" (scalar-key v.z)))

(fn vec4-key [value]
  (local v (or value (glm.vec4 0 0 0 0)))
  (.. (scalar-key v.x) ":" (scalar-key v.y) ":" (scalar-key v.z) ":" (scalar-key v.w)))

(fn vertex-key [vertex]
  (.. (vec3-key vertex.position)
      "|"
      (vec3-key vertex.normal)
      "|"
      (vec4-key vertex.color)))

(fn style-key [options]
  {:seam-color (or options.seam-color (glm.vec4 0.72 0.72 0.72 1.0))
   :seam-inset (or options.seam-inset 0.05)
   :pentagon-color (or options.pentagon-color (glm.vec4 0.08 0.08 0.08 1.0))
   :hexagon-color (or options.hexagon-color
                      options.color
                      (glm.vec4 0.96 0.96 0.92 1.0))})

(fn build-triangles [options]
  (local triangles [])
  (each [_ face (ipairs cached-geometry.faces)]
    (local fill-color (resolve-face-color options face))
    (local seam-color (or options.seam-color (glm.vec4 0.72 0.72 0.72 1.0)))
    (local inset-factor (or options.seam-inset 0.05))
    (local centroid (face-centroid face.vertices))
    (local inner
      (icollect [_ vertex (ipairs face.vertices)]
                (lerp-vec3 vertex centroid inset-factor)))
    (append-triangles triangles (triangulate-face-ring face.vertices inner seam-color))
    (append-triangles triangles (triangulate-curved-face inner fill-color default-fill-subdivisions)))
  triangles)

(fn build-vertices [options]
  (accumulate [vertices [] _ triangle (ipairs (build-triangles options))]
              (do
                (each [_ vertex (ipairs (triangle->vertices triangle))]
                  (table.insert vertices vertex))
                vertices)))

(fn build-mesh [options]
  (local vertices [])
  (local indices [])
  (local index-by-key {})
  (each [_ triangle (ipairs (build-triangles options))]
    (each [_ vertex (ipairs (triangle->vertices triangle))]
      (local key (vertex-key vertex))
      (local existing (. index-by-key key))
      (if existing
          (table.insert indices existing)
          (do
            (table.insert vertices vertex)
            (local next-index (- (length vertices) 1))
            (set (. index-by-key key) next-index)
            (table.insert indices next-index)))))
  {:vertices vertices
   :indices indices})

{:build-vertices build-vertices
 :build-mesh build-mesh
 :style-key style-key
 :scalar-key scalar-key
 :vec3-key vec3-key
 :vec4-key vec4-key
 :vertex-key vertex-key}
