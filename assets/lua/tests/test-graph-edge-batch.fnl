(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local GraphEdgeBatch (require :graph-edge-batch))
(local glm (require :glm))

(local tests [])

(fn graph-edge-batch-marks-dirty-range-after-write []
  (local vector (VectorBuffer 64))
  (local handle-a (vector:allocate 24))
  (local handle-b (vector:allocate 24))
  (vector:clear-dirty)

  (GraphEdgeBatch.write-triangle-batch
    vector
    [handle-a handle-b]
    [(glm.vec3 1 2 3) (glm.vec3 4 5 6)]
    [(glm.vec3 7 8 9) (glm.vec3 10 11 12)]
    [(glm.vec4 1 0 0 1) (glm.vec4 0 1 0 1)]
    [2.0 3.0]
    [1.0 2.0])

  (local (from to) (vector:dirty-range))
  (assert (= from handle-a.index)
          "graph edge batch should dirty from first updated handle")
  (assert (= to (+ handle-b.index 24))
          "graph edge batch should dirty through last updated handle"))

(table.insert tests
              {:name "GraphEdgeBatch marks dirty range after direct writes"
               :fn graph-edge-batch-marks-dirty-range-after-write})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-edge-batch"
                       :tests tests})))

{:name "graph-edge-batch"
 :tests tests
 :main main}
