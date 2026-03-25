(local glm (require :glm))
(local MathUtils (require :math-utils))
(local SoccerBallVisual (require :soccer-ball-visual))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec4-approx= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn read-vertex [data idx]
  (local offset (* (- idx 1) 10))
  {:color (glm.vec4 (. data (+ offset 1))
                    (. data (+ offset 2))
                    (. data (+ offset 3))
                    (. data (+ offset 4)))
   :position (glm.vec3 (. data (+ offset 8))
                       (. data (+ offset 9))
                       (. data (+ offset 10)))})

(fn make-test-ctx []
  (local batches [])
  {:instanced-color-mesh-batches batches
   :register-instanced-color-mesh-batch (fn [_self batch]
                                          (table.insert batches batch)
                                          batch)
   :unregister-instanced-color-mesh-batch (fn [_self batch]
                                            (for [idx 1 (length batches)]
                                              (when (= (. batches idx) batch)
                                                (table.remove batches idx)
                                                (lua "break")))
                                            nil)})

(fn soccer-ball-fill-subdivision-curves-silhouette []
  (local seam-color (glm.vec4 1 0 0 1))
  (local ctx (make-test-ctx))
  (local visual
    ((SoccerBallVisual {:size 2
                        :seam-color seam-color
                        :pentagon-color (glm.vec4 0 0 0 1)
                        :hexagon-color (glm.vec4 1 1 1 1)})
     ctx))
  (visual.layout:measurer)
  (set visual.layout.size visual.layout.measure)
  (set visual.layout.position (glm.vec3 0 0 0))
  (set visual.layout.rotation (glm.quat 1 0 0 0))
  (visual.layout:layouter)

  (assert (= (length ctx.instanced-color-mesh-batches) 1)
          (string.format "Expected one shared instanced mesh batch, got %d"
                         (length ctx.instanced-color-mesh-batches)))

  (local batch (. ctx.instanced-color-mesh-batches 1))
  (local raw-data (batch.vertex-vector:view batch.vertex-handle))
  (local vertex-count (/ (length raw-data) 10))
  (local triangle-count (/ batch.index-count 3))
  (var min-x math.huge)
  (var min-y math.huge)
  (var min-z math.huge)
  (var max-x (- math.huge))
  (var max-y (- math.huge))
  (var max-z (- math.huge))
  (for [idx 1 vertex-count]
    (local vertex (read-vertex raw-data idx))
    (when (< vertex.position.x min-x)
      (set min-x vertex.position.x))
    (when (< vertex.position.y min-y)
      (set min-y vertex.position.y))
    (when (< vertex.position.z min-z)
      (set min-z vertex.position.z))
    (when (> vertex.position.x max-x)
      (set max-x vertex.position.x))
    (when (> vertex.position.y max-y)
      (set max-y vertex.position.y))
    (when (> vertex.position.z max-z)
      (set max-z vertex.position.z)))
  (local center (glm.vec3 (* (+ min-x max-x) 0.5)
                          (* (+ min-y max-y) 0.5)
                          (* (+ min-z max-z) 0.5)))
  (var max-fill-radius 0)
  (var min-fill-radius math.huge)
  (var max-radius 0)
  (for [idx 1 vertex-count]
    (local vertex (read-vertex raw-data idx))
    (local radius (glm.length (- vertex.position center)))
    (when (> radius max-radius)
      (set max-radius radius))
    (when (not (vec4-approx= vertex.color seam-color))
      (when (> radius max-fill-radius)
        (set max-fill-radius radius))
      (when (< radius min-fill-radius)
        (set min-fill-radius radius))))

  (assert (> triangle-count 540)
          (string.format "Expected subdivided soccer ball mesh to exceed 540 triangles, got %d"
                         triangle-count))
  (assert (> max-fill-radius 0.99)
          (string.format "Expected curved fill to reach sphere radius, got %.4f"
                         max-fill-radius))
  (assert (< min-fill-radius 0.98)
          (string.format "Expected inset panel edge to remain inside sphere radius, got %.4f"
                         min-fill-radius))
  (assert (<= max-radius 1.0001)
          (string.format "Expected soccer ball vertices to stay within the unit sphere, got %.4f"
                         max-radius))

  (batch.vertex-vector:clear-dirty)
  (batch.instance-vector:clear-dirty)
  (set visual.layout.position (glm.vec3 5 0 0))
  (visual.layout:layouter)
  (local (vertex-dirty-from _vertex-dirty-to) (batch.vertex-vector:dirty-range))
  (assert (= vertex-dirty-from nil)
          "Moving soccer ball visual should not dirty shared vertex data")
  (local (instance-dirty-from instance-dirty-to) (batch.instance-vector:dirty-range))
  (assert (and instance-dirty-from instance-dirty-to (> instance-dirty-to instance-dirty-from))
          "Moving soccer ball visual should dirty instance transform data")

  (visual:drop)
  (assert (= (length ctx.instanced-color-mesh-batches) 0)
          "Dropping the only soccer ball should release the shared batch"))

(fn soccer-ball-visual-shares-batch-per-context []
  (local ctx (make-test-ctx))
  (local left ((SoccerBallVisual {:size 2}) ctx))
  (local right ((SoccerBallVisual {:size 2}) ctx))

  (left.layout:measurer)
  (right.layout:measurer)
  (set left.layout.size left.layout.measure)
  (set right.layout.size right.layout.measure)
  (set left.layout.position (glm.vec3 0 0 0))
  (set right.layout.position (glm.vec3 2 0 0))
  (set left.layout.rotation (glm.quat 1 0 0 0))
  (set right.layout.rotation (glm.quat 1 0 0 0))
  (left.layout:layouter)
  (right.layout:layouter)

  (assert (= (length ctx.instanced-color-mesh-batches) 1)
          (string.format "Expected same-style soccer balls to share one batch, got %d"
                         (length ctx.instanced-color-mesh-batches)))
  (local batch (. ctx.instanced-color-mesh-batches 1))
  (assert (= (batch.instance-vector:length) (* 2 batch.instance-stride))
          (string.format "Expected two soccer ball instances in shared buffer, got %d floats"
                         (batch.instance-vector:length)))
  (assert (< batch.vertex-count batch.index-count)
          "Indexed soccer ball mesh should store fewer unique vertices than expanded indices")

  (left:drop)
  (assert (= (length ctx.instanced-color-mesh-batches) 1)
          "Shared batch should remain while one soccer ball still exists")
  (right:drop)
  (assert (= (length ctx.instanced-color-mesh-batches) 0)
          "Shared batch should release after the last soccer ball drops"))

(table.insert tests {:name "Soccer ball visual curves panel fill without expanding silhouette"
                     :fn soccer-ball-fill-subdivision-curves-silhouette})
(table.insert tests {:name "Soccer ball visual shares one mesh batch per context"
                     :fn soccer-ball-visual-shares-batch-per-context})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "soccer-ball-visual"
                       :tests tests})))

{:name "soccer-ball-visual"
 :tests tests
 :main main}
