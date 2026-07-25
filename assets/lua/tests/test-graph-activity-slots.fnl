(local glm (require :glm))
(local fs (require :fs))
(local Activities (require :activities))
(local Graph (require :graph/init))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local ObjectSelector (require :object-selector))
(local GraphActivityUnit (require :graph-activity-unit))
(local {: FocusManager} (require :focus))

(local tests [])

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn graph-activity-builds-view-in-canvas-slot []
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph-view
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :canvas-controls
                   :first-person-controls
                   :viewport
                   :themes])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.themes {:get-active-theme
                   (fn []
                     {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                              :label-color (glm.vec4 1 1 1 1)
                              :label-target-pixels 13.0
                              :label-min-scale 4.0
                              :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                      :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})})
  (local data-dir "/tmp/space/tests/graph-activity-slots")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-activity-slot-test"}))
  (local canvas (Canvas {:camera camera
                          :focus-manager focus-manager}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local runtime {:canvas canvas
                  :graph graph
                  :object-selector object-selector
                  :movables app.movables
                  :canvas-camera camera
                  :world-dir data-dir})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (Activities.activate-activity "graph")
        (local slot (canvas:activity-slot "graph"))
        (assert slot "Graph activity should create a graph canvas slot")
        (assert (= canvas.active-activity-slot slot)
                "Graph activity should activate its canvas slot")
        (assert (= slot.pointer-target.canvas-target-kind :graph-view)
                "Graph activity slot should expose graph view target kind")
        (assert app.graph-view "Graph activity should create a graph view")
        (assert (= app.graph-view.ctx slot.ctx)
                "Graph view should be built with the graph slot context")
        (assert (= app.graph-view.ctx.pointer-target slot.pointer-target)
                "Graph view context should route interactions through the graph slot pointer target")
        (assert (= (canvas:get-triangle-vector) slot.ctx.triangle-vector)
                "Active graph slot draw data should be exposed by the canvas")
        (assert (not (= (canvas:get-triangle-vector) canvas.build-context.triangle-vector))
                "Graph activity should not draw through the default canvas context")
        (object-selector:on-mouse-button {:button 1 :state true :x 100 :y 100})
        (assert (> (length (slot.ctx:get-quad-draw-list)) 0)
                "Graph selector rectangle should draw through the active graph slot context")
        (assert (= (length (canvas.build-context:get-quad-draw-list)) 0)
                "Graph selector rectangle should not draw through the default canvas context")
        (object-selector:cancel-selection)
        (Activities.deactivate-active-activity)
        (assert (not slot.visible?)
                "Deactivating graph activity should hide the graph slot")
        (assert (not app.graph-view)
                "Deactivating graph activity should stop exposing app.graph-view")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when runtime.graph-view
    (runtime.graph-view:drop)
    (set runtime.graph-view nil))
  (object-selector:drop)
  (graph:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph activity builds view in canvas activity slot"
                     :fn graph-activity-builds-view-in-canvas-slot})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-activity-slots"
                       :tests tests})))

{:name "graph-activity-slots"
 :tests tests
 :main main}
