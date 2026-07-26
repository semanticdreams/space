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
(table.insert tests {:name "Scene activate-activity-slot fails on unknown"
                        :fn activate-activity-slot-fails-on-unknown})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-activity-slots"
                       :tests tests})))

{:name "scene-activity-slots"
 :tests tests
 :main main}
