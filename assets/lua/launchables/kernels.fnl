{:name "Kernels"
 :run (fn []
        (local graph (or app.graph-map
               (and app.active-world-runtime app.active-world-runtime.graph-map)))
        (assert graph "Kernels launchable requires a graph-map")
        (local kernels-node
          (if graph.load-by-key
              (graph:load-by-key "kernels")
              nil))
        (when (and kernels-node graph.add-node)
          (graph:add-node kernels-node))
        kernels-node)}
