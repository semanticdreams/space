(local glm (require :glm))
(local Registry (require :graph/view/registry))
(local {:GraphNode GraphNode} (require :graph/node-base))

(local tests [])

(fn make-registry []
    (local nodes {})
    (local nodes-by-index [])
    (local indices {})
    (local points {})
    (local edge-map {})
    (local edges [])
    (local node-by-point {})
    (local pinned {})
    (Registry {:nodes nodes
                                 :nodes-by-index nodes-by-index
                                 :indices indices
                                 :points points
                                 :edge-map edge-map
                                 :edges edges
                                 :node-by-point node-by-point
                                 :pinned pinned}))

(fn registry-assigns-keys-and-registers-nodes []
    (local registry (make-registry))
    (local node (GraphNode {}))
    (registry:canonical-node node "test-node")
    (assert node.key "Registry should assign keys when missing")
    (local point {:position (glm.vec3 1 2 3)})
    (registry:add-node node point 0 true)
    (assert (= (. registry.nodes node.key) node)
            "Registry should register node by key")
    (assert (= (. registry.points node) point)
            "Registry should store point reference")
    (assert (= (. registry.nodes-by-index 1) node)
            "Registry should store node by index")
    (assert (= (registry:index-of node) 0)
            "Registry should expose index lookup")
    (assert (. registry.pinned node)
            "Registry should persist pinned flag"))

(fn registry-replaces-node-and-updates-edges []
    (local registry (make-registry))
    (local original (GraphNode {:key "swap"}))
    (local replacement (GraphNode {:key "swap"}))
    (local target (GraphNode {:key "target"}))
    (local original-point {:position (glm.vec3 5 6 7)})
    (local target-point {:position (glm.vec3 0 0 0)})
    (registry:add-node original original-point 0 true)
    (registry:add-node target target-point 1 false)
    (local edge-record {:edge {:source original :target target}})
    (table.insert registry.edges edge-record)
    (local result (registry:replace original replacement))
    (assert result.point "Registry.replace should return existing point")
    (assert (= result.idx 0)
            "Registry.replace should preserve node index")
    (assert (= (. registry.points replacement) original-point)
            "Registry.replace should keep point mapping")
    (assert (. registry.pinned replacement)
            "Registry.replace should transfer pinned flag")
    (assert (= edge-record.edge.source replacement)
            "Registry.replace should update edge sources"))

(fn registry-add-edge-deduplicates []
    (local registry (make-registry))
    (local source (GraphNode {:key "a"}))
    (local target (GraphNode {:key "b"}))
    (local edge {:source source :target target})
    (local line {:dropped 0
                 :drop (fn [self]
                           (set self.dropped (+ self.dropped 1)))})
    (local (record added?)
          (registry:add-edge edge
              (fn []
                  {:edge edge :line line})))
    (assert added? "Registry.add-edge should report new edge")
    (assert (= (length registry.edges) 1)
            "Registry should append new edge records once")
    (assert (= (. registry.edge-map (registry.edge-key edge)) record)
            "Registry should track edge map entries")
    (local (_ reused?)
          (registry:add-edge edge
              (fn []
                  (error "should not create second record"))))
    (assert (not reused?)
            "Registry.add-edge should not recreate existing edges")
    (assert (= (length registry.edges) 1)
            "Registry should not duplicate edge records on reuse"))

(fn registry-remove-nodes-drops-edges-and-points []
    (local registry (make-registry))
    (local a (GraphNode {:key "a"}))
    (local b (GraphNode {:key "b"}))
    (local point-a {:position (glm.vec3 1 1 1)})
    (local point-b {:position (glm.vec3 2 2 2)})
    (registry:add-node a point-a 0 false)
    (registry:add-node b point-b 1 false)
    (local edge {:source a :target b})
    (local line {:dropped 0
                 :drop (fn [self]
                           (set self.dropped (+ self.dropped 1)))})
    (local record {:edge edge :line line})
    (table.insert registry.edges record)
    (set (. registry.edge-map (registry.edge-key edge)) record)
    (var dropped-points 0)
    (local (removed removal-set)
          (registry:remove-nodes [a]
              {:on-drop-point (fn [_point]
                                   (set dropped-points (+ dropped-points 1)))}))
    (assert (= removed 1)
            "Registry.remove-nodes should return removed count")
    (assert (rawget removal-set a)
            "Registry.remove-nodes should include removal set")
    (assert (= (length registry.edges) 0)
            "Registry.remove-nodes should prune edge list")
    (assert (= (. registry.edge-map (registry.edge-key edge)) nil)
            "Registry.remove-nodes should clear edge-map entries")
    (assert (= (. registry.points a) nil)
            "Registry.remove-nodes should drop point mapping")
    (assert (= dropped-points 1)
            "Registry.remove-nodes should invoke point drop callbacks")
    (assert (= line.dropped 1)
            "Registry.remove-nodes should drop edge lines"))

(table.insert tests {:name "GraphViewRegistry assigns keys and registers nodes" :fn registry-assigns-keys-and-registers-nodes})
(table.insert tests {:name "GraphViewRegistry replaces nodes and updates edges" :fn registry-replaces-node-and-updates-edges})
(table.insert tests {:name "GraphViewRegistry deduplicates edges" :fn registry-add-edge-deduplicates})
(table.insert tests {:name "GraphViewRegistry removes nodes and cleans edges" :fn registry-remove-nodes-drops-edges-and-points})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-registry"
                       :tests tests})))

{:name "graph-view-registry"
 :tests tests
 :main main}
