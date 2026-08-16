(fn graph-map? [graph]
  (and graph
       graph.graph
       (not (= graph.graph graph))
       graph.nodes
       graph.edges
       graph.edge-map
       graph.lookup
       graph.load-by-key
       graph.add-edge
       graph.node-added
       graph.edge-added
       graph.node-removed
       graph.edge-removed
       graph.node-added.emit
       graph.edge-added.emit
       graph.graph.register-key-loader))

(fn assert-graph-map [graph action]
  (assert (graph-map? graph) (.. action " requires a graph map"))
  graph)

{:graph-map? graph-map?
 :assert-graph-map assert-graph-map}
