(local Graph (require :graph/init))

(local tests [])

(fn graph-core-adds-nodes-and-edges []
    (local graph (Graph {:with-start false}))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-node b {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (assert (= (graph:node-count) 2) "Graph core should track node count")
    (assert (= (graph:edge-count) 1) "Graph core should track edge count")
    (assert (graph:lookup "a") "Graph core should lookup nodes by key")
    (graph:drop))

(fn graph-core-replaces-node-and-updates-edges []
    (local graph (Graph {:with-start false}))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-node b {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (var replaced nil)
    (local handler (graph.node-replaced:connect (fn [payload]
                                                    (set replaced payload))))
    (local a2 (Graph.GraphNode {:key "a"}))
    (graph:add-node a2 {})
    (assert replaced "Graph core should emit node-replaced")
    (assert (= replaced.old a) "Graph core should report replaced node")
    (assert (= replaced.new a2) "Graph core should report replacement node")
    (local edge (. graph.edges 1))
    (assert (= edge.source a2) "Graph core should update edge source to replacement node")
    (graph.node-replaced:disconnect handler true)
    (graph:drop))

(fn graph-core-removes-nodes-and-edges []
    (local graph (Graph {:with-start false}))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-node b {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (var removed nil)
    (var edge-removed 0)
    (local node-handler (graph.node-removed:connect (fn [payload]
                                                        (set removed payload))))
    (local edge-handler (graph.edge-removed:connect (fn [_payload]
                                                        (set edge-removed (+ edge-removed 1)))))
    (local count (graph:remove-nodes [b]))
    (assert (= count 1) "Graph core should report removed nodes")
    (assert removed "Graph core should emit node-removed payload")
    (assert (= (length removed.nodes) 1) "Graph core should include removed node list")
    (assert (rawget removed.removal-set b) "Graph core should include removal set")
    (assert (= edge-removed 1) "Graph core should emit edge-removed for connected edges")
    (assert (= (graph:edge-count) 0) "Graph core should remove edges when nodes are removed")
    (graph.node-removed:disconnect node-handler true)
    (graph.edge-removed:disconnect edge-handler true)
    (graph:drop))

(fn graph-core-emits-node-and-edge-added []
    (local graph (Graph {:with-start false}))
    (var node-added 0)
    (var edge-added 0)
    (local node-handler (graph.node-added:connect (fn [_payload]
                                                      (set node-added (+ node-added 1)))))
    (local edge-handler (graph.edge-added:connect (fn [_payload]
                                                      (set edge-added (+ edge-added 1)))))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (assert (= node-added 2) "Graph core should emit node-added for source and target")
    (assert (= edge-added 1) "Graph core should emit edge-added")
    (graph.node-added:disconnect node-handler true)
    (graph.edge-added:disconnect edge-handler true)
    (graph:drop))

(table.insert tests {:name "Graph core adds nodes and edges" :fn graph-core-adds-nodes-and-edges})
(table.insert tests {:name "Graph core replaces nodes and updates edges" :fn graph-core-replaces-node-and-updates-edges})
(table.insert tests {:name "Graph core removes nodes and edges" :fn graph-core-removes-nodes-and-edges})
(table.insert tests {:name "Graph core emits node and edge added signals" :fn graph-core-emits-node-and-edge-added})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-core"
                       :tests tests})))

{:name "graph-core"
 :tests tests
 :main main}
