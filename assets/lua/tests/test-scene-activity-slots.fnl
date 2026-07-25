(local glm (require :glm))
(local Main (require :main))
(local Scene (require :scene))
(local Camera (require :camera))
(local AppProjection (require :app-projection))

(local tests [])

(fn make-scene []
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local scene (Scene {:camera camera}))
  {:camera camera
   :scene scene})

(fn drop-fixture [fixture]
  (fixture.scene:drop)
  (fixture.camera:drop))

(fn with-restored-app-fields [keys f]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs keys)]
    (set (. app key) (. snapshot key)))
  (if ok
      result
      (error result)))

(fn ensure-activity-slot-returns-same-slot []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
  (assert (= sandbox-slot (scene:ensure-activity-slot "sandbox"))
          "Scene should retain one slot per activity id")
  (local graph-slot (scene:ensure-activity-slot "graph"))
  (assert (not (= sandbox-slot graph-slot))
          "Different activity ids should create different slots")
  (assert (= sandbox-slot.activity-id "sandbox"))
  (assert (= graph-slot.activity-id "graph"))
  (drop-fixture fixture))

(fn slot-has-distinct-context-and-root []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
  (assert sandbox-slot.ctx
          "Activity slot should have a build context")
  (assert (not (= sandbox-slot.ctx scene.build-context))
          "Activity slot should not share the Scene surface build context")
  (assert sandbox-slot.layout-root
          "Activity slot should have a layout root")
  (assert (not (= sandbox-slot.layout-root scene.layout-root))
          "Activity slot should not share the Scene surface layout root")
  (assert (not sandbox-slot.visible?))
  (assert (not sandbox-slot.interactive?))
  (drop-fixture fixture))

(fn active-slot-controls-render-context []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
  (local graph-slot (scene:ensure-activity-slot "graph"))

  ;; Before activation, draw sources return surface context
  (assert (= (scene:get-triangle-vector) scene.build-context.triangle-vector)
          "Inactive slots should not replace render context")
  (assert (= (scene:get-line-vector) scene.build-context.line-vector)
          "Inactive slots should not replace line context")

  ;; Activate sandbox
  (scene:activate-activity-slot "sandbox")
  (assert sandbox-slot.visible?)
  (assert sandbox-slot.interactive?)
  (assert (= (scene:get-triangle-vector) sandbox-slot.ctx.triangle-vector)
          "Active slot triangle data should be exposed for rendering")
  (assert (= (scene:get-line-vector) sandbox-slot.ctx.line-vector)
          "Active slot line data should be exposed for rendering")
  (assert (= (scene:get-point-vector) sandbox-slot.ctx.point-vector)
          "Active slot point data should be exposed for rendering")
  (assert (= (scene:get-line-strips) sandbox-slot.ctx.line-strips)
          "Active slot line strips should be exposed for rendering")
  (assert (= (scene:get-image-batches) sandbox-slot.ctx.image-batches)
          "Active slot image batches should be exposed for rendering")

  ;; Activate graph should hide sandbox without dropping
  (var sandbox-dropped? false)
  (set sandbox-slot.root {:drop (fn [_] (set sandbox-dropped? true))})
  (scene:activate-activity-slot "graph")
  (assert (not sandbox-slot.visible?)
          "Activating a new slot should hide the previous slot")
  (assert (not sandbox-dropped?)
          "Activating another slot must not drop the inactive slot root")
  (assert graph-slot.visible?)
  (assert (= (scene:get-triangle-vector) graph-slot.ctx.triangle-vector)
          "Switching slots should switch render data immediately")

  ;; Deactivate clears active slot
  (scene:deactivate-activity-slot "graph")
  (assert (not graph-slot.visible?))
  (assert (= (scene:get-triangle-vector) scene.build-context.triangle-vector)
          "Deactivating the active slot should stop exposing activity draw data")

  (drop-fixture fixture))

(fn slot-pointer-target-routing []
  (with-restored-app-fields
    [:scene
     :scene-interactive?
     :pointer-target-enabled?]
    (fn []
      (Main.install-app-shell!)
      (local fixture (make-scene))
      (local scene fixture.scene)
      (set app.scene scene)
      (set app.scene-interactive? true)

      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
      (local graph-slot (scene:ensure-activity-slot "graph"))

      ;; Inactive slot pointer target should be rejected
      (assert (not (app.pointer-target-enabled? sandbox-slot.pointer-target))
              "Inactive activity slot pointer target should be rejected")

      ;; Activate sandbox
      (scene:activate-activity-slot "sandbox")
      (assert (app.pointer-target-enabled? sandbox-slot.pointer-target)
              "Active activity slot pointer target should be enabled")

      ;; Switch to graph
      (scene:activate-activity-slot "graph")
      (assert (not (app.pointer-target-enabled? sandbox-slot.pointer-target))
              "Previously active slot pointer target should be rejected after switch")
      (assert (app.pointer-target-enabled? graph-slot.pointer-target))

      ;; Deactivate
      (scene:deactivate-activity-slot "graph")
      (assert (not (app.pointer-target-enabled? graph-slot.pointer-target)))

      (drop-fixture fixture))))

(fn drop-activity-slot-removes-content []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local slot (scene:activate-activity-slot "sandbox"))
  (var dropped? false)
  (set slot.root {:drop (fn [_] (set dropped? true))})

  (scene:drop-activity-slot "sandbox")
  (assert dropped?
          "Dropping an activity slot should drop its retained root")
  (assert (= (scene:activity-slot "sandbox") nil))
  (assert (= scene.active-activity-slot nil))
  (assert (= scene.active-activity-slot-id nil))
  (assert (= (scene:get-triangle-vector) scene.build-context.triangle-vector))

  (drop-fixture fixture))

(fn activity-slot-returns-nil-for-unknown []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (assert (= (scene:activity-slot "nonexistent") nil)
          "activity-slot should return nil for unknown ids")
  (assert (= (scene:deactivate-activity-slot "nonexistent") nil)
          "deactivate-activity-slot should return nil for unknown ids")
  (drop-fixture fixture))

(table.insert tests {:name "Scene activity slots return same slot on repeat"
                     :fn ensure-activity-slot-returns-same-slot})
(table.insert tests {:name "Scene activity slots have distinct context and root"
                     :fn slot-has-distinct-context-and-root})
(table.insert tests {:name "Scene active slot controls render context"
                     :fn active-slot-controls-render-context})
(table.insert tests {:name "Scene slot pointer target routing"
                     :fn slot-pointer-target-routing})
(table.insert tests {:name "Scene activity slot drop removes content"
                     :fn drop-activity-slot-removes-content})
(table.insert tests {:name "Scene activity-slot returns nil for unknown"
                     :fn activity-slot-returns-nil-for-unknown})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-activity-slots"
                       :tests tests})))

{:name "scene-activity-slots"
 :tests tests
 :main main}
