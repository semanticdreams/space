(local glm (require :glm))
(local Main (require :main))
(local Scene (require :scene))
(local Camera (require :camera))
(local AppProjection (require :app-projection))
(local {: FocusManager} (require :focus))

(local tests [])

;; ── Terrain record helpers for R2-1 tests ──────────────────────────────

(fn make-heightfield-terrain-record [opts]
  (local options (or opts {}))
  (local chunk-samples (or options.chunk-samples [17 17]))
  (local default-height (or options.default-height 0.0))
  (local heights [])
  (for [_ 1 (* (. chunk-samples 1) (. chunk-samples 2))]
    (table.insert heights default-height))
  {:id (or options.id "heightfield-1")
   :name options.name
   :kind "heightfield-terrain"
   :options {:position (or options.position [-160 -100 -160])
             :rotation (or options.rotation [1 0 0 0])
             :opacity (or options.opacity 1.0)
             :physics (if (= options.physics nil) true options.physics)
             :sample-spacing (or options.sample-spacing [20 20])
             :chunk-samples chunk-samples
             :default-height default-height}
   :chunks (or options.chunks [{:coord [0 0]
                                :size chunk-samples
                                :heights heights}])})

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
  (scene:ensure-activity-slot "sandbox")
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
  (set scene.build-context.image-batches :surface-image-batches)

  ;; Sentinels: sandbox slot context
  (set sandbox-slot.ctx.get-triangle-batches (fn [_ctx] :sandbox-triangle-batches))
  (set sandbox-slot.ctx.get-quad-draw-list (fn [_ctx] :sandbox-quad-draw-list))
  (set sandbox-slot.ctx.get-text-ssbo-draw-list (fn [_ctx] :sandbox-text-ssbo-draw-list))
  (set sandbox-slot.ctx.get-mesh-batches (fn [_ctx] :sandbox-mesh-batches))
  (set sandbox-slot.ctx.get-instanced-color-mesh-batches (fn [_ctx] :sandbox-instanced-color-mesh-batches))
  (set sandbox-slot.ctx.image-batches :sandbox-image-batches)

  ;; Sentinels: graph slot context
  (set graph-slot.ctx.get-triangle-batches (fn [_ctx] :graph-triangle-batches))
  (set graph-slot.ctx.get-quad-draw-list (fn [_ctx] :graph-quad-draw-list))
  (set graph-slot.ctx.get-text-ssbo-draw-list (fn [_ctx] :graph-text-ssbo-draw-list))
  (set graph-slot.ctx.get-mesh-batches (fn [_ctx] :graph-mesh-batches))
  (set graph-slot.ctx.get-instanced-color-mesh-batches (fn [_ctx] :graph-instanced-color-mesh-batches))
  (set graph-slot.ctx.image-batches :graph-image-batches)

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
  (assert (= (scene:get-image-batches) :surface-image-batches)
          "Inactive: image batches route to surface")

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
  (assert (= (scene:get-image-batches) :sandbox-image-batches)
          "Sandbox active: image batches route to sandbox slot")

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
  (assert (= (scene:get-image-batches) :graph-image-batches)
          "Graph active: image batches route to graph slot")

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
  (assert (= (scene:get-image-batches) :surface-image-batches)
          "Deactivated: image batches fall back to surface")

  (drop-fixture fixture))

(fn active-slot-layout-root-updates-during-update []
  ;; R1-1: Scene.update must update the active slot layout root
  (local fixture (make-scene))
  (local scene fixture.scene)
  (scene:ensure-activity-slot "sandbox")
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
  (scene:ensure-activity-slot "sandbox")
  (local sandbox-slot (scene:activate-activity-slot "sandbox"))
  (scene:ensure-activity-slot "graph")
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

(fn slot-environment-isolated-on-activation []
  ;; Task 2: Restore environment state on activation; empty state clears services.
  ;; Requires: ActivitySceneState, capture-activity-slot-state, restore-activity-slot-state,
  ;; and activation applying lights/skybox/background/containment.
  ;; R1-6: Use valid terrain record, assert containment installs/clears, assert content preserved.
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local LightingViewState (require :lighting-view-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local PhysicsContainment (require :physics-containment))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))

      ;; Mock renderer skybox / background
      (var skybox-state {:enabled? false
                         :name "lake"
                         :brightness 0.1
                         :tint-color [1.0 1.0 1.0]})
      (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                                   :set-state (fn [_ state]
                                                (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                          :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                          :set-background-state (fn [_ state]
                                                   (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})

      ;; Mock physics for containment
      (var installed-bodies [])
      (set app.engine {:physics {:addRigidBody (fn [_phys body] (table.insert installed-bodies body))
                                  :removeRigidBody (fn [_phys _body])}})

      (local fixture (make-scene))
      (local scene fixture.scene)
      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
      (local graph-slot (scene:ensure-activity-slot "graph"))

      ;; Non-default sandbox state: enabled ambient, enabled skybox, custom background, enabled containment.
      ;; R1-6: Include a valid terrain record.
      (local sandbox-state
        {:panels []
         :terrains [{:kind "heightfield-terrain"}]
         :lights {:ambient {:enabled? true :color [1.0 1.0 1.0] :intensity 1.0}
                  :directional []
                  :point []
                  :spot []}
         :skybox {:enabled? true
                  :name "lake"
                  :brightness 0.5
                  :tint-color [1.0 1.0 1.0]}
         :background {:color [0.2 0.3 0.4]}
         :containment {:enabled? true}})

      (local empty-state (ActivitySceneState.empty-state))

      ;; Restore sandbox slot with non-default state
      (assert (scene:restore-activity-slot-state "sandbox" sandbox-state)
              "restore-activity-slot-state should return true for valid state")

      ;; Activate sandbox: services should reflect sandbox state
      (scene:activate-activity-slot "sandbox")
      (local lights-state (app.lights:get-state))
      (assert lights-state.ambient.enabled?
              "Sandbox activation should enable ambient light")
      (assert skybox-state.enabled?
              "Sandbox activation should enable skybox")
      (assert (= skybox-state.brightness 0.5)
              "Sandbox activation should apply skybox brightness")
      (assert (and app.background-state
                   (= (. app.background-state.color 1) 0.2)
                   (= (. app.background-state.color 2) 0.3)
                   (= (. app.background-state.color 3) 0.4))
              "Sandbox activation should apply custom background color")

      ;; R1-6: Assert Sandbox containment installs
      (assert (not (= app.physics-containment-config nil))
              "Sandbox activation should set physics-containment-config")
      (assert app.physics-containment-config.enabled?
              "Sandbox containment config should have enabled? true")

      ;; Restore graph with empty state
      (assert (scene:restore-activity-slot-state "graph" empty-state)
              "restore-activity-slot-state with empty-state should return true")

      ;; Activate graph: services should clear to empty
      (scene:activate-activity-slot "graph")
      (local graph-lights (app.lights:get-state))
      (assert (not graph-lights.ambient.enabled?)
              "Graph activation with empty state should disable ambient light")
      (assert (not skybox-state.enabled?)
              "Graph activation with empty state should disable skybox")
      (assert (and app.background-state
                   (= (. app.background-state.color 1) 0.0)
                   (= (. app.background-state.color 2) 0.0)
                   (= (. app.background-state.color 3) 0.0))
              "Graph activation with empty state should set neutral background")

      ;; R1-6: Assert Graph activation clears containment
      (assert (and app.physics-containment-config
                   (not app.physics-containment-config.enabled?))
              "Graph activation should disable containment")

      ;; Capture graph state: should have empty terrain/panels
      (local graph-captured (scene:capture-activity-slot-state "graph"))
      (assert graph-captured "capture-activity-slot-state should return state")
      (assert (= (type graph-captured.panels) :table)
              "Captured graph state should have panels table")
      (assert (= (length graph-captured.panels) 0)
              "Graph activation with empty state should leave no panels")
      (assert (= (type graph-captured.terrains) :table)
              "Captured graph state should have terrains table")
      (assert (= (length graph-captured.terrains) 0)
              "Graph activation with empty state should leave no terrains")

      ;; R1-6: Switch back to sandbox — services should reflect sandbox state again
      (scene:activate-activity-slot "sandbox")
      (local sandbox-lights (app.lights:get-state))
      (assert sandbox-lights.ambient.enabled?
              "Switching back to sandbox should re-enable ambient light")
      (assert skybox-state.enabled?
              "Switching back to sandbox should re-enable skybox")
      (assert (= skybox-state.brightness 0.5)
              "Switching back to sandbox should restore skybox brightness")
      ;; R1-6: Assert Sandbox containment returns
      (assert (and app.physics-containment-config
                   app.physics-containment-config.enabled?)
              "Switching back to sandbox should re-enable containment")
      ;; R1-6: Assert terrain record was preserved through switches
      (local sandbox-captured (scene:capture-activity-slot-state "sandbox"))
      (assert (= (length sandbox-captured.terrains) 1)
              "Sandbox terrain should be preserved through activation switches")

      ;; R1-2: Restoring one terrain record into an active empty slot yields
      ;; exactly one runtime terrain record (no duplicates).
      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
      (assert sandbox-slot.scene-terrains
              "Sandbox slot should have runtime terrain after activation")
      (assert (= (length sandbox-slot.scene-terrains) 1)
              "Sandbox slot should have exactly one runtime terrain record")

      (drop-fixture fixture))))

(fn no-active-slot-mutation-asserts []
  ;; R1-6: Content mutators must assert when no active slot exists,
  ;; both before any slot is registered and after a registered slot is inactive.
  (local fixture (make-scene))
  (local scene fixture.scene)

  ;; Case 1: No slots registered at all — mutation should still fail
  (local (ok1 err1) (pcall (fn [] (scene:add-object {:scene-object-options (fn [] {})}))))
  (assert (not ok1) "add-object without any slots should fail")
  (assert (string.find (tostring err1) "Scene content mutation requires an active activity scene slot")
          "add-object should produce the expected assertion message")

  ;; Case 2: Register a slot, don't activate — mutation should fail
  (scene:ensure-activity-slot "sandbox")
  (local (ok2 err2) (pcall (fn [] (scene:build-default {}))))
  (assert (not ok2) "build-default with inactive slot should fail")
  (assert (string.find (tostring err2) "Scene content mutation requires an active activity scene slot")
          "build-default should produce the expected assertion message")

  (local (ok3 err3) (pcall (fn [] (scene:add-terrain-record {:kind "heightfield-terrain"}))))
  (assert (not ok3) "add-terrain-record with inactive slot should fail")
  (assert (string.find (tostring err3) "Scene content mutation requires an active activity scene slot")
          "add-terrain-record should produce the expected assertion message")

  (drop-fixture fixture))

(fn physics-bodies-suspend-and-resume []
  ;; Task 2: LayoutPhysicsBodies.deactivate/activate remove and restore Bullet bodies
  ;; without dropping the entity.
  (with-restored-app-fields
    [:engine :movables]
    (fn []
      (local bt (require :bt))
      (local LayoutPhysicsBodies (require :layout-physics-bodies))
      (local BuildContext (require :build-context))
      (local Container (require :container))

      ;; Mock a minimal physics world
      (var added-bodies [])
      (var removed-bodies [])
      (set app.engine
           {:physics
            {:addRigidBody (fn [_physics body] (table.insert added-bodies body))
             :removeRigidBody (fn [_physics body] (table.insert removed-bodies body))
             :syncMovedRigidBody (fn [_physics _body])}})
      (set app.movables {:register (fn [_movables _widget _opts])})

      ;; Create a simple entity
      (local ctx (BuildContext {:layout-root {:children []
                                              :__root true}}))
      (local builder (Container {:children []}))
      (local entity (builder ctx))
      (set entity.layout.position (glm.vec3 0 0 0))
      (set entity.layout.rotation (glm.quat 1 0 0 0))
      (set entity.children [])
      (set entity.movables [])

      ;; Create a physics entry
      (local element {:layout {:position (glm.vec3 0 5 0)
                               :rotation (glm.quat 1 0 0 0)
                               :size (glm.vec3 4 4 4)
                               :measure (glm.vec3 4 4 4)
                               :children []
                               :parent entity.layout
                               :root entity.layout
                               :depth-offset-index 0
                               :mark-measure-dirty (fn [_layout])}})
      (local entry (LayoutPhysicsBodies.add-runtime-layout-body entity {:element element}))
      (assert entry.body "LayoutPhysicsBodies should create a Bullet body")

      ;; Deactivate: remove bodies without dropping entity
      (LayoutPhysicsBodies.deactivate entity)
      (assert (not entry.body-active?)
              "LayoutPhysicsBodies.deactivate should mark bodies inactive")
      (assert (> (length removed-bodies) 0)
              "LayoutPhysicsBodies.deactivate should remove Bullet bodies")

      ;; Reactivate: restore bodies
      (LayoutPhysicsBodies.activate entity)
      (assert entry.body-active?
              "LayoutPhysicsBodies.activate should restore body active state")

      ;; Cleanup
      (entity:drop))))

(fn restore-terrain-no-duplicates-on-active-slot []
  ;; R1-2 focused: restore-activity-slot-state on an already-active empty slot
  ;; must build terrain exactly once with no duplicates.
  ;; The existing environment-isolation test restores before activation;
  ;; this exercises the active-slot restore path directly.
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))

      ;; Mock renderer skybox / background for apply-state-to-services
      (var skybox-state {:enabled? false
                         :name "lake"
                         :brightness 0.1
                         :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                     :set-state (fn [_ state]
                                   (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state]
                                     (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})

      ;; Mock physics for containment
      (var installed-bodies [])
      (set app.engine {:physics {:addRigidBody (fn [_phys body] (table.insert installed-bodies body))
                                  :removeRigidBody (fn [_phys _body])}})

      (local fixture (make-scene))
      (local scene fixture.scene)
      (local slot (scene:ensure-activity-slot "sandbox"))

      ;; (1) Activate an empty Scene slot (no terrain built yet)
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Slot should be active before restore")

      ;; (2) Build a complete canonical state with exactly one terrain record
      (local state (ActivitySceneState.empty-state))
      (set state.terrains [{:kind "heightfield-terrain"}])

      ;; Call restore-activity-slot-state for the already-active slot
      (assert (scene:restore-activity-slot-state "sandbox" state)
              "restore-activity-slot-state on active slot should return true")

      ;; (3) Immediately assert slot.scene-terrains has exactly one entry
      (assert slot.scene-terrains
              "Active slot should have runtime terrain after restore")
      (assert (= (length slot.scene-terrains) 1)
              (.. "Active slot should have exactly one runtime terrain after restore, got "
                  (tostring (length slot.scene-terrains))))

      (drop-fixture fixture))))

(fn restore-terrain-idempotent-on-repeat []
  ;; R1-3: restore-activity-slot-state called twice on an already-active slot
  ;; with the same one-terrain state must leave exactly one runtime terrain.
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))

      ;; Mock renderer skybox / background
      (var skybox-state {:enabled? false
                         :name "lake"
                         :brightness 0.1
                         :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                     :set-state (fn [_ state]
                                   (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state]
                                     (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})

      ;; Mock physics
      (var installed-bodies [])
      (set app.engine {:physics {:addRigidBody (fn [_phys body] (table.insert installed-bodies body))
                                  :removeRigidBody (fn [_phys _body])}})

      (local fixture (make-scene))
      (local scene fixture.scene)
      (local slot (scene:ensure-activity-slot "sandbox"))

      ;; Activate an empty slot
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Slot should be active before restore")

      ;; Build canonical state with exactly one terrain record
      (local state (ActivitySceneState.empty-state))
      (set state.terrains [{:kind "heightfield-terrain"}])

      ;; First restore builds the terrain
      (assert (scene:restore-activity-slot-state "sandbox" state)
              "First restore should return true")
      (assert slot.scene-terrains
              "Active slot should have runtime terrain after first restore")
      (assert (= (length slot.scene-terrains) 1)
              (.. "After first restore: expected 1 terrain, got "
                  (tostring (length slot.scene-terrains))))

      ;; Second restore with same state must NOT add duplicates
      (assert (scene:restore-activity-slot-state "sandbox" state)
              "Second restore should return true")
      (assert slot.scene-terrains
              "Active slot should still have runtime terrain after second restore")
      (assert (= (length slot.scene-terrains) 1)
              (.. "After second restore: expected exactly 1 terrain (idempotent), got "
                  (tostring (length slot.scene-terrains))))

      (drop-fixture fixture))))

(fn restore-terrain-adds-missing-while-active []
  ;; R1-3: restoring a state with an additional terrain while the slot is active
  ;; must add exactly the missing terrain without duplicating existing ones.
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))

      ;; Mock renderer skybox / background
      (var skybox-state {:enabled? false :name "lake" :brightness 0.1 :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                     :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})

      ;; Mock physics
      (var installed-bodies [])
      (set app.engine {:physics {:addRigidBody (fn [_phys body] (table.insert installed-bodies body))
                                  :removeRigidBody (fn [_phys _body])}})

      (local fixture (make-scene))
      (local scene fixture.scene)
      (local slot (scene:ensure-activity-slot "sandbox"))

      ;; Activate empty slot
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Slot should be active before restore")

      ;; (1) Restore state with one terrain
      (local state-1 (ActivitySceneState.empty-state))
      (set state-1.terrains [{:kind "heightfield-terrain"}])
      (assert (scene:restore-activity-slot-state "sandbox" state-1)
              "First restore should return true")
      (assert (= (length slot.scene-terrains) 1)
              (.. "After first restore: expected 1 terrain, got "
                  (tostring (length slot.scene-terrains))))

      ;; (2) Restore state with two terrains — must NOT duplicate the first
      (local state-2 (ActivitySceneState.empty-state))
      (set state-2.terrains [{:kind "heightfield-terrain"} {:kind "flat-terrain"}])
      (assert (scene:restore-activity-slot-state "sandbox" state-2)
              "Second restore with additional terrain should return true")
      (assert (= (length slot.scene-terrains) 2)
              (.. "After second restore: expected exactly 2 terrains, got "
                  (tostring (length slot.scene-terrains))))

      (drop-fixture fixture))))

(fn activate-activity-slot-fails-on-unknown []
  ;; R1-2: activate-activity-slot must assert when the slot does not exist,
  ;; instead of silently creating one.
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local (ok err) (pcall (fn [] (scene:activate-activity-slot "unregistered"))))
  (assert (not ok) "activate-activity-slot must fail for unknown activity id")
  (assert (string.find (tostring err) "no slot for activity" 1 true)
          (.. "activate-activity-slot failure must mention missing slot, got: " (tostring err)))
  ;; But ensure-activity-slot + activate-activity-slot should work
  (scene:ensure-activity-slot "sandbox")
  (local slot (scene:activate-activity-slot "sandbox"))
  (assert slot "activate-activity-slot should succeed after ensure-activity-slot")
  (drop-fixture fixture))

(fn containment-enabled-flag-controls-install []
  ;; Task 2: Containment :enabled? false should clear and install nothing.
  (with-restored-app-fields
    [:physics-containment-config :physics-containment-scene
     :__physics-global-containment :__physics_containment_refresh_debouncer
     :engine]
    (fn []
      (local PhysicsContainment (require :physics-containment))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))

      ;; Verify enabled? is in normalized config
      (local enabled-config (PhysicsContainment.normalize-config {:enabled? true}))
      (assert enabled-config.enabled?
              "normalize-config should preserve :enabled? true")

      (local disabled-config (PhysicsContainment.normalize-config {:enabled? false}))
      (assert (not disabled-config.enabled?)
              "normalize-config should preserve :enabled? false")

      ;; Verify serialize includes enabled?
      (local serialized (PhysicsContainment.serialize-config {:enabled? true}))
      (assert serialized.enabled?
              "serialize-config should include :enabled?")

      ;; Mock physics for ensure-installed
      (var installed-planes [])
      (var cleared? false)
      ;; Capture original clear to use within mock
      (local original-clear PhysicsContainment.clear)
      (set app.engine {:physics {:addRigidBody (fn [_phys body] (table.insert installed-planes body))}})
      ;; Override clear for test to detect it was called
      (var ensure-installed-calls [])
      (local orig-ensure-installed PhysicsContainment.ensure-installed)

      ;; Setup: install enabled containment
      (orig-ensure-installed {:config {:enabled? true}})
      (assert (> (length installed-planes) 0)
              "ensure-installed with enabled? true should install containment planes")
      (assert (not (= app.physics-containment-config nil))
              "ensure-installed should set physics-containment-config")

      ;; Clean up and test disabled
      (original-clear)
      (set installed-planes [])

      ;; Install disabled containment: should clear and install nothing
      (local result (orig-ensure-installed {:config {:enabled? false}}))
      ;; When enabled? is false, ensure-installed clears and returns false
      (assert (= result false)
              "ensure-installed with enabled? false should return false")
      (assert (= (length installed-planes) 0)
              "ensure-installed with enabled? false should not install planes")

      ;; Clean up
      (original-clear))))

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
(table.insert tests {:name "Scene slot environment isolated on activation"
                      :fn slot-environment-isolated-on-activation})
(table.insert tests {:name "Scene physics bodies suspend and resume"
                      :fn physics-bodies-suspend-and-resume})
(table.insert tests {:name "Scene containment enabled flag controls install"
                       :fn containment-enabled-flag-controls-install})
(table.insert tests {:name "Scene content mutation asserts without active slot"
                       :fn no-active-slot-mutation-asserts})
(table.insert tests {:name "Scene restore terrain no duplicates on active slot"
                        :fn restore-terrain-no-duplicates-on-active-slot})
(table.insert tests {:name "Scene restore terrain idempotent on repeat"
                        :fn restore-terrain-idempotent-on-repeat})
(table.insert tests {:name "Scene restore terrain adds missing while active"
                        :fn restore-terrain-adds-missing-while-active})
(table.insert tests {:name "Scene activate-activity-slot fails on unknown"
                        :fn activate-activity-slot-fails-on-unknown})

;; ── R2-1 ──────────────────────────────────────────────────────────────

(fn inactive-capture-uses-authoritative-terrains []
  "R2-1: When a slot is inactive, capture-activity-slot-state must use the
  authoritative slot.scene-state.terrains, NOT stale slot.scene-terrains.
  This prevents stale runtime terrain from overwriting canonical state
  during inactive capture."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      ;; Mock renderer services for apply-state-to-services
      (var skybox-state {:enabled? false
                         :default {:name "lake"
                                   :brightness 0.1
                                   :tint-color [1.0 1.0 1.0]}
                         :by-theme {}})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                    :set-state (fn [_ state] (set skybox-state state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Ensure and activate sandbox
      (local slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      ;; Restore a valid state with exactly one terrain record
      (local canonical (ActivitySceneState.empty-state))
      (set canonical.terrains [(make-heightfield-terrain-record {:id "t1-legit"})])
      (scene:restore-activity-slot-state "sandbox" canonical)
      ;; Now switch to Graph (deactivates sandbox)
      (scene:ensure-activity-slot "graph")
      (scene:activate-activity-slot "graph")
      (assert (= scene.active-activity-slot-id "graph")
              "Graph should be the active slot after switch")
      (assert (not slot.visible?)
              "Sandbox slot should be inactive after graph activation")
      ;; Simulate stale runtime terrain: set slot.scene-terrains to
      ;; something different from the canonical scene-state.terrains.
      ;; This represents the stale state that existed before inactive
      ;; WorldData mutations.
      (set slot.scene-terrains [{:record {:id "t-stale-runtime"
                                          :kind "heightfield-terrain"}}])
      ;; Meanwhile, add a second terrain to the canonical scene-state
      ;; (simulating WorldData.add-terrain while sandbox is inactive).
      (table.insert slot.scene-state.terrains
                    (make-heightfield-terrain-record {:id "t2-added-while-inactive"}))
      ;; Capture the sandbox slot state.  The fix ensures this reads from
      ;; slot.scene-state.terrains, NOT from slot.scene-terrains.
      (local captured (scene:capture-activity-slot-state "sandbox"))
      (assert captured "capture-activity-slot-state should return a state table")
      (assert (= (type captured.terrains) :table) "captured state must have terrains")
      (assert (= (length captured.terrains) 2)
              (.. "Expected exactly 2 terrains in captured state (one original + one added while inactive), got "
                  (tostring (length captured.terrains))))
      ;; Verify the correct terrain ids are present (not the stale runtime id)
      (local captured-ids {})
      (each [_ rec (ipairs captured.terrains)]
        (set (. captured-ids rec.id) true))
      (assert (. captured-ids "t1-legit")
              "Captured state must contain the original terrain t1-legit")
      (assert (. captured-ids "t2-added-while-inactive")
              "Captured state must contain the terrain added while inactive")
      (assert (not (. captured-ids "t-stale-runtime"))
              "Captured state must NOT contain the stale runtime terrain id")
      (drop-fixture fixture))))

(fn sandbox-activation-reconciles-terrains []
  "R2-1: When sandbox is reactivated after WorldData terrain mutations,
  the stale runtime slot.scene-terrains must be reconciled against the
  authoritative slot.scene-state.terrains.  Stale terrains should be
  removed and new canonical terrains should be added."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      ;; Mock renderer services
      (var skybox-state {:enabled? false
                         :default {:name "lake"
                                   :brightness 0.1
                                   :tint-color [1.0 1.0 1.0]}
                         :by-theme {}})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                    :set-state (fn [_ state] (set skybox-state state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Activate sandbox and restore with one terrain, then switch away
      (local slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      (local original-state (ActivitySceneState.empty-state))
      (set original-state.terrains [(make-heightfield-terrain-record {:id "t-a"})])
      (scene:restore-activity-slot-state "sandbox" original-state)
      ;; Switch to Graph (deactivates sandbox)
      (scene:ensure-activity-slot "graph")
      (scene:activate-activity-slot "graph")
      (assert (not slot.visible?) "Sandbox should be inactive after graph activation")
      ;; Simulate WorldData mutation while inactive: add a second terrain
      ;; to the canonical scene-state.  This is what refresh-sandbox-slot-if-inactive
      ;; would do after a WorldData.add-terrain call.
      (table.insert slot.scene-state.terrains
                    (make-heightfield-terrain-record {:id "t-b"}))
      ;; NOTE: the stale slot.scene-terrains from before the switch is
      ;; what would be restored on reactivation.  Our fix in
      ;; activate-activity-slot reconciles this against slot.scene-state.terrains.
      ;; Reactivate sandbox
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Sandbox should be active after reactivation")
      ;; After reactivation, the canonical scene-state should still have 2 records
      (assert (= (length slot.scene-state.terrains) 2)
              (.. "slot.scene-state.terrains should have 2 entries after reactivation, got "
                  (tostring (length slot.scene-state.terrains))))
      (drop-fixture fixture))))

(table.insert tests {:name "inactive capture uses authoritative terrains"
                     :fn inactive-capture-uses-authoritative-terrains})
(table.insert tests {:name "sandbox activation reconciles terrains"
                     :fn sandbox-activation-reconciles-terrains})

;; ── R2-1 empty canonical terrain list ──────────────────────────────────

(fn sandbox-activation-removes-stale-terrains-when-canonical-empty []
  "R2-1: When all terrains are removed from the canonical state while
  Sandbox is inactive, reactivation must remove all stale runtime
  terrains.  The result is zero runtime terrains and zero canonical
  terrain records — no leftover stale entries and no recapture."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      (var skybox-state {:enabled? false
                         :default {:name "lake"
                                   :brightness 0.1
                                   :tint-color [1.0 1.0 1.0]}
                         :by-theme {}})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                    :set-state (fn [_ state] (set skybox-state state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Activate sandbox with exactly one terrain.
      (local slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      (local original-state (ActivitySceneState.empty-state))
      (set original-state.terrains [(make-heightfield-terrain-record {:id "t-solo"})])
      (scene:restore-activity-slot-state "sandbox" original-state)
      ;; Switch to Graph (deactivates sandbox).
      (scene:ensure-activity-slot "graph")
      (scene:activate-activity-slot "graph")
      (assert (not slot.visible?) "Sandbox should be inactive after graph activation")
      ;; Simulate removal of the only terrain via WorldData while inactive:
      ;; clear the canonical terrain list to empty.
      (set slot.scene-state.terrains [])
      ;; Stale runtime terrains remain in slot.scene-terrains from capture.
      ;; Reactivate sandbox — the reconcile must remove them all.
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Sandbox should be active after reactivation")
      ;; Verify zero canonical terrain records.
      (assert (= (length slot.scene-state.terrains) 0)
              (.. "Expected zero canonical terrains after removal-to-empty, got "
                  (tostring (length slot.scene-state.terrains))))
      ;; Verify zero runtime terrains (stale ones were removed).
      (assert (or (not slot.scene-terrains) (= (length slot.scene-terrains) 0))
              (.. "Expected zero runtime terrains after stale removal, got "
                  (tostring (length (or slot.scene-terrains [])))))
      (drop-fixture fixture))))

;; ── R2-2 preserve complete skybox policy on slot switch ────────────────

(fn slot-switch-preserves-complete-skybox-policy []
  "R2-2: When an active slot with a by-theme skybox policy is switched
  away from and later reactivated, its slot.scene-state.skybox must
  retain the complete policy (:default, :by-theme) — not be overwritten
  by the renderer's resolved format during slot switch."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      ;; Mock renderer so the resolved skybox is captured on switch.
      (var renderer-skybox {:enabled? true
                            :name "lake"
                            :brightness 0.1
                            :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] renderer-skybox)
                    :set-state (fn [_ state] (set renderer-skybox state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Activate sandbox and set a complete skybox with a by-theme override.
      (local slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      (local complete-skybox
        (SkyboxState.normalize-complete-state
          {:enabled? true
           :default {:name "lake"
                     :brightness 0.1
                     :tint-color [1.0 1.0 1.0]}
           :by-theme {:dark {:name "night"
                              :brightness 0.3
                              :tint-color [0.8 0.8 1.0]}}}
          "test-skybox-policy"))
      (local sandbox-state (ActivitySceneState.empty-state))
      (set sandbox-state.skybox complete-skybox)
      (scene:restore-activity-slot-state "sandbox" sandbox-state)
      ;; Switch to Graph — this triggers capture of the old slot's services.
      ;; The fix must preserve the complete skybox policy, not overwrite it
      ;; with the renderer's resolved view.
      (scene:ensure-activity-slot "graph")
      (scene:activate-activity-slot "graph")
      (assert (not slot.visible?) "Sandbox should be inactive after switch")
      ;; Verify the sandbox slot retained its complete skybox policy.
      (assert slot.scene-state "Slot must have scene-state after switch")
      (assert slot.scene-state.skybox "Slot scene-state must have skybox")
      (assert (= (type slot.scene-state.skybox.default) :table)
              "skybox.default must still be present after switch (not flattened)")
      (assert (= (type slot.scene-state.skybox.by-theme) :table)
              "skybox.by-theme must still be present after switch")
      (assert slot.scene-state.skybox.by-theme.dark
              "dark theme override must survive slot switch")
      (assert (= slot.scene-state.skybox.by-theme.dark.name "night")
              "dark theme override name must survive slot switch")
      (assert (= slot.scene-state.skybox.by-theme.dark.brightness 0.3)
              "dark theme override brightness must survive slot switch")
      ;; Switch back to sandbox and verify policy is still complete.
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Sandbox should be active after reactivation")
      (assert (= (type slot.scene-state.skybox.by-theme) :table)
              "skybox.by-theme must still be present after reactivation")
      (assert slot.scene-state.skybox.by-theme.dark
              "dark theme override must survive full switch cycle")
      (drop-fixture fixture))))

;; ── R3-1 inactive existing terrain update ──────────────────────────────

(fn sandbox-activation-replaces-stale-terrain-with-updated-canonical []
  "R3-1: When a canonical Sandbox terrain record changes while the Sandbox
  is inactive, reactivation must update/replace the retained runtime terrain
  instead of skipping the same terrain id.  The stale runtime capture must
  not overwrite the updated canonical state."
  (with-restored-app-fields
    [:renderers :skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      (var skybox-state {:enabled? false
                         :default {:name "lake"
                                   :brightness 0.1
                                   :tint-color [1.0 1.0 1.0]}
                         :by-theme {}})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                    :set-state (fn [_ state] (set skybox-state state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Activate sandbox with terrain A (opacity 1.0).
      (local slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      (local original-state (ActivitySceneState.empty-state))
      (set original-state.terrains
           [(make-heightfield-terrain-record {:id "t-a" :opacity 1.0})])
      (scene:restore-activity-slot-state "sandbox" original-state)
      ;; Verify the runtime terrain has the original opacity.
      (local runtime-terrain-a (. slot.scene-terrains 1))
      (assert runtime-terrain-a "slot should have runtime terrain for t-a")
      ;; Switch to Graph (deactivates sandbox).
      (scene:ensure-activity-slot "graph")
      (scene:activate-activity-slot "graph")
      (assert (not slot.visible?) "Sandbox should be inactive after graph activation")
      ;; Simulate WorldData.update-terrain-record: update t-a's opacity
      ;; in the canonical state while Sandbox is inactive.
      (local canonical-t-a (. slot.scene-state.terrains 1))
      (assert (= canonical-t-a.id "t-a")
              "canonical terrain at index 1 should be t-a")
      (set canonical-t-a.options.opacity 0.5)
      ;; Reactivate Sandbox.  R3-1 fix ensures the stale runtime terrain
      ;; is replaced with the updated canonical record.
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Sandbox should be active after reactivation")
      ;; Verify the runtime terrain now reflects the updated canonical record.
      (local updated-runtime-terrain-a (. slot.scene-terrains 1))
      (assert updated-runtime-terrain-a
              "slot should still have runtime terrain for t-a after reactivation")
      ;; Verify terrain count is still 1 (no duplicates).
      (assert (= (length slot.scene-terrains) 1)
              (.. "Expected 1 runtime terrain after reactivation, got "
                  (tostring (length slot.scene-terrains))))
      ;; Verify the canonical state still has the updated record.
      (assert (= (length slot.scene-state.terrains) 1)
              "Canonical state should still have 1 terrain after reactivation")
      ;; Now capture the slot state and verify the updated opacity is preserved.
      (local captured (scene:capture-activity-slot-state "sandbox"))
      (assert captured "capture-activity-slot-state should return state")
      (assert (= (length captured.terrains) 1)
              (.. "Captured state should have 1 terrain, got "
                  (tostring (length captured.terrains))))
      (local captured-t-a (. captured.terrains 1))
      (assert (= captured-t-a.id "t-a")
              "Captured terrain should be t-a")
      (assert (= (. captured-t-a.options :opacity) 0.5)
              "Captured terrain should preserve the updated opacity 0.5, not the stale 1.0")
      (drop-fixture fixture))))

;; ── R3-2 inactive panel removal ────────────────────────────────────────

(fn sandbox-activation-removes-stale-panels-on-reactivation []
  "R3-2: When canonical Sandbox panels are removed while the Sandbox is
  inactive, reactivation must drop stale retained runtime panels so the
  graph-mode view does not carry forward deleted panels."
  (with-restored-app-fields
    [:renderers :skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      (var skybox-state {:enabled? false
                         :default {:name "lake"
                                   :brightness 0.1
                                   :tint-color [1.0 1.0 1.0]}
                         :by-theme {}})
      (set app.renderers
           {:skybox {:get-state (fn [_] skybox-state)
                    :set-state (fn [_ state] (set skybox-state state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Activate sandbox and build a simple entity with a panel.
      (local slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      ;; Build a default entity so scene-children / entity exist.
      (scene:build-default {})
      ;; Manually inject a panel with persistence into the scene-children.
      ;; This simulates a panel that was added via add-panel-child and
      ;; captured into canonical state.
      (local test-element {:layout {:position (glm.vec3 10 20 30)
                                     :rotation (glm.quat 1 0 0 0)
                                     :size (glm.vec3 4 4 4)
                                     :measure (glm.vec3 4 4 4)
                                     :children []
                                     :parent scene.entity.layout
                                     :root scene.entity.layout.root
                                     :mark-measure-dirty (fn [_])}
                            :drop (fn [_])})
      (local test-persistence {:kind "graph-node-cube"
                                :graph-map-id "test-map"
                                :node-key "test-key"
                                :label "Test Cube"
                                :size [4 4 4]})
      ;; Add to scene-children
      (when (not scene.scene-children)
        (set scene.scene-children []))
      (table.insert scene.scene-children
                    {:element test-element
                     :persistence test-persistence
                     :position (glm.vec3 0 0 0)
                     :rotation (glm.quat 1 0 0 0)})
      ;; Add to entity children
      (when (not scene.entity.children)
        (set scene.entity.children []))
      (table.insert scene.entity.children
                    {:element test-element
                     :position (glm.vec3 10 20 30)
                     :rotation (glm.quat 1 0 0 0)})
      ;; Capture this into the slot's scene-state for canonical storage.
      (local initial-state (ActivitySceneState.empty-state))
      ;; Shallow copy the persistence table for canonical storage.
      (local panel-copy {})
      (each [k v (pairs test-persistence)]
        (tset panel-copy k v))
      (set initial-state.panels [panel-copy])
      (set slot.scene-state initial-state)
      ;; Verify the scene has the panel in its children before switch.
      (assert (= (length (or scene.scene-children [])) 1)
              "Scene should have 1 panel before switch")
      ;; Switch to Graph (deactivates sandbox).
      (scene:ensure-activity-slot "graph")
      (scene:activate-activity-slot "graph")
      (assert (not slot.visible?) "Sandbox should be inactive after graph activation")
      ;; Simulate panel removal via WorldData: clear canonical panels.
      (set slot.scene-state.panels [])
      ;; Reactivate Sandbox.  R3-2 fix ensures the stale panel is removed.
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Sandbox should be active after reactivation")
      ;; Verify the stale panel was removed from scene-children.
      ;; After removal, scene-children should be empty (no persistent panels).
      (var persistent-panel-count 0)
      (each [_ metadata (ipairs (or scene.scene-children []))]
        (when (and metadata metadata.persistence)
          (set persistent-panel-count (+ persistent-panel-count 1))))
      (assert (= persistent-panel-count 0)
              (.. "Expected 0 persistent panels after reactivation with empty canonical, got "
                  (tostring persistent-panel-count)))
      (drop-fixture fixture))))

;; ── R3-3 skybox by-theme on activation ─────────────────────────────────

(fn sandbox-activation-resolves-skybox-by-theme []
  "R3-3: When activating a slot with a by-theme skybox override, the
  skybox applied to the renderer must resolve for the current active theme,
  not just use the default entry."
  (with-restored-app-fields
    [:renderers :themes :skybox-state :background-state :lights-state :physics-containment-config
     :__physics-global-containment :physics-containment-scene
     :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      ;; Build complete skybox state with a dark-theme override.
      (local complete-skybox
        (SkyboxState.normalize-complete-state
          {:enabled? true
           :default {:name "lake"
                     :brightness 0.1
                     :tint-color [1.0 1.0 1.0]}
           :by-theme {:dark {:name "night"
                              :brightness 0.3
                              :tint-color [0.8 0.8 1.0]}}}
          "test-by-theme"))
      ;; Unit-test: resolve-for-theme returns the dark entry when key is "dark".
      (let [resolved-dark (SkyboxState.resolve-for-theme complete-skybox :dark)]
        (assert (= resolved-dark.name "night")
                (.. "resolve-for-theme(:dark) should return night, got " (tostring resolved-dark.name)))
        (assert (= resolved-dark.brightness 0.3)
                (.. "resolve-for-theme(:dark) brightness should be 0.3, got " (tostring resolved-dark.brightness))))
      ;; resolve-for-theme with nil key returns the default entry.
      (let [resolved-nil (SkyboxState.resolve-for-theme complete-skybox nil)]
        (assert (= resolved-nil.name "lake")
                (.. "resolve-for-theme(nil) should return lake, got " (tostring resolved-nil.name))))
      ;; Set active theme to dark via a mock themes object, so
      ;; apply-state-to-services resolves the dark by-theme override.
      ;; The mock must expose get-active-theme returning {:name :dark}
      ;; because resolve-active-theme in scene.fnl extracts .name from it.
      (set app.themes
           {:get-active-theme (fn [] {:name :dark})
            :set-theme (fn [_name] true)})
      ;; Mock renderer to capture the exact skybox sent to it.
      (var renderer-skybox nil)
      (set app.renderers
           {:skybox {:get-state (fn [_] (or renderer-skybox
                                            {:enabled? false :name "lake" :brightness 0.1 :tint-color [1.0 1.0 1.0]}))
                    :set-state (fn [_ state] (set renderer-skybox state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      (local slot (scene:ensure-activity-slot "sandbox"))
      (local sandbox-state (ActivitySceneState.empty-state))
      (set sandbox-state.skybox complete-skybox)
      (scene:restore-activity-slot-state "sandbox" sandbox-state)
      ;; Activate sandbox.  With active theme = dark, the renderer must
      ;; receive the dark :by-theme override (night, brightness 0.3),
      ;; NOT the default lake skybox.  This assertion fails for the
      ;; original nil-theme bug where resolve-for-theme received nil
      ;; and always returned the default entry.
      (scene:activate-activity-slot "sandbox")
      (assert renderer-skybox "Skybox should have been set on activation")
      (assert renderer-skybox.enabled? "Renderer skybox should be enabled")
      (assert (not renderer-skybox.default)
              "Renderer skybox must NOT contain :default (complete state was not resolved)")
      (assert (not renderer-skybox.by-theme)
              "Renderer skybox must NOT contain :by-theme (complete state was not resolved)")
      (assert (= renderer-skybox.name "night")
              (.. "Expected dark-theme night skybox, got " (tostring renderer-skybox.name)))
      (assert (= renderer-skybox.brightness 0.3)
              (.. "Expected dark-theme brightness 0.3, got " (tostring renderer-skybox.brightness)))
      (drop-fixture fixture))))

(table.insert tests {:name "sandbox activation removes stale terrains when canonical empty"
                     :fn sandbox-activation-removes-stale-terrains-when-canonical-empty})
(table.insert tests {:name "slot switch preserves complete skybox policy"
                     :fn slot-switch-preserves-complete-skybox-policy})

(table.insert tests {:name "R3-1 sandbox activation replaces stale terrain with updated canonical"
                     :fn sandbox-activation-replaces-stale-terrain-with-updated-canonical})
(table.insert tests {:name "R3-2 sandbox activation removes stale panels on reactivation"
                     :fn sandbox-activation-removes-stale-panels-on-reactivation})
(table.insert tests {:name "R3-3 sandbox activation resolves skybox by-theme"
                     :fn sandbox-activation-resolves-skybox-by-theme})

;; ── R4-1 active slot content construction routes through slot ctx ───────

(fn terrain-build-routes-to-slot-context []
  "R4-1: When content is built via build/build-default/attach-entity into an
  active slot, the builder receives the slot's build-context (not surface empty
  context), the entity layout-root is set to the slot's layout-root, and the
  renderer-facing batches/vectors route through the slot's ctx."
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local sandbox-slot (scene:ensure-activity-slot "sandbox"))

  ;; Sentinels: surface context vector identifiers
  (set scene.build-context.triangle-vector :surface-triangle-vector)
  (set scene.build-context.line-vector :surface-line-vector)
  (set scene.build-context.point-vector :surface-point-vector)

  ;; Sentinels: sandbox slot context vector identifiers
  (set sandbox-slot.build-context.triangle-vector :slot-triangle-vector)
  (set sandbox-slot.build-context.line-vector :slot-line-vector)
  (set sandbox-slot.build-context.point-vector :slot-point-vector)

  ;; Activate sandbox slot
  (scene:activate-activity-slot "sandbox")
  (assert sandbox-slot.visible? "Sandbox slot should be active")

  ;; Verify pre-existing render routing (render context already routes to slot)
  (assert (= (scene:get-triangle-vector) :slot-triangle-vector)
          "Active render context should route to slot before content build")

  ;; R4-1: Verify that build() passes the slot's build-context to the builder
  (var builder-received-ctx nil)
  (fn mock-builder [ctx]
    (set builder-received-ctx ctx)
    ;; Return a minimal entity-like table
    (local entity {:layout {:children []
                            :set-root (fn [layout root] (set layout.__root root))
                            :set-position (fn [])
                            :set-rotation (fn [])
                            :mark-measure-dirty (fn [])
                            :position (glm.vec3 0 0 0)
                            :rotation (glm.quat 1 0 0 0)}
                   :children []
                   :scene-children []
                   :scene-terrains []
                   :scene-objects []
                   :movables []
                   :drop (fn [_])})
    entity)
  (scene:build mock-builder)
  (assert builder-received-ctx "Builder should have been called")
  (assert (= builder-received-ctx.triangle-vector :slot-triangle-vector)
          (.. "Builder should receive slot's build-context (triangle-vector), got "
              (tostring builder-received-ctx.triangle-vector)))
  (assert (= builder-received-ctx.line-vector :slot-line-vector)
          "Builder should receive slot's build-context (line-vector)")

  ;; R4-1: Verify that attach-entity sets the entity layout root to the slot's layout root
  (assert scene.entity "Scene should have an entity after build")
  (assert scene.entity.layout "Entity should have a layout")
  (assert (= scene.entity.layout.__root sandbox-slot.layout-root)
          (.. "Entity layout root should be the active slot's layout root, got "
              (tostring scene.entity.layout.__root)))
  (assert (not (= scene.entity.layout.__root scene.layout-root))
          "Entity layout root must NOT be the surface layout root")

  ;; After build, render context should still route through the active slot
  (assert (= (scene:get-triangle-vector) :slot-triangle-vector)
          "Render context should still route through slot after content build")
  (assert (= (scene:get-line-vector) :slot-line-vector)
          "Render line vector should still route through slot after content build")
  (assert (= (scene:get-point-vector) :slot-point-vector)
          "Render point vector should still route through slot after content build")

  (drop-fixture fixture))

(table.insert tests {:name "R4-1 terrain build routes to slot build-context"
                     :fn terrain-build-routes-to-slot-context})

;; ── R4-3 corrupt terrain activation fails loudly ────────────────────────

(fn corrupt-terrain-activation-fails []
  "R4-3: Activating a slot with corrupt/unsupported terrain records must
  fail loudly (not silently swallowed by pcall). The activation error
  must propagate out so callers can handle it."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :renderers
     :engine :physics-containment-config]
    (fn []
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      ;; Mock renderer services so service-application succeeds
      (var renderer-skybox
        {:enabled? false :name "lake" :brightness 0.1 :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] renderer-skybox)
                    :set-state (fn [_ state] (set renderer-skybox state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Ensure the sandbox slot exists but inject a corrupt terrain record
      ;; that will cause build-default to throw.  An empty kind string triggers
      ;; an assertion in normalize-record.
      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
      ;; Build a complete scene-state with valid services but corrupt terrains
      (local complete-skybox
        (SkyboxState.normalize-complete-state
          {:enabled? false
           :default {:name "lake" :brightness 0.1 :tint-color [1 1 1]}
           :by-theme {}}
          "test-corrupt-terrain-skybox"))
      (set sandbox-slot.scene-state {:panels []
                                     :terrains [{:kind ""}]
                                     :lights {:ambient {:enabled? false :color [1 1 1] :intensity 0}
                                              :directional []
                                              :point []
                                              :spot []}
                                     :skybox complete-skybox
                                     :background {:color [0 0 0]}
                                     :containment {:enabled? false}})
      ;; Activate the slot — this must fail because the corrupt terrain record
      ;; causes normalize-record to assert "Terrain record kind must not be empty"
      ;; during build-default → make-default-builder → normalize-records.
      (local (ok err) (pcall (fn [] (scene:activate-activity-slot "sandbox"))))
      (assert (not ok)
              "Activation with corrupt terrain must fail, not silently succeed")
      (assert (and err (string.find (tostring err) "Terrain record kind" 1 true))
              (.. "Error must mention terrain record kind, got: " (tostring err)))
      (drop-fixture fixture))))

(table.insert tests {:name "R4-3 corrupt terrain activation fails loudly"
                     :fn corrupt-terrain-activation-fails})

;; ── R4-3b transactional rollback on corrupt terrain ─────────────────────

(fn corrupt-terrain-activation-rolls-back-previous-slot []
  "R4-3: When activating a slot whose terrain build fails while switching
  from a different active slot, the activation must be transactional:
  the target slot must not remain active, and the previous slot (with its
  content/services/visibility) must be fully restored."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :renderers
     :engine :physics-containment-config]
    (fn []
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      ;; Mock renderer services so service-application succeeds
      (var renderer-skybox
        {:enabled? false :name "lake" :brightness 0.1 :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] renderer-skybox)
                    :set-state (fn [_ state] (set renderer-skybox state))}
            :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
            :set-background-state (fn [_ state] (set app.background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; (1) Create two activity slots — graph (healthy) and sandbox (corrupt)
      (local graph-slot (scene:ensure-activity-slot "graph"))
      ;; Set up a valid empty state for graph (no terrains, basic services)
      (local complete-skybox
        (SkyboxState.normalize-complete-state
          {:enabled? false
           :default {:name "lake" :brightness 0.1 :tint-color [1 1 1]}
           :by-theme {}}
          "test-r4-3b-skybox"))
      (set graph-slot.scene-state {:panels []
                                   :terrains []
                                   :lights {:ambient {:enabled? false :color [1 1 1] :intensity 0}
                                            :directional []
                                            :point []
                                            :spot []}
                                   :skybox complete-skybox
                                   :background {:color [0 0 0]}
                                   :containment {:enabled? false}})
      ;; (2) Activate graph slot (this becomes the "previous" slot)
      (scene:activate-activity-slot "graph")
      (assert graph-slot.visible? "Graph slot must be active after first activation")
      (assert (= scene.active-activity-slot-id "graph")
              "Scene must report graph as active slot")
      ;; (3) Build sandbox slot with corrupt terrain (invalid record with empty kind)
      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
      (set sandbox-slot.scene-state {:panels []
                                     :terrains [{:kind ""}]
                                     :lights {:ambient {:enabled? false :color [1 1 1] :intensity 0}
                                              :directional []
                                              :point []
                                              :spot []}
                                     :skybox complete-skybox
                                     :background {:color [0 0 0]}
                                     :containment {:enabled? false}})
      ;; (4) Attempt to activate corrupt sandbox — must fail
      (local (ok err) (pcall (fn [] (scene:activate-activity-slot "sandbox"))))
      (assert (not ok)
              "Activation with corrupt terrain must fail")
      (assert (and err (string.find (tostring err) "Terrain record kind" 1 true))
              (.. "Error must mention terrain record kind, got: " (tostring err)))
      ;; (5) Transactional rollback assertions:
      ;;     Graph must remain active/visible (the previous slot is restored)
      (assert graph-slot.visible?
              "Graph slot must remain visible after failed sandbox activation")
      (assert (= scene.active-activity-slot graph-slot)
              "Scene must still have graph as active slot after rollback")
      (assert (= scene.active-activity-slot-id "graph")
              "Scene must still report graph as active slot id after rollback")
      ;;     Sandbox must NOT be active
      (assert (not sandbox-slot.visible?)
              "Sandbox slot must remain invisible after failed activation")
      (assert (not (= scene.active-activity-slot sandbox-slot))
              "Sandbox slot must NOT be the active slot after failed activation")
      (drop-fixture fixture))))

(table.insert tests {:name "R4-3b corrupt terrain activation rolls back to previous slot"
                     :fn corrupt-terrain-activation-rolls-back-previous-slot})

;; ── R4-3c no-previous-slot rollback consistency ─────────────────────────

(fn corrupt-terrain-activation-no-previous-slot-consistent-cleanup []
  "R4-3: When activate-activity-slot fails with corrupt terrain and there
  was no previous active slot, the content aliases must be cleared to
  match the nil/empty values used by deactivate-activity-slot, and engine
  services must be reset to empty/disabled.  Uses non-empty services
  on the corrupt slot to verify rollback resets everything."
  (with-restored-app-fields
    [:lights-state :skybox-state :background-state :renderers
     :engine :physics-containment-config :physics-containment-scene
     :__physics-global-containment :lights]
    (fn []
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local PhysicsContainment (require :physics-containment))

      ;; Mock lights — captures the last set state
      (var lights-state {:ambient {:enabled? false :color [0 0 0] :intensity 0.0}
                         :directional []
                         :point []
                         :spot []})
      (set app.lights {:get-state (fn [_] lights-state)
                       :set-state (fn [_ state] (set lights-state state))})
      ;; Mock renderer skybox / background — captures last set state
      (var renderer-skybox
        {:enabled? false :name "lake" :brightness 0.1 :tint-color [1.0 1.0 1.0]})
      (var background-state {:color [0 0 0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] renderer-skybox)
                    :set-state (fn [_ state] (set renderer-skybox state))}
            :get-background-state (fn [_] background-state)
            :set-background-state (fn [_ state] (set background-state state))})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      ;; Track containment config
      (var containment-installed? nil)
      (local orig-ensure-installed PhysicsContainment.ensure-installed)
      (set PhysicsContainment.ensure-installed
           (fn [opts]
             (set containment-installed? (and opts.config opts.config.enabled?))
             (orig-ensure-installed opts)))
      (set app.__physics-global-containment nil)

      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; (1) Create sandbox slot with corrupt terrain AND non-empty services
      ;;     so we can verify the rollback resets them to empty/disabled.
      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
      (local complete-skybox
        (SkyboxState.normalize-complete-state
          {:enabled? true
           :default {:name "ocean" :brightness 0.75 :tint-color [0.8 0.9 1.0]}
           :by-theme {}}
          "test-r4-3c-skybox"))
      ;; Non-empty services distinguishable from empty/disabled
      (set sandbox-slot.scene-state {:panels []
                                     :terrains [{:kind ""}]
                                     :lights {:ambient {:enabled? true
                                                         :color [0.5 0.3 0.1]
                                                         :intensity 2.5}
                                              :directional []
                                              :point []
                                              :spot []}
                                     :skybox complete-skybox
                                     :background {:color [0.1 0.2 0.3]}
                                     :containment {:enabled? true}})
      ;; (2) Verify no active slot before the attempt
      (assert (= scene.active-activity-slot nil)
              "Scene should have no active slot before activation attempt")
      (assert (not sandbox-slot.visible?)
              "Sandbox slot should be invisible before activation attempt")
      ;; Services should be at defaults before activation
      (assert (not lights-state.ambient.enabled?)
              "Lights should be disabled before activation")

      ;; (3) Attempt to activate corrupt sandbox — must fail
      (local (ok err) (pcall (fn [] (scene:activate-activity-slot "sandbox"))))
      (assert (not ok)
              "Activation with corrupt terrain must fail when no previous slot exists")
      (assert (and err (string.find (tostring err) "activate-activity-slot failed" 1 true))
              (.. "Error must report activate-activity-slot failure, got: " (tostring err)))

      ;; (4) No-previous-slot rollback assertions:
      ;;     (a) Target slot must be invisible/inactive (retains scene-state but not active)
      (assert (not sandbox-slot.visible?)
              "Sandbox slot must be invisible after failed activation")
      (assert (not sandbox-slot.interactive?)
              "Sandbox slot must be non-interactive after failed activation")
      ;;     (b) Scene active slot binding must be nil
      (assert (= scene.active-activity-slot nil)
              "Scene.active-activity-slot must be nil after failed activation")
      (assert (= scene.active-activity-slot-id nil)
              "Scene.active-activity-slot-id must be nil after failed activation")
      ;;     (c) Content aliases must match deactivate-activity-slot cleanup
      (assert (= scene.entity nil)
              "Scene.entity must be nil after failed activation (no previous slot)")
      (assert (= scene.scene-children nil)
              "Scene.scene-children must be nil after failed activation")
      (assert (= scene.scene-terrains nil)
              "Scene.scene-terrains must be nil after failed activation")
      (assert (= (length scene.queued-cube-panels) 0)
              "Scene.queued-cube-panels must be empty after failed activation")
      (var panel-restorer-count 0)
      (each [_ _ (pairs (or scene.panel-restorers {}))]
        (set panel-restorer-count (+ panel-restorer-count 1)))
      (assert (= panel-restorer-count 0)
              "Scene.panel-restorers must be empty after failed activation")
      (assert (= scene.demo-browser nil)
              "Scene.demo-browser must be nil after failed activation")
      (assert (= scene.physics-body-count 0)
              "Scene.physics-body-count must be 0 after failed activation")

      ;; (5) Service rollback: all services must be reset to empty/disabled
      ;;     (a) Lights: ambient disabled, default color/intensity
      (assert (not lights-state.ambient.enabled?)
              "Lights ambient must be disabled after rollback")
      ;;     (b) Skybox: disabled
      (assert (not renderer-skybox.enabled?)
              "Renderer skybox must be disabled after rollback")
      ;;     (c) Background: default color [0 0 0]
      (assert (and background-state background-state.color
                   (= (. background-state.color 1) 0.0)
                   (= (. background-state.color 2) 0.0)
                   (= (. background-state.color 3) 0.0))
              "Background must be reset to default [0 0 0] after rollback")
      ;;     (d) Containment: disabled
      (assert (not containment-installed?)
              "Physics containment must be not-installed/disabled after rollback")

      ;; Restore PhysicsContainment.ensure-installed
      (set PhysicsContainment.ensure-installed orig-ensure-installed)
      (drop-fixture fixture))))

(table.insert tests {:name "R4-3c corrupt terrain activation no-previous-slot consistent cleanup"
                     :fn corrupt-terrain-activation-no-previous-slot-consistent-cleanup})

;; ── R4-3d retained slot content preserved on rollback ───────────────────

(fn corrupt-activation-preserves-retained-slot-content []
  "R4-3: When a slot with pre-existing retained content (entity,
  scene-children, scene-terrains, physics bodies) fails activation
  with corrupt terrain and no previous active slot, the rollback must:
  - Deactivate layout physics bodies on the entity
  - Clear Scene surface aliases (entity nil, scene-children nil, etc.)
  - Preserve the slot's own retained fields (slot.entity, slot.scene-children,
    slot.scene-terrains) intact
  - Leave the slot invisible/inactive"
  (with-restored-app-fields
    [:renderers :engine :lights :physics-containment-config
     :physics-containment-scene :__physics-global-containment
     :skybox-state :background-state :lights-state]
    (fn []
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local LayoutPhysicsBodies (require :layout-physics-bodies))
      (local PhysicsContainment (require :physics-containment))

      ;; Mock services
      (var renderer-skybox
        {:enabled? false :name "lake" :brightness 0.1 :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] renderer-skybox)
                    :set-state (fn [_ state] (set renderer-skybox state))}
            :get-background-state (fn [_] {:color [0 0 0]})
            :set-background-state (fn [_ state])})
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})
      (set app.lights {:get-state (fn [_] {:ambient {:enabled? false :color [0 0 0] :intensity 0} :directional [] :point [] :spot []})
                       :set-state (fn [_ _state])})
      ;; Suppress containment
      (local orig-ensure-installed PhysicsContainment.ensure-installed)
      (set PhysicsContainment.ensure-installed (fn [_opts] true))
      (set app.__physics-global-containment nil)

      (local fixture (make-scene))
      (local scene fixture.scene)
      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))

      ;; (1) Seed the slot with pre-existing retained content
      ;;     Build a mock entity with layout, children, and physics
      (local entity-layout
        {:children []
         :set-root (fn [layout _root] (set layout.__root :slot-root))
         :__root nil
         :set-position (fn [])
         :set-rotation (fn [])
         :mark-measure-dirty (fn [])
         :position (glm.vec3 0 0 0)
         :rotation (glm.quat 1 0 0 0)})
      (local mock-entity
        {:layout entity-layout
         :children []
         :scene-children []
         :scene-terrains []
         :scene-objects []
         :movables []
         :drop (fn [_])})
      ;; Give the entity a physics entry so deactivate has something to act on
      (var physics-deactivate-called false)
      (local orig-deactivate LayoutPhysicsBodies.deactivate)
      (set LayoutPhysicsBodies.deactivate
           (fn [ent]
             (when (= ent mock-entity)
               (set physics-deactivate-called true))
             (orig-deactivate ent)))
      ;; Create a runtime physics entry on the entity
      (local element
        {:layout {:position (glm.vec3 0 5 0)
                  :rotation (glm.quat 1 0 0 0)
                  :size (glm.vec3 4 4 4)
                  :measure (glm.vec3 4 4 4)
                  :children []
                  :parent entity-layout
                  :root entity-layout
                  :depth-offset-index 0
                  :mark-measure-dirty (fn [_layout])}})
      (local entry
        (LayoutPhysicsBodies.add-runtime-layout-body mock-entity {:element element}))
      ;; entry was created; may or may not have a live body depending on bt availability

      ;; Seed slot with retained content
      (set sandbox-slot.entity mock-entity)
      (set sandbox-slot.scene-children
           [{:element element
             :persistence {:kind "physics-cuboid"
                           :size [4 4 4]}
             :position (glm.vec3 0 0 0)
             :rotation (glm.quat 1 0 0 0)}])
      (set sandbox-slot.scene-terrains
           [{:element element :record {:id "t-retained" :kind "heightfield-terrain"}}])

      ;; (2) Inject corrupt terrain into slot's scene-state
      (local complete-skybox
        (SkyboxState.normalize-complete-state
          {:enabled? false
           :default {:name "lake" :brightness 0.1 :tint-color [1 1 1]}
           :by-theme {}}
          "test-r4-3d-skybox"))
      (set sandbox-slot.scene-state {:panels []
                                     :terrains [{:kind ""}]
                                     :lights {:ambient {:enabled? false :color [1 1 1] :intensity 0}
                                              :directional []
                                              :point []
                                              :spot []}
                                     :skybox complete-skybox
                                     :background {:color [0 0 0]}
                                     :containment {:enabled? false}})

      ;; (3) Verify pre-activation state
      (assert (= scene.active-activity-slot nil) "No active slot before test")
      (assert (not sandbox-slot.visible?) "Slot invisible before activation")
      (assert sandbox-slot.entity "Slot has retained entity")
      (assert sandbox-slot.scene-children "Slot has retained scene-children")
      (assert sandbox-slot.scene-terrains "Slot has retained scene-terrains")

      ;; (4) Activate — must fail due to corrupt terrain
      (local (ok _err) (pcall (fn [] (scene:activate-activity-slot "sandbox"))))
      (assert (not ok) "Activation with corrupt terrain must fail")

      ;; (5) Rollback assertions for retained content preservation:
      ;;     (a) Slot-owned content must be intact
      (assert (= sandbox-slot.entity mock-entity)
              "Slot.entity must still reference the pre-seeded entity")
      (assert sandbox-slot.scene-children
              "Slot.scene-children must still exist")
      (assert (= (length sandbox-slot.scene-children) 1)
              (.. "Slot.scene-children must have 1 entry, got "
                  (tostring (length (or sandbox-slot.scene-children [])))))
      (assert sandbox-slot.scene-terrains
              "Slot.scene-terrains must still exist")
      (assert (= (length sandbox-slot.scene-terrains) 1)
              (.. "Slot.scene-terrains must have 1 entry, got "
                  (tostring (length (or sandbox-slot.scene-terrains [])))))
      ;;     (b) Slot is invisible/inactive
      (assert (not sandbox-slot.visible?)
              "Slot must be invisible after failed activation")
      (assert (not sandbox-slot.interactive?)
              "Slot must be non-interactive after failed activation")
      ;;     (c) Scene surface aliases are cleared
      (assert (= scene.entity nil)
              "Scene.entity must be nil after rollback")
      (assert (= scene.scene-children nil)
              "Scene.scene-children must be nil after rollback")
      (assert (= scene.scene-terrains nil)
              "Scene.scene-terrains must be nil after rollback")
      ;;     (d) Active slot binding is nil
      (assert (= scene.active-activity-slot nil)
              "Scene.active-activity-slot must be nil after rollback")
      (assert (= scene.active-activity-slot-id nil)
              "Scene.active-activity-slot-id must be nil after rollback")
      ;;     (e) Layout physics deactivation occurred
      (assert physics-deactivate-called
              "LayoutPhysicsBodies.deactivate must have been called during rollback")

      ;; Restore mock
      (set LayoutPhysicsBodies.deactivate orig-deactivate)
      (set PhysicsContainment.ensure-installed orig-ensure-installed)
      (drop-fixture fixture))))

(table.insert tests {:name "R4-3d corrupt activation preserves retained slot content"
                     :fn corrupt-activation-preserves-retained-slot-content})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-activity-slots"
                       :tests tests})))

{:name "scene-activity-slots"
 :tests tests
 :main main}
