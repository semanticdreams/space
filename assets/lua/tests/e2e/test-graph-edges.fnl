(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout} (require :layout))
(local fs (require :fs))

(fn run [ctx]
  (local focus-manager (FocusManager {:root-name "e2e-graph-edges"}))
  (var view nil)
  (var graph nil)
  (local data-root (fs.join-path "/tmp/space/tests" "graph-edges"))
  (when (fs.exists data-root)
    (fs.remove-all data-root))
  (fs.create-dirs data-root)
  (local screen-target
    (Harness.make-screen-target
      {:focus-manager focus-manager
       :builder (fn [ctx]
                  (set graph (Graph {:with-start false}))
                  (set view (GraphView {:graph-map graph
                                        :ctx ctx
                                        :edge-color (glm.vec4 1.0 0.2 0.1 1.0)
                                        :edge-thickness 8.0
                                        :data-dir data-root}))
                  (local node-a (Graph.GraphNode {:key "node-a"
                                                  :label "A"
                                                  :color (glm.vec4 0.3 0.55 0.95 1)
                                                  :size 6}))
                  (local node-b (Graph.GraphNode {:key "node-b"
                                                  :label "B"
                                                  :color (glm.vec4 0.62 0.88 0.35 1)
                                                  :size 6}))
                  (graph:add-node node-a {:position (glm.vec3 6 9 0)
                                          :run-force? false})
                  (graph:add-node node-b {:position (glm.vec3 26 10 0)
                                          :run-force? false})
                  (graph:add-edge (Graph.GraphEdge {:source node-a
                                                    :target node-b
                                                    :color (glm.vec4 1.0 0.2 0.1 1.0)})
                                  {:run-force? false})
                  (view:update 0.016)
                  (local layout
                    (Layout {:name "graph-edges"
                             :measurer (fn [self]
                                         (set self.measure (glm.vec3 0 0 0)))
                             :layouter (fn [self]
                                         (set self.size self.measure))}))
                  {:layout layout
                   :drop (fn [_self]
                           (when view
                             (view:drop))
                           (when graph
                             (graph:drop))
                           (layout:drop))})}))
  (Harness.draw-targets ctx.width ctx.height [{:target screen-target}])
  (Harness.capture-snapshot {:name "graph-edges"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (Harness.cleanup-target screen-target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E graph-edges snapshot complete"))

{:run run
 :main main}
