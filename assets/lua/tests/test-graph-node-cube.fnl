(local _ (require :main))
(local glm (require :glm))
(local BuildContext (require :build-context))
(local GraphNodeCube (require :graph-node-cube))
(local RuntimeTimers (require :runtime-timers))

(local tests [])

(fn make-ui-context []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn graph-node-cube-lod-stops-updating-after-drop []
    (RuntimeTimers.clear)
    (local ctx (make-ui-context))
    (local original-camera app.camera)
    (set app.camera {:position (glm.vec3 0 0 20)})
    (local cube
        ((GraphNodeCube {:node {:key "cube-node"
                                :label "Graph node cube label for lod checks and wrapping"}})
         ctx))
    (cube.layout:measurer)
    (set cube.layout.position (glm.vec3 0 0 0))
    (set cube.layout.size cube.layout.measure)
    (cube.layout:layouter)

    (local front (. cube.faces 1))
    (local near-scale front.label-text.style.scale)
    (set app.camera.position (glm.vec3 0 0 600))
    (app.engine.events.updated:emit 16)
    (local far-scale front.label-text.style.scale)
    (assert (not (= near-scale far-scale))
            "GraphNodeCube should refresh LOD while mounted")

    (cube:drop)
    (set app.camera.position (glm.vec3 0 0 20))
    (app.engine.events.updated:emit 16)
    (assert (= front.label-text.style.scale far-scale)
            "GraphNodeCube drop should stop background LOD updates")

    (set app.camera original-camera)
    (RuntimeTimers.clear))

(table.insert tests {:name "GraphNodeCube LOD stops updating after drop"
                     :fn graph-node-cube-lod-stops-updating-after-drop})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-node-cube"
                           :tests tests})))

{:name "graph-node-cube"
 :tests tests
 :main main}
