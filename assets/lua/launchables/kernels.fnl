{:name "Kernels"
 :run (fn []
        (assert (and app app.graph) "Kernels launchable requires app.graph")
        (local kernels-node
          (if app.graph.load-by-key
              (app.graph:load-by-key "kernels")
              nil))
        (when (and kernels-node app.graph.add-node)
          (app.graph:add-node kernels-node))
        kernels-node)}
