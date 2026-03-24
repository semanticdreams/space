(local PolyhedronMeshes (require :polyhedron-meshes))

(local tests [])

(fn truncated-icosahedron-has-expected-face-counts []
  (local geometry (PolyhedronMeshes.truncated-icosahedron))
  (var pentagons 0)
  (var hexagons 0)
  (each [_ face (ipairs geometry.faces)]
    (if (= face.kind :pentagon)
        (set pentagons (+ pentagons 1))
        (= face.kind :hexagon)
        (set hexagons (+ hexagons 1))))
  (assert (= pentagons 12)
          (string.format "Expected 12 pentagons, got %d" pentagons))
  (assert (= hexagons 20)
          (string.format "Expected 20 hexagons, got %d" hexagons)))

(fn truncated-icosahedron-triangulates-all-faces []
  (local geometry (PolyhedronMeshes.truncated-icosahedron))
  (local triangles
    (PolyhedronMeshes.triangulate-faces
      geometry.faces
      (fn [_face] nil)))
  (assert (= (length triangles) 116)
          (string.format "Expected 116 triangles, got %d" (length triangles))))

(table.insert tests {:name "Truncated icosahedron has expected face counts"
                     :fn truncated-icosahedron-has-expected-face-counts})
(table.insert tests {:name "Truncated icosahedron triangulates all faces"
                     :fn truncated-icosahedron-triangulates-all-faces})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "polyhedron-meshes"
                       :tests tests})))

{:name "polyhedron-meshes"
 :tests tests
 :main main}
