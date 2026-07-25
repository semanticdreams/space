(local glm (require :glm))
(local Main (require :main))
(local Scene (require :scene))
(local Camera (require :camera))
(local AppProjection (require :app-projection))
(local {: FocusManager} (require :focus))

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

(fn active-slot-batch-accessors-route-correctly []
  ;; R1-4: Exercise all renderer-facing batch accessors with sentinel monkeypatching.
  ;; Each context gets distinct sentinels so we can assert exact routing through the
  ;; active-render-context path: surface before activation, Sandbox when active,
  ;; Graph after switch, surface after deactivation.
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
  (local graph-slot (scene:ensure-activity-slot "graph"))

  ;; Sentinels: surface context
  (set scene.build-context.get-triangle-batches (fn [_ctx] :surface-triangle-batches))
  (set scene.build-context.get-quad-draw-list (fn [_ctx] :surface-quad-draw-list))
  (set scene.build-context.get-text-ssbo-draw-list (fn [_ctx] :surface-text-ssbo-draw-list))
  (set scene.build-context.get-mesh-batches (fn [_ctx] :surface-mesh-batches))
  (set scene.build-context.get-instanced-color-mesh-batches (fn [_ctx] :surface-instanced-color-mesh-batches))

  ;; Sentinels: sandbox slot context
  (set sandbox-slot.ctx.get-triangle-batches (fn [_ctx] :sandbox-triangle-batches))
  (set sandbox-slot.ctx.get-quad-draw-list (fn [_ctx] :sandbox-quad-draw-list))
  (set sandbox-slot.ctx.get-text-ssbo-draw-list (fn [_ctx] :sandbox-text-ssbo-draw-list))
  (set sandbox-slot.ctx.get-mesh-batches (fn [_ctx] :sandbox-mesh-batches))
  (set sandbox-slot.ctx.get-instanced-color-mesh-batches (fn [_ctx] :sandbox-instanced-color-mesh-batches))

  ;; Sentinels: graph slot context
  (set graph-slot.ctx.get-triangle-batches (fn [_ctx] :graph-triangle-batches))
  (set graph-slot.ctx.get-quad-draw-list (fn [_ctx] :graph-quad-draw-list))
  (set graph-slot.ctx.get-text-ssbo-draw-list (fn [_ctx] :graph-text-ssbo-draw-list))
  (set graph-slot.ctx.get-mesh-batches (fn [_ctx] :graph-mesh-batches))
  (set graph-slot.ctx.get-instanced-color-mesh-batches (fn [_ctx] :graph-instanced-color-mesh-batches))

  ;; Before activation: surface sentinels
  (assert (= (scene:get-triangle-batches) :surface-triangle-batches)
          "Inactive: triangle batches route to surface")
  (assert (= (scene:get-quad-draw-list) :surface-quad-draw-list)
          "Inactive: quad draw list routes to surface")
  (assert (= (scene:get-text-ssbo-draw-list) :surface-text-ssbo-draw-list)
          "Inactive: text SSBO draw list routes to surface")
  (assert (= (scene:get-mesh-batches) :surface-mesh-batches)
          "Inactive: mesh batches route to surface")
  (assert (= (scene:get-instanced-color-mesh-batches) :surface-instanced-color-mesh-batches)
          "Inactive: instanced color mesh batches route to surface")

  ;; Activate sandbox: sandbox sentinels
  (scene:activate-activity-slot "sandbox")
  (assert (= (scene:get-triangle-batches) :sandbox-triangle-batches)
          "Sandbox active: triangle batches route to sandbox slot")
  (assert (= (scene:get-quad-draw-list) :sandbox-quad-draw-list)
          "Sandbox active: quad draw list routes to sandbox slot")
  (assert (= (scene:get-text-ssbo-draw-list) :sandbox-text-ssbo-draw-list)
          "Sandbox active: text SSBO draw list routes to sandbox slot")
  (assert (= (scene:get-mesh-batches) :sandbox-mesh-batches)
          "Sandbox active: mesh batches route to sandbox slot")
  (assert (= (scene:get-instanced-color-mesh-batches) :sandbox-instanced-color-mesh-batches)
          "Sandbox active: instanced color mesh batches route to sandbox slot")

  ;; Switch to graph: graph sentinels
  (scene:activate-activity-slot "graph")
  (assert (= (scene:get-triangle-batches) :graph-triangle-batches)
          "Graph active: triangle batches route to graph slot")
  (assert (= (scene:get-quad-draw-list) :graph-quad-draw-list)
          "Graph active: quad draw list routes to graph slot")
  (assert (= (scene:get-text-ssbo-draw-list) :graph-text-ssbo-draw-list)
          "Graph active: text SSBO draw list routes to graph slot")
  (assert (= (scene:get-mesh-batches) :graph-mesh-batches)
          "Graph active: mesh batches route to graph slot")
  (assert (= (scene:get-instanced-color-mesh-batches) :graph-instanced-color-mesh-batches)
          "Graph active: instanced color mesh batches route to graph slot")

  ;; Deactivate: fall back to surface sentinels
  (scene:deactivate-activity-slot "graph")
  (assert (= (scene:get-triangle-batches) :surface-triangle-batches)
          "Deactivated: triangle batches fall back to surface")
  (assert (= (scene:get-quad-draw-list) :surface-quad-draw-list)
          "Deactivated: quad draw list falls back to surface")
  (assert (= (scene:get-text-ssbo-draw-list) :surface-text-ssbo-draw-list)
          "Deactivated: text SSBO draw list falls back to surface")
  (assert (= (scene:get-mesh-batches) :surface-mesh-batches)
          "Deactivated: mesh batches fall back to surface")
  (assert (= (scene:get-instanced-color-mesh-batches) :surface-instanced-color-mesh-batches)
          "Deactivated: instanced color mesh batches fall back to surface")

  (drop-fixture fixture))

(fn active-slot-layout-root-updates-during-update []
  ;; R1-1: Scene.update must update the active slot layout root
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local slot (scene:activate-activity-slot "sandbox"))
  (var updated? false)
  (local original-update slot.layout-root.update)
  (set slot.layout-root.update (fn [self]
                                 (set updated? true)
                                 (when original-update
                                   (original-update self))))
  (scene:update)
  (assert updated?
          "Scene.update should update the active slot layout root")
  (drop-fixture fixture))

(fn inactive-slot-layout-root-not-updated []
  ;; R1-1: Inactive slot layout roots must not be updated
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local sandbox-slot (scene:activate-activity-slot "sandbox"))
  (scene:activate-activity-slot "graph")
  (var sandbox-updated? false)
  (local original-update sandbox-slot.layout-root.update)
  (set sandbox-slot.layout-root.update (fn [self]
                                         (set sandbox-updated? true)
                                         (when original-update
                                           (original-update self))))
  (scene:update)
  (assert (not sandbox-updated?)
          "Scene.update must not update inactive slot layout roots")
  (drop-fixture fixture))

(fn slot-focus-scope-follows-activation []
  ;; R1-2: Per-slot focus scope attaches/detaches with activation
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local focus-manager (FocusManager {:root-name "test-scene-focus"}))
  (local scene (Scene {:camera camera
                       :focus-manager focus-manager
                       :focus-scope-name "test-scene-focus"}))
  (local slot (scene:ensure-activity-slot "sandbox"))
  (assert slot.focus-scope
          "Scene activity slot should own a focus scope")
  (assert (= slot.focus-scope.parent nil)
          "Inactive activity slot focus scope should be detached")
  (scene:activate-activity-slot "sandbox")
  (assert (= slot.focus-scope.parent scene.focus-scope)
          "Active activity slot focus scope should attach to Scene focus scope")
  (scene:deactivate-activity-slot "sandbox")
  (assert (= slot.focus-scope.parent nil)
          "Deactivated activity slot focus scope should detach from traversal")
  (scene:drop)
  (camera:drop)
  (focus-manager:drop))

(fn scene-drop-disposes-retained-slots []
  ;; R1-3: Scene.drop must dispose all retained activity slots
  (local fixture (make-scene))
  (local scene fixture.scene)
  (var sandbox-dropped? false)
  (var graph-dropped? false)
  (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
  (local graph-slot (scene:ensure-activity-slot "graph"))
  (set sandbox-slot.root {:drop (fn [_] (set sandbox-dropped? true))})
  (set graph-slot.root {:drop (fn [_] (set graph-dropped? true))})
  ;; Drop the scene (which should cascade to all slots)
  (scene:drop)
  (assert sandbox-dropped?
          "Scene.drop should drop sandbox slot root")
  (assert graph-dropped?
          "Scene.drop should drop graph slot root")
  (fixture.camera:drop))

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
(table.insert tests {:name "Scene active slot batch accessors route correctly"
                     :fn active-slot-batch-accessors-route-correctly})
(table.insert tests {:name "Scene active slot layout root updates during update"
                     :fn active-slot-layout-root-updates-during-update})
(table.insert tests {:name "Scene inactive slot layout root not updated"
                     :fn inactive-slot-layout-root-not-updated})
(table.insert tests {:name "Scene slot focus scope follows activation"
                     :fn slot-focus-scope-follows-activation})
(table.insert tests {:name "Scene drop disposes retained slots"
                     :fn scene-drop-disposes-retained-slots})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-activity-slots"
                       :tests tests})))

{:name "scene-activity-slots"
 :tests tests
 :main main}
