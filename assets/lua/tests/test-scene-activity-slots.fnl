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

;; ── R6-1: Scene content input registrations are slot-scoped ────────────

(fn slot-content-movables-use-slot-pointer-target []
  "R6-1: movables/resizables registered for content built inside an activity
  slot must carry the owning slot's pointer-target so that
  app.pointer-target-enabled? rejects them when the slot is inactive."
  (with-restored-app-fields
    [:scene
     :scene-interactive?
     :pointer-target-enabled?
     :movables]
    (fn []
      (Main.install-app-shell!)
      (local glm (require :glm))
      (local fixture (make-scene))
      (local scene fixture.scene)
      (set app.scene scene)
      (set app.scene-interactive? true)
      ;; Track movable registrations to inspect pointer-target
      (var registered-movables [])
      (set app.movables
           {:register
            (fn [_movables _widget opts]
              (table.insert registered-movables opts))
            :unregister (fn [_movables _key])})

      ;; (1) Activate sandbox and build content — movables must use
      ;;     the sandbox slot's pointer-target.
      (local sandbox-slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      ;; Build a minimal entity with layout (simulates content building)
      (fn mock-builder [ctx]
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
      ;; Movables should have been registered with sandbox slot pointer-target
      (assert (> (length registered-movables) 0)
              "Building content should register movables")
      (var sandbox-pt-count 0)
      (each [_ opts (ipairs registered-movables)]
        (when (= opts.pointer-target sandbox-slot.pointer-target)
          (set sandbox-pt-count (+ sandbox-pt-count 1))))
      (assert (> sandbox-pt-count 0)
              "Movables registered under Sandbox must carry Sandbox slot pointer-target")

      ;; (2) Sandbox slot is active → pointer-target should be enabled
      (each [_ opts (ipairs registered-movables)]
        (assert (app.pointer-target-enabled? opts.pointer-target)
                "Sandbox content movables should be enabled while Sandbox is active"))

      ;; (3) Switch to Graph → Sandbox content movables must be disabled
      (local graph-slot (scene:ensure-activity-slot "graph"))
      (scene:activate-activity-slot "graph")
      (each [_ opts (ipairs registered-movables)]
        (assert (not (app.pointer-target-enabled? opts.pointer-target))
                "Sandbox content movables must be disabled when Graph is active"))

      ;; (4) Switch back to Sandbox → Sandbox content movables re-enabled
      (scene:activate-activity-slot "sandbox")
      (each [_ opts (ipairs registered-movables)]
        (assert (app.pointer-target-enabled? opts.pointer-target)
                "Sandbox content movables must be re-enabled when Sandbox reactivates"))

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

;; ── R6-2: Dropping a retained slot releases entity ─────────────────────

(fn drop-inactive-slot-releases-retained-entity []
  "R6-2: Dropping a retained (inactive) Scene activity slot must deactivate
  physics, unregister movables/resizables, and drop the entity without
  double-dropping active content."
  (with-restored-app-fields
    [:movables :resizables :engine]
    (fn []
      (local glm (require :glm))
      (local LayoutPhysicsBodies (require :layout-physics-bodies))
      (pcall require :bt)
      (local fixture (make-scene))
      (local scene fixture.scene)

      ;; Mock physics
      (var deactivate-calls [])
      (var remove-rigid-body-called false)
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body]
                                                     (set remove-rigid-body-called true))}})

      ;; Mock movables
      (var movable-unregister-calls [])
      (set app.movables {:register (fn [_m _w _o])
                         :unregister (fn [_m key] (table.insert movable-unregister-calls key))})
      (var resizable-unregister-calls [])
      (set app.resizables {:register (fn [_r _w _o])
                           :unregister (fn [_r key] (table.insert resizable-unregister-calls key))})

      ;; (1) Create a slot, activate it, build content with physics
      (local slot (scene:ensure-activity-slot "sandbox"))
      (scene:activate-activity-slot "sandbox")
      ;; Build a mock entity
      (fn mock-builder [ctx]
        (local entity-layout
          {:children []
           :set-root (fn [_layout _root])
           :set-position (fn [])
           :set-rotation (fn [])
           :mark-measure-dirty (fn [])
           :position (glm.vec3 0 0 0)
           :rotation (glm.quat 1 0 0 0)})
        (local entity
          {:layout entity-layout
           :children []
           :scene-children []
           :scene-terrains []
           :scene-objects []
           :movables []
           :drop (fn [_])})
        ;; Create a physics entry on the entity
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
        (LayoutPhysicsBodies.add-runtime-layout-body entity {:element element})
        ;; Give entity movable/resizable keys so slot.drop can unregister them
        (set entity.__scene_movable_keys ["movable-key-1" "movable-key-2"])
        (set entity.__scene_resizable_keys ["resizable-key-1"])
        entity)
      (scene:build mock-builder)
      (assert scene.entity "Entity should exist after build")
      (assert slot.entity "Slot should own the entity")

      ;; Track if entity.drop was called
      (var entity-dropped? false)
      (set slot.entity.drop (fn [_] (set entity-dropped? true)))

      ;; (2) Deactivate sandbox (slot is now inactive) — switch to graph
      (scene:ensure-activity-slot "graph")
      (scene:activate-activity-slot "graph")
      ;; Slot retains entity but scene does not
      (assert slot.entity "Slot must retain entity when inactive")
      (assert (not (= scene.entity slot.entity))
              "Scene entity should be different from retained slot entity")

      ;; (3) Drop the retained slot — must release entity
      (scene:drop-activity-slot "sandbox")
      (assert (= (scene:activity-slot "sandbox") nil)
              "Slot must be removed after drop")
      ;; Entity must have been dropped
      (assert entity-dropped?
              "Inactive slot entity must be dropped on slot.drop")
      ;; Movables must be unregistered
      (assert (> (length movable-unregister-calls) 0)
              "Slot.drop must unregister movables for retained entity")
      ;; Resizables must be unregistered
      (assert (> (length resizable-unregister-calls) 0)
              "Slot.drop must unregister resizables for retained entity")

      (drop-fixture fixture))))

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
    [:skybox-state :background-state :lights-state :renderers :engine]
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
      (local sandbox-slot (scene:activity-slot "sandbox"))
      (local sandbox-manager sandbox-slot.physics-containment-manager)
      (assert sandbox-manager "Sandbox slot should have a containment manager after activation")
      (assert (not (= sandbox-manager.config nil))
              "Sandbox activation should set containment config on manager")
      (assert sandbox-manager.config.enabled?
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
      (local graph-slot (scene:activity-slot "graph"))
      (local graph-manager graph-slot.physics-containment-manager)
      (assert graph-manager "Graph slot should have a containment manager after activation")
      (assert (and graph-manager.config
                   (not graph-manager.config.enabled?))
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
      (local sb-slot2 (scene:activity-slot "sandbox"))
      (local sb-manager2 sb-slot2.physics-containment-manager)
      (assert (and sb-manager2 sb-manager2.config
                   sb-manager2.config.enabled?)
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
    [:skybox-state :background-state :lights-state :renderers :engine]
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
    [:skybox-state :background-state :lights-state :renderers :engine]
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
    [:skybox-state :background-state :lights-state :renderers :engine]
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
    [:engine]
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
      (set app.engine {:physics {:addRigidBody (fn [_phys body] (table.insert installed-planes body))}})

      ;; Create a manager
      (local manager (PhysicsContainment.create-manager
                       {:owner {}
                        :physics app.engine.physics}))

      ;; Setup: install enabled containment
      (manager:ensure-installed {:config {:enabled? true}})
      (assert (> (length installed-planes) 0)
              "ensure-installed with enabled? true should install containment planes")
      (assert (not (= manager.config nil))
              "ensure-installed should set manager.config")

      ;; Clean up and test disabled
      (manager:clear)
      (set installed-planes [])

      ;; Install disabled containment: should clear and install nothing
      (local result (manager:ensure-installed {:config {:enabled? false}}))
      ;; When enabled? is false, ensure-installed clears and returns false
      (assert (= result false)
              "ensure-installed with enabled? false should return false")
      (assert (= (length installed-planes) 0)
              "ensure-installed with enabled? false should not install planes")

      ;; Clean up
      (manager:drop))))

(table.insert tests {:name "Scene activity slots return same slot on repeat"
                     :fn ensure-activity-slot-returns-same-slot})
(table.insert tests {:name "Scene activity slots have distinct context and root"
                     :fn slot-has-distinct-context-and-root})
(table.insert tests {:name "Scene active slot controls render context"
                     :fn active-slot-controls-render-context})
(table.insert tests {:name "Scene slot pointer target routing"
                     :fn slot-pointer-target-routing})
(table.insert tests {:name "R6-1 slot content movables use slot pointer target"
                     :fn slot-content-movables-use-slot-pointer-target})
(table.insert tests {:name "Scene activity slot drop removes content"
                     :fn drop-activity-slot-removes-content})
(table.insert tests {:name "R6-2 drop inactive slot releases retained entity"
                      :fn drop-inactive-slot-releases-retained-entity})
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

;; ── Task 1: Scene Slot Presentation Targets ─────────────────────────

(fn empty-scene-slot-exposes-no-presentation-target []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (scene:ensure-activity-slot "drawing")
  (scene:activate-activity-slot "drawing")
  (assert (= (scene:presentation-target) nil)
          "An empty scene slot must not expose a render target")
  (drop-fixture fixture))

(fn scene-presentation-target-uses-slot-camera []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local slot-camera-a (Camera {:position (glm.vec3 1 2 3)}))
  (local slot-camera-b (Camera {:position (glm.vec3 10 20 30)}))
  (local slot (scene:ensure-activity-slot "sandbox" {:camera slot-camera-a}))
  (scene:activate-activity-slot "sandbox")
  (slot:expose-render-target! {:layers [:geometry :text]})
  (local target-a (scene:presentation-target))
  (assert (= target-a.camera slot-camera-a)
          "Scene target must use the slot-owned camera")
  (slot:set-camera slot-camera-b)
  (local target-b (scene:presentation-target))
  (assert (= target-b.camera slot-camera-b)
          "Changing the slot camera must change the presentation target camera")
  (slot-camera-a:drop)
  (slot-camera-b:drop)
  (drop-fixture fixture))

(table.insert tests {:name "Task 1: empty scene slot exposes no presentation target"
                     :fn empty-scene-slot-exposes-no-presentation-target})
(table.insert tests {:name "Task 1: scene presentation target uses slot camera"
                     :fn scene-presentation-target-uses-slot-camera})

;; ── R1-1: active slot without camera fails loudly ────────────────────

(fn active-slot-without-camera-fails-loudly []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (scene:ensure-activity-slot "sandbox")
  (scene:activate-activity-slot "sandbox")
  ;; get-view-matrix must fail because the active slot has no camera
  (local (ok-v err-v) (pcall (fn [] (scene:get-view-matrix))))
  (assert (not ok-v)
          "get-view-matrix must fail when active slot has no camera")
  (assert (string.find (tostring err-v) "requires its own camera" 1 true)
          (.. "get-view-matrix error must mention missing slot camera, got: "
              (tostring err-v)))
  ;; screen-pos-ray must also fail (it delegates to get-view-matrix)
  (local (ok-s err-s) (pcall (fn [] (scene:screen-pos-ray {:x 100 :y 200}))))
  (assert (not ok-s)
          "screen-pos-ray must fail when active slot has no camera")
  (assert (string.find (tostring err-s) "requires its own camera" 1 true)
          (.. "screen-pos-ray error must mention missing slot camera, got: "
              (tostring err-s)))
  (drop-fixture fixture))

(table.insert tests {:name "R1-1: active slot without camera fails loudly"
                     :fn active-slot-without-camera-fails-loudly})

;; ── R1-2: presentation target parameter handling and ownership ───────

(fn presentation-target-screen-pos-ray-uses-slot-camera []
  "R1-2: target:screen-pos-ray must use the slot-owned camera, not
  the current active Scene camera.  Verify argument handling (receiver
  parameter) and captured camera/projection ownership."
  (with-restored-app-fields
    [:viewport]
    (fn []
      (set app.viewport {:x 0 :y 0 :width 800 :height 600})
      (local fixture (make-scene))
      (local scene fixture.scene)
      ;; Ensure the scene has a valid projection for ray computation
      (set scene.projection (glm.ortho -40 40 -30 30 -100.0 1000.0))
      (local slot-camera (Camera {:position (glm.vec3 50 50 100)}))
      (local slot (scene:ensure-activity-slot "sandbox" {:camera slot-camera}))
      (scene:activate-activity-slot "sandbox")
      (slot:expose-render-target! {:layers [:geometry]})
      (local target (scene:presentation-target))
      (assert target "presentation-target must return non-nil")
      (assert target.camera "target must have camera")
      ;; R1-2a: target:screen-pos-ray must handle receiver parameter correctly.
      ;; When called as target:screen-pos-ray({:x 10 :y 20}), the first
      ;; argument is the target object and the second is the pointer.
      (local ray (target:screen-pos-ray {:x 10 :y 20}))
      (assert ray "target:screen-pos-ray must return a ray")
      (assert ray.origin "ray must have origin")
      (assert ray.direction "ray must have direction")
      ;; R1-2b: target.get-render-contexts must return slot.ctx
      (local contexts (target:get-render-contexts))
      (assert contexts "target:get-render-contexts must return a table")
      (assert (= (type contexts) :table)
              "target:get-render-contexts must return a table")
      (assert (= (length contexts) 1)
              (.. "expected exactly 1 render context, got " (tostring (length contexts))))
      (assert (= (. contexts 1) slot.ctx)
              "target:get-render-contexts must return the slot's ctx, not active-render-context")
      ;; R1-2c: target:screen-pos-ray must use slot camera, not surface camera.
      ;; Verify by moving the surface camera away and confirming the ray still
      ;; uses the slot camera position.
      (scene:set-camera (Camera {:position (glm.vec3 -999 -999 -999)}))
      (local ray-after-surface-move (target:screen-pos-ray {:x 10 :y 20}))
      (assert ray-after-surface-move "ray must still work after surface camera move")
      (assert ray-after-surface-move.origin "ray origin must exist after surface camera move")
      ;; The ray origin should be near slot-camera position (50,50,100), not the
      ;; surface camera at (-999,-999,-999).
      (assert (< (math.abs (- ray-after-surface-move.origin.x 50)) 200)
              (.. "ray origin x should be near slot camera 50, got "
                  (tostring ray-after-surface-move.origin.x)))
      (slot-camera:drop)
      (drop-fixture fixture))))

(table.insert tests {:name "R1-2: target screen-pos-ray uses slot camera and context"
                     :fn presentation-target-screen-pos-ray-uses-slot-camera})

;; ── R2-1 ──────────────────────────────────────────────────────────────

(fn inactive-capture-uses-authoritative-terrains []
  "R2-1: When a slot is inactive, capture-activity-slot-state must use the
  authoritative slot.scene-state.terrains, NOT stale slot.scene-terrains.
  This prevents stale runtime terrain from overwriting canonical state
  during inactive capture."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :renderers :engine]
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
    [:skybox-state :background-state :lights-state :renderers :engine]
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
    [:skybox-state :background-state :lights-state :renderers :engine]
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
    [:skybox-state :background-state :lights-state :renderers :engine]
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
    [:renderers :skybox-state :background-state :lights-state
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
    [:renderers :skybox-state :background-state :lights-state
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
    [:skybox-state :background-state :lights-state
     :renderers :themes :engine]
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
     :engine]
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
     :engine]
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

;; ── Task 6: Stale containment refresh does not install into wrong slot ──

(fn stale-containment-refresh-does-not-install-into-new-active-slot []
  (with-restored-app-fields
    [:engine]
    (fn []
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))
      ;; Mock engine with events support for the debouncer.
      ;; The debouncer uses updated:connect to subscribe and updated:emit
      ;; to receive delta values.  We simulate the full event lifecycle.
      (var update-handlers [])
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}
                        :events {:updated {:connect (fn [_self handler]
                                                      (table.insert update-handlers handler)
                                                      handler)
                                          :disconnect (fn [_self handler _ok?]
                                                        (for [i (length update-handlers) 1 -1]
                                                          (when (= (. update-handlers i) handler)
                                                            (table.remove update-handlers i)))
                                                        true)
                                          :emit (fn [_self delta]
                                                  (each [_ handler (ipairs update-handlers)]
                                                    (pcall (fn [] (handler delta)))))}}
                        :now-ms (fn [self] 0)})
      (local fixture (make-scene))
      (local scene fixture.scene)
      (scene:ensure-activity-slot "sandbox")
      (scene:ensure-activity-slot "drawing")
      ;; Verify no managers exist before activation
      (assert (= (. (scene:activity-slot "drawing") :physics-containment-manager) nil)
              "Drawing slot should have no manager before any activation")
      (scene:activate-activity-slot "sandbox")
      ;; After sandbox activation, drawing still has no manager
      (assert (= (. (scene:activity-slot "drawing") :physics-containment-manager) nil)
              "Drawing slot should have no manager after sandbox activation")
      ;; Create the sandbox slot's containment manager
      (local sandbox-slot (scene:activity-slot "sandbox"))
      (local sandbox-manager (sandbox-slot:ensure-containment-manager))
      (assert sandbox-manager "Sandbox slot should have a containment manager when active")
      ;; Schedule a debounced refresh with a long delay
      (sandbox-manager:schedule-refresh
        {:scene scene
         :config {:debounce-ms 10000
                  :mode "manual-bounds"
                  :bounds {:min [-10 -10 -10]
                           :max [10 10 10]}}})
      ;; Verify the debouncer was created
      (assert sandbox-manager.debouncer "Sandbox manager should have a debouncer after schedule-refresh")
      ;; Switch to drawing slot — this deactivates sandbox slot
      (scene:activate-activity-slot "drawing")
      ;; Fire the debounce by emitting a large delta.  The debounced callback
      ;; captured the sandbox manager's owner identity.  The callback fires
      ;; on the SANDBOX manager, not the drawing slot's manager.
      (pcall (fn [] (app.engine.events.updated:emit 10000)))
      ;; Assert: the drawing slot's manager must NOT have an active containment
      ;; installation (the stale refresh from sandbox must not install into drawing).
      (local drawing-slot2 (scene:activity-slot "drawing"))
      (assert drawing-slot2.physics-containment-manager
              "Drawing slot should have a manager from normal activation")
      (assert (= drawing-slot2.physics-containment-manager.installation nil)
              "Drawing slot manager must not have containment installation (stale refresh from sandbox)")
      (drop-fixture fixture))))

(table.insert tests {:name "Task 6: stale containment refresh does not install into new active slot"
                     :fn stale-containment-refresh-does-not-install-into-new-active-slot})

;; ── R4-3c no-previous-slot rollback consistency ─────────────────────────

(fn corrupt-terrain-activation-no-previous-slot-consistent-cleanup []
  "R4-3: When activate-activity-slot fails with corrupt terrain and there
  was no previous active slot, the content aliases must be cleared to
  match the nil/empty values used by deactivate-activity-slot, and engine
  services must be reset to empty/disabled.  Uses non-empty services
  on the corrupt slot to verify rollback resets everything."
  (with-restored-app-fields
    [:lights-state :skybox-state :background-state :renderers
     :engine :lights]
    (fn []
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))

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
      ;;     (d) Containment: slot manager must have no active installation
      ;;         after rollback.  The manager itself survives on the slot but
      ;;         its planes are removed and config is disabled.
      (let [sb-mgr sandbox-slot.physics-containment-manager]
        (assert (or (not sb-mgr) (= sb-mgr.installation nil))
                "Physics containment must be not-installed/disabled after rollback"))
      (sandbox-slot.physics-containment-manager:drop)
      (set sandbox-slot.physics-containment-manager nil)

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
    [:renderers :engine :lights
     :skybox-state :background-state :lights-state]
    (fn []
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local LayoutPhysicsBodies (require :layout-physics-bodies))
      ;; Ensure bt is loaded so physics-available? in layout-physics-bodies resolves
      (pcall require :bt)

      ;; Mock services
      (var renderer-skybox
        {:enabled? false :name "lake" :brightness 0.1 :tint-color [1.0 1.0 1.0]})
      (set app.renderers
           {:skybox {:get-state (fn [_] renderer-skybox)
                    :set-state (fn [_ state] (set renderer-skybox state))}
            :get-background-state (fn [_] {:color [0 0 0]})
            :set-background-state (fn [_ state])})
       (set app.lights {:get-state (fn [_] {:ambient {:enabled? false :color [0 0 0] :intensity 0} :directional [] :point [] :spot []})
                        :set-state (fn [_ _state])})
      ;; Containment is handled by the slot's manager during activation.
      ;; The slot's scene-state has :containment {:enabled? false}, so the
      ;; manager will be created with disabled containment — no planes installed.

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
      ;; Track whether entity.drop was called — must NOT be called during rollback
      (var entity-dropped false)
      (local mock-entity
        {:layout entity-layout
         :children []
         :scene-children []
         :scene-terrains []
         :scene-objects []
         :movables []
         :drop (fn [_] (set entity-dropped true))})
      ;; Give the entity a physics entry so deactivate has something to act on
      (var physics-deactivate-called false)
      (local orig-deactivate LayoutPhysicsBodies.deactivate)
      (set LayoutPhysicsBodies.deactivate
           (fn [ent]
             (when (= ent mock-entity)
               (set physics-deactivate-called true))
             (orig-deactivate ent)))
      ;; Track removeRigidBody calls to prove actual body removal
      (var remove-rigid-body-called false)
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body]
                                                     (set remove-rigid-body-called true))}})
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
      ;; Force the entry into an unquestionably active state so the
      ;; deactivate path during rollback exercises real body removal.
      ;; If bt created a live body it's already active; otherwise give it a
      ;; sentinel body and mark it active so remove-body fires and flips
      ;; body-active? false (and removeRigidBody if physics-available?).
      (when (not entry.body)
        (set entry.body {:__mock_body true}))
      (set entry.body-active? true)
      ;; Reset the removeRigidBody tracker after setup so only
      ;; rollback-triggered calls are counted.
      (set remove-rigid-body-called false)

      ;; (pre-condition) Verify the entry is active before the corrupt activation
      (assert entry.body "Entry must have a body before activation")
      (assert entry.body-active? "Entry.body-active? must be true before activation")

      ;; Seed slot with retained content — save exact references for identity check
      (set sandbox-slot.entity mock-entity)
      (local retained-child-metadata
        {:element element
         :persistence {:kind "physics-cuboid"
                       :size [4 4 4]}
         :position (glm.vec3 0 0 0)
         :rotation (glm.quat 1 0 0 0)})
      (local retained-terrain-metadata
        {:element element :record {:id "t-retained" :kind "heightfield-terrain"}})
      (set sandbox-slot.scene-children [retained-child-metadata])
      (set sandbox-slot.scene-terrains [retained-terrain-metadata])

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
      ;;     (a) Slot-owned content must be intact — exact table identity
      (assert (= sandbox-slot.entity mock-entity)
              "Slot.entity must still reference the pre-seeded entity")
      (assert sandbox-slot.scene-children
              "Slot.scene-children must still exist")
      (assert (= (. sandbox-slot.scene-children 1) retained-child-metadata)
              "Slot.scene-children[1] must be the exact same table reference")
      (assert sandbox-slot.scene-terrains
              "Slot.scene-terrains must still exist")
      (assert (= (. sandbox-slot.scene-terrains 1) retained-terrain-metadata)
              "Slot.scene-terrains[1] must be the exact same table reference")
      ;;     (b) entity:drop must NOT have been called (slot content preserved)
      (assert (not entity-dropped)
              "mock-entity.drop must NOT have been called during rollback")
      ;;     (c) Slot is invisible/inactive
      (assert (not sandbox-slot.visible?)
              "Slot must be invisible after failed activation")
      (assert (not sandbox-slot.interactive?)
              "Slot must be non-interactive after failed activation")
      ;;     (d) Scene surface aliases are cleared
      (assert (= scene.entity nil)
              "Scene.entity must be nil after rollback")
      (assert (= scene.scene-children nil)
              "Scene.scene-children must be nil after rollback")
      (assert (= scene.scene-terrains nil)
              "Scene.scene-terrains must be nil after rollback")
      ;;     (e) Active slot binding is nil
      (assert (= scene.active-activity-slot nil)
              "Scene.active-activity-slot must be nil after rollback")
      (assert (= scene.active-activity-slot-id nil)
              "Scene.active-activity-slot-id must be nil after rollback")
      ;;     (f) Layout physics deactivation occurred:
      ;;         wrapper was invoked AND removeRigidBody fired (body was active)
      (assert physics-deactivate-called
              "LayoutPhysicsBodies.deactivate must have been called during rollback")
      (assert remove-rigid-body-called
              "app.engine.physics:removeRigidBody must have been called during physics deactivation")
      (assert (not entry.body-active?)
              "Entry.body-active? must be false after deactivation")

      ;; Restore mock
      (set LayoutPhysicsBodies.deactivate orig-deactivate)
      (drop-fixture fixture))))

(table.insert tests {:name "R4-3d corrupt activation preserves retained slot content"
                     :fn corrupt-activation-preserves-retained-slot-content})

;; ── R7-1 active restore reconciles terrains ─────────────────────────────

(fn active-restore-removes-stale-terrains []
  "R7-1: When an active slot is restored with canonical terrain state
  that has fewer terrains than runtime, the absent terrains must be
  removed from runtime.  When a terrain record changes (different data
  for the same id), the runtime entry must be replaced."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :renderers :engine]
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
      (local slot (scene:ensure-activity-slot "sandbox"))

      ;; Activate empty slot
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Slot should be active before restore")

      ;; (1) Restore state with two terrains: A and B
      (local state-1 (ActivitySceneState.empty-state))
      (set state-1.terrains
           [(make-heightfield-terrain-record {:id "t-a"})
            (make-heightfield-terrain-record {:id "t-b"})])
      (assert (scene:restore-activity-slot-state "sandbox" state-1)
              "First restore should return true")
      (assert (= (length slot.scene-terrains) 2)
              (.. "After first restore: expected 2 terrains, got "
                  (tostring (length slot.scene-terrains))))

      ;; (2) Restore state with only terrain B (A removed)
      (local state-2 (ActivitySceneState.empty-state))
      (set state-2.terrains [(make-heightfield-terrain-record {:id "t-b"})])
      (assert (scene:restore-activity-slot-state "sandbox" state-2)
              "Second restore (remove A) should return true")
      (assert (= (length slot.scene-terrains) 1)
              (.. "After second restore (remove A): expected 1 terrain, got "
                  (tostring (length slot.scene-terrains))))
      ;; Verify that terrain A is gone and terrain B remains
      (local remaining-id (and (. slot.scene-terrains 1)
                               (. (. slot.scene-terrains 1) :record)
                               (. (. (. slot.scene-terrains 1) :record) :id)))
      (assert (= remaining-id "t-b")
              (.. "After second restore, remaining terrain should be t-b, got "
                  (tostring remaining-id)))

      ;; (3) Restore state with terrain B but with different height (changed record)
      (local state-3 (ActivitySceneState.empty-state))
      (set state-3.terrains
           [(make-heightfield-terrain-record {:id "t-b" :default-height 5.0})])
      (assert (scene:restore-activity-slot-state "sandbox" state-3)
              "Third restore (change B) should return true")
      (assert (= (length slot.scene-terrains) 1)
              (.. "After third restore (change B): expected 1 terrain, got "
                  (tostring (length slot.scene-terrains))))
      ;; Verify that the record was captured with the new height
      (assert slot.scene-state.terrains
              "slot.scene-state.terrains should exist after restore")
      (local captured-record (. slot.scene-state.terrains 1))
      (assert captured-record "Captured terrain record should exist")
      (assert (= (. (or captured-record.options {}) :default-height) 5.0)
              (.. "Captured terrain should have updated height 5.0, got "
                  (tostring (. (or captured-record.options {}) :default-height))))

      ;; (4) Restore with empty terrain list — all runtime terrains must be cleared
      (local state-4 (ActivitySceneState.empty-state))
      (set state-4.terrains [])
      (assert (scene:restore-activity-slot-state "sandbox" state-4)
              "Fourth restore (empty) should return true")
      (assert (or (not slot.scene-terrains) (= (length (or slot.scene-terrains [])) 0))
              (.. "After fourth restore (empty): expected 0 runtime terrains, got "
                  (tostring (length (or slot.scene-terrains [])))))

      (drop-fixture fixture))))
(table.insert tests {:name "R7-1 active restore removes stale and replaces changed terrains"
                      :fn active-restore-removes-stale-terrains})

;; ── R7-1b active restore captures generated terrain id ───────────────────

(fn active-restore-captures-generated-terrain-id []
  "R7-1: When an active empty slot is restored from a terrain record
  without an explicit id, the generated terrain id must be captured back
  into slot.scene-state.terrains, and a repeat restore must remain
  idempotent (no duplicate terrain entries)."
  (with-restored-app-fields
    [:skybox-state :background-state :lights-state :renderers :engine]
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
      (local slot (scene:ensure-activity-slot "sandbox"))

      ;; Activate empty slot
      (scene:activate-activity-slot "sandbox")
      (assert slot.visible? "Slot should be active before restore")

      ;; (1) Restore with a terrain record that has NO explicit id
      (local state (ActivitySceneState.empty-state))
      (set state.terrains [{:kind "heightfield-terrain"}])
      (assert (scene:restore-activity-slot-state "sandbox" state)
              "First restore should return true")

      ;; (2) Assert the generated terrain id was captured back into
      ;;     slot.scene-state.terrains
      (assert slot.scene-state
              "slot.scene-state should exist after restore")
      (assert slot.scene-state.terrains
              "slot.scene-state.terrains should exist after restore")
      (assert (= (length slot.scene-state.terrains) 1)
              (.. "slot.scene-state.terrains should have 1 entry, got "
                  (tostring (length slot.scene-state.terrains))))
      (local captured-id (. slot.scene-state.terrains 1 :id))
      (assert (and captured-id (= (type captured-id) :string) (> (string.len captured-id) 0))
              (.. "slot.scene-state.terrains[1].id must be a generated non-empty string after restore, got "
                  (tostring captured-id)))

      ;; (3) Assert runtime terrains have exactly one entry
      (assert slot.scene-terrains
              "slot.scene-terrains should have runtime terrain after restore")
      (assert (= (length slot.scene-terrains) 1)
              (.. "slot.scene-terrains should have 1 runtime entry, got "
                  (tostring (length slot.scene-terrains))))

      ;; (4) Second restore with same state must remain idempotent
      (assert (scene:restore-activity-slot-state "sandbox" state)
              "Second restore should return true")
      (assert (= (length slot.scene-terrains) 1)
              (.. "After second restore: expected exactly 1 terrain (idempotent), got "
                  (tostring (length slot.scene-terrains))))
      (assert (= (length slot.scene-state.terrains) 1)
              (.. "After second restore: canonical terrains count must still be 1, got "
                  (tostring (length slot.scene-state.terrains))))
      ;; The id should be stable across repeated restores
      (local second-id (. slot.scene-state.terrains 1 :id))
      (assert (= second-id captured-id)
              (.. "Terrain id must be stable across repeated restores (got " (tostring second-id) " expected " (tostring captured-id) ")"))

      (drop-fixture fixture))))

(table.insert tests {:name "R7-1b active restore captures generated terrain id"
                     :fn active-restore-captures-generated-terrain-id})

;; ── Task 7: Empty scene slot service leakage ─────────────────────────

(fn empty-scene-slot-applies-empty-services-without-render-target []
  "Task 7: An empty drawing scene slot activated after sandbox (with
  non-empty lights, skybox, background, and containment) must reset all
  engine services to the canonical empty state so sandbox service state
  does not leak through the scene surface."
  (with-restored-app-fields
    [:lights :renderers :engine]
    (fn []
      (local ActivitySceneState (require :activity-scene-state))
      (local SkyboxState (require :skybox-state))
      (local BackgroundState (require :background-state))
      (local PhysicsContainment (require :physics-containment))
      (local AppProjection (require :app-projection))
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))

      ;; Derive expected empty service state shapes
      (local empty (ActivitySceneState.empty-state))
      (local expected-empty-lights empty.lights)
      ;; Resolved format: what the renderer actually receives after
      ;; apply-slot-service-state resolves the complete skybox for the
      ;; current theme (nil = no active theme = use :default).
      (local expected-empty-skybox
        (SkyboxState.resolve-for-theme empty.skybox nil))
      ;; Background is already in its normalized complete form.
      (local expected-empty-background empty.background)
      ;; Containment is already serialized by empty-containment.
      (local expected-empty-containment empty.containment)

      ;; Mock lights — captures the last set state
      (var lights-state {:ambient {:enabled? false :color [0 0 0] :intensity 0.0}
                         :directional []
                         :point []
                         :spot []})
      (set app.lights {:set-state (fn [_self state] (set lights-state state))
                       :get-state (fn [_self] lights-state)})

      ;; Mock renderer skybox / background — captures last set state
      (var skybox-state {:enabled? false
                         :name "lake"
                         :brightness 0.1
                         :tint-color [1.0 1.0 1.0]})
      (var background-state {:color [0 0 0]})
      (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                                   :set-state (fn [_ state] (set skybox-state state))}
                          :get-background-state (fn [_] background-state)
                          :set-background-state (fn [_ state] (set background-state state))})

      ;; Mock physics for containment
      (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                  :removeRigidBody (fn [_phys _body])}})

      (local fixture (make-scene))
      (local scene fixture.scene)

      ;; (1) Activate sandbox with non-empty service state (enabled lights,
      ;;     enabled skybox, custom background, enabled containment).
      (scene:ensure-activity-slot "sandbox")
      (local sandbox-state
        {:panels []
         :terrains []
         :lights {:ambient {:enabled? true :color [0.9 0.8 0.7] :intensity 2.0}
                  :directional []
                  :point []
                  :spot []}
         :skybox {:enabled? true
                  :name "ocean"
                  :brightness 0.75
                  :tint-color [0.5 0.6 1.0]}
         :background {:color [0.1 0.2 0.3]}
         :containment {:enabled? true}})
      (scene:restore-activity-slot-state "sandbox" sandbox-state)
      (scene:activate-activity-slot "sandbox")

      ;; Verify sandbox services were applied (sanity check)
      (assert lights-state.ambient.enabled?
              "Sandbox activation must enable ambient light")
      (assert skybox-state.enabled?
              "Sandbox activation must enable skybox")
      (assert (= skybox-state.brightness 0.75)
              "Sandbox activation must apply skybox brightness")
      (local sandbox-slot (scene:activity-slot "sandbox"))
      (assert (and sandbox-slot.physics-containment-manager
                   sandbox-slot.physics-containment-manager.config
                   sandbox-slot.physics-containment-manager.config.enabled?)
              "Sandbox slot must have enabled containment")

      ;; (2) Switch to drawing — the empty slot must reset all services.
      (local drawing-slot (scene:ensure-activity-slot "drawing"))
      (scene:activate-activity-slot "drawing")

      ;; ── Lights: compare observed against expected empty lights ──────
      (assert (not lights-state.ambient.enabled?)
              (.. "ambient must be disabled, expected "
                  (tostring expected-empty-lights.ambient.enabled?)))
      (assert (= (length lights-state.directional)
                 (length expected-empty-lights.directional))
              (.. "directional array length mismatch, expected "
                  (tostring (length expected-empty-lights.directional))))
      (assert (= (length lights-state.point)
                 (length expected-empty-lights.point))
              (.. "point array length mismatch, expected "
                  (tostring (length expected-empty-lights.point))))
      (assert (= (length lights-state.spot)
                 (length expected-empty-lights.spot))
              (.. "spot array length mismatch, expected "
                  (tostring (length expected-empty-lights.spot))))
      ;; Compare ambient color components
      (each [idx expected-v (ipairs expected-empty-lights.ambient.color)]
        (assert (<= (math.abs (- (. lights-state.ambient.color idx) expected-v)) 0.01)
                (.. "ambient.color[" (tostring idx) "] mismatch, expected "
                    (tostring expected-v) " got "
                    (tostring (. lights-state.ambient.color idx)))))
      ;; Compare ambient intensity
      (assert (<= (math.abs (- (. lights-state.ambient.intensity)
                               expected-empty-lights.ambient.intensity)) 0.01)
              (.. "ambient.intensity mismatch, expected "
                  (tostring expected-empty-lights.ambient.intensity) " got "
                  (tostring (. lights-state.ambient.intensity))))

      ;; ── Skybox: compare observed against resolved empty skybox ─────
      (assert (= skybox-state.enabled? expected-empty-skybox.enabled?)
              (.. "skybox enabled? mismatch, expected "
                  (tostring expected-empty-skybox.enabled?) " got "
                  (tostring skybox-state.enabled?)))
      (assert (= skybox-state.name expected-empty-skybox.name)
              (.. "skybox name mismatch, expected "
                  (tostring expected-empty-skybox.name) " got "
                  (tostring skybox-state.name)))
      (assert (<= (math.abs (- skybox-state.brightness
                               expected-empty-skybox.brightness)) 0.01)
              (.. "skybox brightness mismatch, expected "
                  (tostring expected-empty-skybox.brightness) " got "
                  (tostring skybox-state.brightness)))
      (each [idx expected-v (ipairs expected-empty-skybox.tint-color)]
        (assert (<= (math.abs (- (. skybox-state.tint-color idx) expected-v)) 0.01)
                (.. "skybox tint-color[" (tostring idx) "] mismatch, expected "
                    (tostring expected-v) " got "
                    (tostring (. skybox-state.tint-color idx)))))

      ;; ── Background: compare observed against canonical empty bg ────
      (each [idx expected-v (ipairs expected-empty-background.color)]
        (assert (<= (math.abs (- (. background-state.color idx) expected-v)) 0.01)
                (.. "background.color[" (tostring idx) "] mismatch, expected "
                    (tostring expected-v) " got "
                    (tostring (. background-state.color idx)))))

      ;; ── Containment: compare manager.config against empty containment ─
      (assert drawing-slot.physics-containment-manager
              "Drawing slot should have a containment manager after activation")
      (local drawing-config drawing-slot.physics-containment-manager.config)
      (assert drawing-config "Drawing containment manager must have config")
      (assert (= drawing-config.enabled? expected-empty-containment.enabled?)
              (.. "containment enabled? mismatch, expected "
                  (tostring expected-empty-containment.enabled?) " got "
                  (tostring drawing-config.enabled?)))

      ;; ── Presentation target and slot state ──────────────────────────
      (assert (= (scene:presentation-target) nil)
              "Empty drawing scene slot must not expose a render target")
      (assert drawing-slot.scene-state
              "Empty slot must own explicit empty service state")

      (drop-fixture fixture))))

(table.insert tests {:name "Task 7: empty scene slot applies empty services without render target"
                     :fn empty-scene-slot-applies-empty-services-without-render-target})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-activity-slots"
                       :tests tests})))

{:name "scene-activity-slots"
 :tests tests
 :main main}
