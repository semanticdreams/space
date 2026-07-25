(local glm (require :glm))
(local fs (require :fs))
(local Activities (require :activities))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local DrawingController (require :drawing/controller))
(local DrawingActivityUnit (require :drawing-activity-unit))
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

(fn drawing-activity-builds-render-in-canvas-slot []
  (local app-keys [:active-world-runtime
                   :canvas
                   :drawing-controller
                   :drawing-render
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
                   :first-person-controls])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (local data-dir "/tmp/space/tests/drawing-activity-slots")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "drawing-activity-slot-test"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (local controller (DrawingController {:data_dir data-dir}))
  (controller:add-layer "vector")
  (controller:begin-gesture "rectangle" (glm.vec3 0 0 0))
  (controller:update-gesture (glm.vec3 24 12 0) false)
  (assert (controller:commit-gesture)
          "drawing activity slot test expected rectangle commit to succeed")
  (local runtime {:canvas canvas
                  :drawing-controller controller})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.drawing-controller controller)
  (local (ok result)
    (pcall
      (fn []
        (DrawingActivityUnit.load-drawing-activity!)
        (Activities.activate-activity "drawing")
        (local slot (canvas:activity-slot "drawing"))
        (assert slot "Drawing activity should create a drawing canvas slot")
        (assert (= canvas.active-activity-slot slot)
                "Drawing activity should activate its canvas slot")
        (assert app.drawing-render "Drawing activity should create app.drawing-render")
        (assert (= slot.root app.drawing-render)
                "Drawing activity slot should own the drawing render")
        (app.drawing-render:update)
        (assert (= (canvas:get-triangle-vector) slot.ctx.triangle-vector)
                "Active drawing slot draw data should be exposed by the canvas")
        (assert (> (slot.ctx.triangle-vector:length) 0)
                "Drawing render should write vector geometry into the drawing slot")
        (assert (= (canvas.build-context.triangle-vector:length) 0)
                "Drawing activity should not draw through the default canvas context")
        (Activities.deactivate-active-activity)
        (assert (not slot.visible?)
                "Deactivating drawing activity should hide the drawing slot")
        (assert (not app.drawing-render)
                "Deactivating drawing activity should drop app.drawing-render")
        true)))
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (when runtime.drawing-render
    (runtime.drawing-render:drop)
    (set runtime.drawing-render nil))
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Drawing activity builds render in canvas activity slot"
                     :fn drawing-activity-builds-render-in-canvas-slot})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-activity-slots"
                       :tests tests})))

{:name "drawing-activity-slots"
 :tests tests
 :main main}
