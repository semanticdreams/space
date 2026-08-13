(local tests [])
(local _ (require :main))
(local Activities (require :activities))
(local ActivitySceneState (require :activity-scene-state))

;; Ensure the sandbox activity unit is loaded before tests run
(local sandbox-unit (require :sandbox-activity-unit))
(local _sandbox-actions (pcall require :sandbox-activity-actions))

(fn ensure-built-in-activities! []
  (local registry (Activities.ensure-registry))
  (when (not (. registry.activities "sandbox"))
    (sandbox-unit.load-sandbox-activity!))
  (when (not (. registry.activities "graph"))
    (Activities.register-activity
      {:id "graph"
       :label "Graph"
       :icon "account_tree"
       :button-name "graph-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "graph"})
       :deactivate (fn [_ctx _session] true)}))
  (when (not (. registry.activities "drawing"))
    (Activities.register-activity
      {:id "drawing"
       :label "Draw"
       :icon "draw"
       :button-name "drawing-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "drawing"})
       :deactivate (fn [_ctx _session] true)}))
  (when (not (. registry.activities "board"))
    (Activities.register-activity
      {:id "board"
       :label "Board"
       :icon "grid_view"
       :button-name "board-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "board"})
       :deactivate (fn [_ctx _session] true)}))
   true)

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn restore-table! [target snapshot]
  (each [k _v (pairs target)]
    (set (. target k) nil))
  (each [k v (pairs snapshot)]
    (set (. target k) (clone-table v)))
  target)

(fn with-restored-app [fields f]
  (local snapshot {})
  (local registry-key :activity-registry)
  (local registry-ref app.activity-registry)
  (local registry-snapshot (clone-table registry-ref))
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (if registry-ref
      (do
        (restore-table! registry-ref registry-snapshot)
        (tset app registry-key registry-ref))
      (tset app registry-key nil))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
  (if ok result (error result)))

(fn with-restored-app-restores-registry-owner []
  (local original-registry app.activity-registry)
  (set app.activity-registry {:active-activity-id nil})
  (local (ok result)
    (pcall
      (fn []
        (with-restored-app []
          (fn []
            (local registry app.activity-registry)
            (set registry.active-activity-id "sandbox")
            true))
        (assert (= app.activity-registry.active-activity-id nil)
                "with-restored-app must restore nested registry owner state"))))
  (set app.activity-registry original-registry)
  (if ok result (error result)))

(fn make-mock-scene []
  (local slots {})
  (var active-slot-id nil)
  (fn ensure-activity-slot [_self activity-id]
    (when (not (. slots activity-id))
      (set (. slots activity-id)
           {:activity-id activity-id
            :scene-state nil
            :visible? false
            :interactive? false
            :camera nil
            :controls nil
            :render-target-spec nil
            :physics-containment-manager nil
            :set-camera (fn [self camera] (set self.camera camera) self)
            :set-controls (fn [self controls] (set self.controls controls) self)
            :expose-render-target! (fn [self opts] (set self.render-target-spec opts) self)
            :clear-render-target! (fn [self] (set self.render-target-spec nil) self)}))
    (. slots activity-id))
  (fn activate-activity-slot [_self activity-id]
    (local slot (ensure-activity-slot _self activity-id))
    (when active-slot-id
      (set (. slots active-slot-id :visible?) false)
      (set (. slots active-slot-id :interactive?) false))
    (set active-slot-id activity-id)
    (set slot.visible? true)
    (set slot.interactive? true)
    slot)
  (fn deactivate-activity-slot [_self activity-id]
    (local slot (. slots activity-id))
    (when slot
      (set slot.visible? false)
      (set slot.interactive? false))
    (set active-slot-id nil)
    slot)
  (fn restore-activity-slot-state [_self activity-id state]
    (local slot (ensure-activity-slot _self activity-id))
    (set slot.scene-state state))
  (fn capture-activity-slot-state [_self activity-id]
    (local slot (. slots activity-id))
    (and slot slot.scene-state))
  (fn activity-slot [_self activity-id]
    (. slots activity-id))
  {:ensure-activity-slot ensure-activity-slot
   :activity-slot activity-slot
   :activate-activity-slot activate-activity-slot
   :deactivate-activity-slot deactivate-activity-slot
   :restore-activity-slot-state restore-activity-slot-state
   :capture-activity-slot-state capture-activity-slot-state
   :slots slots
   :active-slot-id (fn [_] active-slot-id)})

;; ---------------------------------------------------------------------------
;; Test: sandbox activity spec is registered
;; ---------------------------------------------------------------------------
(fn sandbox-activity-unit-registers-spec []
  (ensure-built-in-activities!)
  (local spec (Activities.spec "sandbox"))
  (assert spec "Sandbox activity spec must be registered")
  (assert (= spec.id "sandbox")
          "Sandbox activity id must be 'sandbox'")
  (assert (= spec.label "Sandbox")
          "Sandbox activity label must be 'Sandbox'")
  (assert (= spec.icon "toys")
          "Sandbox activity icon must be 'toys'")
  (assert (= spec.button-name "sandbox-activity")
          "Sandbox activity button-name must be 'sandbox-activity'")
  (assert (= spec.show-in-switcher? true)
          "Sandbox activity must be shown in activity switcher")
  (assert (= (type spec.activate) :function)
          "Sandbox activity must have activate function")
  (assert (= (type spec.deactivate) :function)
          "Sandbox activity must have deactivate function")
  (assert (= (type spec.snapshot) :function)
          "Sandbox activity must have snapshot function")
  (assert (= (type spec.restore) :function)
          "Sandbox activity must have restore function")
  true)

;; ---------------------------------------------------------------------------
;; Test: activation sets scene-preferred interaction surface
;; ---------------------------------------------------------------------------
(fn sandbox-activation-sets-scene-interaction-surface []
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                     :activity-session-state
                                     {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      ;; Deactivate any lingering activity before activation
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      ;; Activate the sandbox activity
      (Activities.activate-activity "sandbox")
      ;; Verify interaction surface
      (assert (= app.activity-preferred-interaction-surface :scene)
              "Sandbox activation must set preferred interaction surface to :scene")
      (assert (= app.activity-surface-state.canvas.visible? false)
              "Sandbox activation must hide canvas")
      true)))

;; ---------------------------------------------------------------------------
;; Test: activation installs root actions
;; ---------------------------------------------------------------------------
(fn sandbox-activation-installs-root-actions []
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                     :activity-session-state
                                     {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      ;; Verify root actions are installed
      (assert (= (type app.activity-root-actions) :function)
              "Sandbox activation must install root actions function")
      (local context {:scene {:scene mock-scene}})
      (local actions (app.activity-root-actions context))
      (assert (= (type actions) :table)
              "Sandbox root actions must return a table")
      (assert (> (length actions) 0)
              "Sandbox root actions must not be empty")
      true)))

;; ---------------------------------------------------------------------------
;; Test: activation installs update hook
;; ---------------------------------------------------------------------------
(fn sandbox-activation-installs-update-hook []
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                     :activity-session-state
                                     {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      (assert (= (type app.activity-update) :function)
              "Sandbox activation must install update hook")
      true)))

;; ---------------------------------------------------------------------------
;; Test: activation installs target-enabled predicate
;; ---------------------------------------------------------------------------
(fn sandbox-activation-installs-target-predicate []
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                     :activity-session-state
                                     {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      (assert (= (type app.activity-target-enabled?) :function)
              "Sandbox activation must install target predicate")
      true)))

;; ---------------------------------------------------------------------------
;; Test: panel hydration processes one panel per frame
;; ---------------------------------------------------------------------------
(fn sandbox-panel-hydration-one-per-frame []
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :engine]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      ;; Track panel restoration
      (var restored-panels [])
      (set mock-scene.restore-panel-state
           (fn [_self panel index]
             (table.insert restored-panels {:panel panel :index index})))
      (set mock-scene.sync-scene-objects (fn [_self] nil))
      ;; Mock engine for timing
      (var now-ms 0)
      (set app.engine {:now-ms (fn [_self]
                                 (set now-ms (+ now-ms 16))
                                 now-ms)})
      ;; Set up runtime with hydration queue
      (local session-state {:scene (ActivitySceneState.empty-state)})
      (set session-state.scene.panels
           [{:kind "test-panel-1" :position [1 2 3]}
            {:kind "test-panel-2" :position [4 5 6]}
            {:kind "test-panel-3" :position [7 8 9]}])
      (set app.active-world-runtime
           {:scene mock-scene
            :activity-session-state {:sandbox session-state}
            :hydration {:scene-panels [{:kind "test-panel-1" :position [1 2 3]}
                                       {:kind "test-panel-2" :position [4 5 6]}
                                       {:kind "test-panel-3" :position [7 8 9]}]
                        :scene-panel-index 1
                        :phase "scene-panels"
                        :ready? true
                        :started? false
                        :completed? false}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      ;; Activate sandbox
      (Activities.activate-activity "sandbox")
      (assert (= (type app.activity-update) :function)
              "Update hook must be installed")
      ;; Call update with world in payload (needed for physics pause sync)
      (local world {:id "test-world" :active? true})
      ;; First update: should restore first panel
      (app.activity-update {:runtime app.active-world-runtime
                            :world world
                            :delta 0.016})
      (assert (= (length restored-panels) 1) "First update should restore 1 panel")
      (assert (= (. restored-panels 1 :panel :kind) "test-panel-1") "First panel should be panel 1")
      ;; Second update: should restore second panel
      (app.activity-update {:runtime app.active-world-runtime
                            :world world
                            :delta 0.016})
      (assert (= (length restored-panels) 2) "Second update should restore 2 panels total")
      (assert (= (. restored-panels 2 :panel :kind) "test-panel-2") "Second panel should be panel 2")
      ;; Third update: should restore third panel
      (app.activity-update {:runtime app.active-world-runtime
                            :world world
                            :delta 0.016})
      (assert (= (length restored-panels) 3) "Third update should restore 3 panels total")
      (assert (= (. restored-panels 3 :panel :kind) "test-panel-3") "Third panel should be panel 3")
      ;; Fourth update: all panels restored, should complete
      (app.activity-update {:runtime app.active-world-runtime
                            :world world
                            :delta 0.016})
      (assert (= (length restored-panels) 3) "Fourth update should not add more panels")
      (assert (= app.active-world-runtime.hydration.completed? true)
              "Hydration should be marked complete after all panels")
      (assert (= app.active-world-runtime.hydration.phase "complete")
              "Hydration phase should be 'complete'")
      true)))

;; ---------------------------------------------------------------------------
;; Test: switch retention — sandbox retains state across activity switches
;; ---------------------------------------------------------------------------
(fn sandbox-retains-state-across-switches []
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-interaction-surface
     :canvas-visible?
     :active-activity-id
     :canvas]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                     :activity-session-state
                                     {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (set app.canvas {:activate-activity-slot (fn [_self _id] {})})
      ;; Ensure clean activity state before test
      (when (not (= (Activities.active-activity-id) nil))
        (Activities.deactivate-active-activity))
      ;; Activate sandbox and verify slot is active via mock-scene
      (local (ok err) (pcall (fn [] (Activities.activate-activity "sandbox"))))
      (assert ok (.. "Sandbox activation should not error: " (tostring err)))
      (local sandbox-slot-id (mock-scene:active-slot-id))
      ;; If sandbox-slot-id is not a string, show its type for debugging
      (assert (= (type sandbox-slot-id) :string)
              (.. "Expected string slot id, got " (type sandbox-slot-id)))
      (assert (= sandbox-slot-id "sandbox")
              "Sandbox slot must be active after activation")
      ;; Deactivate and switch to graph
      (Activities.activate-activity "graph")
      ;; Sandbox slot should be deactivated (not dropped)
      (assert (not (. mock-scene.slots "sandbox" :visible?))
              "Sandbox slot must be hidden after graph activation")
      (assert (. mock-scene.slots "sandbox")
              "Sandbox slot must not be dropped")
      ;; Switch back to sandbox
      (Activities.activate-activity "sandbox")
      ;; Sandbox slot should be active again
      (assert (. mock-scene.slots "sandbox" :visible?)
              "Sandbox slot must be visible after reactivation")
      (assert (= (mock-scene:active-slot-id) "sandbox")
              "Sandbox slot must be active after reactivation")
      true)))

;; ---------------------------------------------------------------------------
;; Test: sandbox activity actions includes expected scene root actions
;; ---------------------------------------------------------------------------
(fn sandbox-activity-actions-includes-scene-root-actions []
  (local SandboxActivityActions (require :sandbox-activity-actions))
  (assert SandboxActivityActions.sandbox-root-actions
          "sandbox-activity-actions must export sandbox-root-actions")
  (assert (= (type SandboxActivityActions.sandbox-root-actions) :function)
          "sandbox-root-actions must be a function")
  ;; Call with a mock scene context
  (local mock-scene {:add-demo-browser (fn [_self] nil)
                     :add-physics-body (fn [_self] nil)
                     :add-object (fn [_self _obj] nil)
                     :add-light-ball (fn [_self _opts] nil)})
  (local context {:scene {:scene mock-scene}})
  (local actions (SandboxActivityActions.sandbox-root-actions context))
  (assert (= (type actions) :table)
          "sandbox-root-actions must return a table of actions")
  (assert (> (length actions) 0)
          "sandbox-root-actions must return non-empty actions list")
  ;; Verify specific actions exist
  (local action-names {})
  (each [_ action (ipairs actions)]
    (set (. action-names action.name) true))
  (assert (. action-names "Demo Browser")
          "Actions must include 'Demo Browser'")
  (assert (. action-names "add cuboid")
          "Actions must include 'add cuboid'")
  (assert (. action-names "ball")
          "Actions must include 'ball'")
  (assert (. action-names "Add light ball")
          "Actions must include 'Add light ball'")
  (assert (. action-names "Recover Terrain-Bound Objects")
          "Actions must include 'Recover Terrain-Bound Objects'")
  true)

;; ---------------------------------------------------------------------------
;; Test: root context menu delegates scene actions to sandbox
;; ---------------------------------------------------------------------------
(fn root-context-menu-delegates-scene-actions-to-sandbox []
  (local RootContextMenuActions (require :root-context-menu-actions))
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :active-interaction-surface]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                     :activity-session-state
                                     {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene {:add-physics-body (fn [_self] :cuboid-added)
                      :add-demo-browser (fn [_self] :browser-added)
                      :add-object (fn [_self _obj] :ball-added)
                      :add-light-ball (fn [_self _opts] :light-added)})
      (set app.active-interaction-surface :scene)
      ;; Activate sandbox
      (when (not (= (Activities.active-activity-id) nil))
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      ;; Verify state
      (assert (= (Activities.active-activity-id) "sandbox")
              "Sandbox should be active")
      (assert (= (type app.activity-root-actions) :function)
              "Root actions should be installed")
      ;; Build context and get actions
      (local context (RootContextMenuActions.build-context nil))
      (assert (= context.surface :scene)
              "Context surface should be :scene")
      (assert (= context.activity "sandbox")
              (.. "Context activity should be sandbox, got " (tostring context.activity)))
      ;; Diagnostic: check both conditions that activity-root-actions uses
      (local registry-active-id (Activities.active-activity-id))
      (assert (= (type app.activity-root-actions) :function)
              "app.activity-root-actions should still be a function before actions-for-context")
      (assert (= registry-active-id context.activity)
              (.. "Registry active-id should equal context.activity. registry="
                  (tostring registry-active-id) " context=" (tostring context.activity)))
      ;; Directly test app.activity-root-actions
      (local direct-actions (app.activity-root-actions {:scene {:scene app.scene}}))
      (assert (= (type direct-actions) :table)
              "Direct call to activity-root-actions should return a table")
      (assert (> (length direct-actions) 0)
              "Direct call to activity-root-actions should return non-empty actions")
      (local direct-names {})
      (each [_ action (ipairs direct-actions)]
        (set (. direct-names action.name) true))
      (assert (. direct-names "add cuboid")
              "Direct call should include 'add cuboid'")
      ;; Also check through context
      (local actions (RootContextMenuActions.actions-for-context context))
      (assert (= (type actions) :table)
              "actions-for-context should return a table")
      (assert (> (length actions) 0)
              "actions-for-context should return non-empty actions")
      ;; Verify specific actions
      (local action-names {})
      (each [_ action (ipairs actions)]
        (set (. action-names action.name) true))
      (assert (. action-names "add cuboid")
              "actions should include 'add cuboid'")
      (assert (. action-names "ball")
              "actions should include 'ball'")
      (assert (. action-names "Demo Browser")
              "actions should include 'Demo Browser'")
      true)))

;; ---------------------------------------------------------------------------
;; R1-1: snapshot preserves remaining hydration queue panels
;; ---------------------------------------------------------------------------
(fn sandbox-snapshot-preserves-remaining-hydration-panels []
  "When snapshotted mid-hydration, the sandbox session scene must include
  both already-hydrated panels and the panels still queued in runtime.hydration."
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :engine]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      ;; Mock scene capture: return the currently accumulated scene-state
      (local empty-svc (ActivitySceneState.empty-state))
      (var captured-state {:panels [{:kind "hydrated-panel-0" :position [0 0 0]}]
                           :lights empty-svc.lights
                           :skybox empty-svc.skybox
                           :background empty-svc.background
                           :containment empty-svc.containment
                           :terrains []})
      (set mock-scene.capture-activity-slot-state
           (fn [_self _activity-id]
             captured-state))
      ;; Mock engine for timing
      (var now-ms 0)
      (set app.engine {:now-ms (fn [_self] (set now-ms (+ now-ms 16)) now-ms)})
      ;; Set up runtime with partially-consumed hydration queue:
      ;; 3 panels total, index 3 means panels 1-2 are hydrated, panel 3 is remaining
      (set app.active-world-runtime
           {:scene mock-scene
            :hydration {:scene-panels [{:kind "queued-panel-1" :position [1 0 0]}
                                       {:kind "queued-panel-2" :position [2 0 0]}
                                       {:kind "queued-panel-3" :position [3 0 0]}]
                        :scene-panel-index 3
                        :phase "scene-panels"
                        :ready? true
                        :started? true
                        :completed? false}})
      (set app.scene mock-scene)
      (when (not (= (Activities.active-activity-id) nil))
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      ;; Snapshot mid-hydration
      (local snapshot-result (sandbox-unit.snapshot-sandbox-activity!))
      (assert (= (type snapshot-result) :table)
              "Snapshot must return a table")
      (assert (= (type snapshot-result.scene) :table)
              "Snapshot must have :scene key")
      (assert (= (type snapshot-result.scene.panels) :table)
              "Snapshot scene must have panels")
      ;; Should contain: the already-hydrated panel (from captured-state)
      ;; PLUS the remaining hydration panel (queued-panel-3 at index 3)
      (assert (>= (length snapshot-result.scene.panels) 2)
              (.. "Expected at least 2 panels in snapshot (hydrated + remaining), got "
                  (tostring (length snapshot-result.scene.panels))))
      (local kinds {})
      (each [_ panel (ipairs snapshot-result.scene.panels)]
        (set (. kinds panel.kind) true))
      (assert (. kinds "hydrated-panel-0")
              "Snapshot must preserve already-hydrated panel")
      (assert (. kinds "queued-panel-3")
              "Snapshot must include remaining hydration panel at current index")
      true)))

;; ---------------------------------------------------------------------------
;; R1-2: sandbox deactivation resets services to empty when no successor slot
;; ---------------------------------------------------------------------------
(fn sandbox-deactivation-resets-services-when-no-successor []
  "When sandbox deactivates and no successor Scene slot activates,
  the global lights/skybox/background/containment must be reset to empty
  so they don't leak sandbox state into other activities.
  Exercises the real Scene:deactivate-activity-slot last-slot path."
  ;; Collect the module names we will mock so we can restore them correctly
  ;; regardless of whether they were originally in package.loaded or not.
  (local mocked-modules [:physics-containment :layout-physics-bodies])
  ;; Save originals, tracking nil vs non-nil
  (local originals {})
  (each [_ name (ipairs mocked-modules)]
    (set (. originals name) (. package.loaded name)))
  ;; Install mock PhysicsContainment that records calls precisely while
  ;; delegating all real module functionality.
  (var containment-calls [])
  (local real-physics-containment (require :physics-containment))
  (set (. package.loaded :physics-containment)
       {:available? real-physics-containment.available?
        :default-mode real-physics-containment.default-mode
        :default-manual-bounds real-physics-containment.default-manual-bounds
        :default-padding real-physics-containment.default-padding
        :default-restitution real-physics-containment.default-restitution
        :default-debounce-ms real-physics-containment.default-debounce-ms
        :default-visualization real-physics-containment.default-visualization
        :default-config real-physics-containment.default-config
        :normalize-config real-physics-containment.normalize-config
        :serialize-config real-physics-containment.serialize-config
        :automatic-terrain-bounds real-physics-containment.automatic-terrain-bounds
        :resolve-active-bounds real-physics-containment.resolve-active-bounds
        :create-manager (fn [opts]
                          (local real-manager (real-physics-containment.create-manager opts))
                          ;; Wrap manager methods to record calls
                          (local orig-ensure-installed real-manager.ensure-installed)
                          (local orig-clear real-manager.clear)
                          (set real-manager.ensure-installed
                               (fn [self install-opts]
                                 (table.insert containment-calls {:ensure-installed install-opts})
                                 (orig-ensure-installed self install-opts)))
                          (set real-manager.clear
                               (fn [self]
                                 (table.insert containment-calls :clear)
                                 (orig-clear self)))
                          real-manager)})
  ;; Install mock LayoutPhysicsBodies that records deactivation calls
  (var physics-deactivate-calls [])
  (set (. package.loaded :layout-physics-bodies)
       {:deactivate (fn [entity]
                      (table.insert physics-deactivate-calls entity)
                      true)})
  (local (ok result)
    (pcall
      (fn []
        (local Camera (require :camera))
        (local glm (require :glm))
        (local Scene (require :scene))
        (with-restored-app
          [:active-world-runtime
           :scene
           :activity-root-actions
           :activity-target-enabled?
           :activity-update
           :activity-preferred-interaction-surface
           :activity-surface-state
           :canvas-surface-interactive?
           :activity-context-enricher
           :active-activity-id
           :lights
           :renderers
           :physics-containment-config
           :physics-containment-scene
           :engine
           :create-default-projection]
          (fn []
            (ensure-built-in-activities!)
            ;; Set up minimum app globals required by real Scene constructor
            (local AppProjection (require :app-projection))
            (when (not app.create-default-projection)
              (set app.create-default-projection AppProjection.create-default-projection))
            ;; Minimal physics mock required by slot containment manager creation
            (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                                        :removeRigidBody (fn [_phys _body])}})
            ;; Create a real Scene with a Camera so the real
            ;; deactivate-activity-slot path is exercised.
            (local camera (Camera {:position (glm.vec3 0 0 100)}))
            (local real-scene (Scene {:camera camera}))
            ;; Install mock global services
            (var lights-reset-calls [])
            (var skybox-reset-calls [])
            (var background-reset-calls [])
            (set app.lights {:set-state (fn [_self state] (table.insert lights-reset-calls state))})
            (set app.renderers
                 {:skybox {:set-state (fn [_self state] (table.insert skybox-reset-calls state))}
                  :set-background-state (fn [_self state] (table.insert background-reset-calls state))})
            ;; Set up runtime with the real Scene
            ;; Set up runtime with sandbox session
            (set app.active-world-runtime
                 {:scene real-scene
                  :activity-session-state
                  {:sandbox {:scene (ActivitySceneState.empty-state)}}})
            (set app.scene real-scene)
            (when (not (= (Activities.active-activity-id) nil))
              (Activities.deactivate-active-activity))
            ;; Activate sandbox (calls real Scene.activate-activity-slot)
            (Activities.activate-activity "sandbox")
            (assert (. real-scene.activity-slots "sandbox")
                    "Sandbox slot must exist on real Scene")
            (assert real-scene.active-activity-slot
                    "Real Scene must have an active slot after sandbox activation")
            ;; Manually set an entity on the slot so the real
            ;; Scene:deactivate-activity-slot path exercises the
            ;; LayoutPhysicsBodies.deactivate branch.
            (set real-scene.entity {:id "sandbox-root"})
            (set (. real-scene.activity-slots "sandbox" :entity) {:id "sandbox-root"})
            ;; Track pre-deactivation call counts
            (local pre-lights-count (length lights-reset-calls))
            (local pre-skybox-count (length skybox-reset-calls))
            (local pre-background-count (length background-reset-calls))
            (local pre-containment-count (length containment-calls))
            (local pre-physics-count (length physics-deactivate-calls))
            ;; Deactivate sandbox — exercises the real Scene:deactivate-activity-slot
            ;; path which now includes the LayoutPhysicsBodies.deactivate fix.
            (Activities.deactivate-active-activity)
            ;; No successor Scene slot activated — sandbox deactivation must
            ;; reset shared services to empty.
            (assert (> (length lights-reset-calls) pre-lights-count)
                    "Deactivation must reset lights to empty")
            (assert (> (length skybox-reset-calls) pre-skybox-count)
                    "Deactivation must reset skybox to empty")
            (assert (> (length background-reset-calls) pre-background-count)
                    "Deactivation must reset background to empty")
            ;; Verify reset state is empty (not sandbox)
            (local last-lights (. lights-reset-calls (length lights-reset-calls)))
            (when last-lights
              (assert (= last-lights.ambient.enabled? false)
                      "Reset lights must have ambient disabled"))
            (local last-skybox (. skybox-reset-calls (length skybox-reset-calls)))
            (when last-skybox
              (assert (= last-skybox.enabled? false)
                      "Reset skybox must be disabled"))
            (local last-background (. background-reset-calls (length background-reset-calls)))
            (when last-background
              (assert (= (type last-background.color) :table)
                      "Reset background must be valid"))
            ;; R1-2: Containment must be cleared via PhysicsContainment.ensure-installed
            ;; with enabled? false config.
            (assert (> (length containment-calls) pre-containment-count)
                    "Containment must be cleared on deactivation without successor")
            ;; Verify the call was ensure-installed with the expected disabled config
            (var ensure-call nil)
            (each [_ call (ipairs containment-calls)]
              (when (= (type call) :table)
                (set ensure-call (. call :ensure-installed))))
            (assert ensure-call
                    "PhysicsContainment.ensure-installed must be called on deactivation")
            (assert (and ensure-call.config (not ensure-call.config.enabled?))
                    "Containment config must have enabled? = false")
            (assert (= ensure-call.scene real-scene)
                    "Containment must reference the deactivated scene")
            ;; R1-2: Layout physics bodies must be deactivated via real Scene path
            (assert (> (length physics-deactivate-calls) pre-physics-count)
                    "Real Scene deactivate-activity-slot must deactivate layout physics bodies")
            ;; Clean up real Scene
            (real-scene:drop)
            (camera:drop)
            true)))))
  ;; Restore package.loaded: handle both nil and non-nil originals
  (each [_ name (ipairs mocked-modules)]
    (set (. package.loaded name) (. originals name)))
  (if ok result (error result)))

;; ---------------------------------------------------------------------------
;; Toolbar integration tests (Task 2)
;; ---------------------------------------------------------------------------

(fn sandbox-activation-creates-toolbar-state []
  "Sandbox activation must create or reuse runtime.sandbox-toolbar-state
  and set app.sandbox-toolbar-state."
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :activity-top-toolbar-builder
      :activity-object-drag-mode-provider
     :sandbox-toolbar-state]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                      :activity-session-state
                                      {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      ;; Runtime must have sandbox-toolbar-state
      (assert app.active-world-runtime.sandbox-toolbar-state
              "Sandbox activation must create runtime.sandbox-toolbar-state")
      (assert (= app.sandbox-toolbar-state
                 app.active-world-runtime.sandbox-toolbar-state)
              "app.sandbox-toolbar-state must point to runtime.sandbox-toolbar-state")
      true)))

(fn sandbox-activation-installs-toolbar-builder []
  "Sandbox activation must install app.activity-top-toolbar-builder."
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :activity-top-toolbar-builder
      :activity-object-drag-mode-provider
     :sandbox-toolbar-state]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                      :activity-session-state
                                      {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      (assert (= (type app.activity-top-toolbar-builder) :function)
              "Sandbox activation must install activity-top-toolbar-builder")
      true)))

(fn sandbox-activation-installs-object-drag-mode-provider []
  "Sandbox activation must install object drag mode provider returning toolbar mode."
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :activity-top-toolbar-builder
      :activity-object-drag-mode-provider
     :sandbox-toolbar-state]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (set app.active-world-runtime {:scene mock-scene
                                      :activity-session-state
                                      {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      (assert (= (type app.activity-object-drag-mode-provider) :function)
              "Sandbox activation must install object drag mode provider")
      (assert (= (app.activity-object-drag-mode-provider) nil)
              "Object drag mode provider must return nil by default")
      (app.active-world-runtime.sandbox-toolbar-state:set-interaction-mode :move)
      (assert (= (app.activity-object-drag-mode-provider) :move)
              "Object drag mode provider must return :move in Move mode")
      (app.active-world-runtime.sandbox-toolbar-state:set-interaction-mode :grab)
      (assert (= (app.activity-object-drag-mode-provider) :grab)
              "Object drag mode provider must return :grab in Grab mode")
      true)))

(fn runtime-object-drag-mode-respects-provider []
  "Runtime.activity-object-drag-mode must return nil, :move, or :grab and reject invalid provider values."
  (local Runtime (require :state-runtime))
  (with-restored-app
    [:activity-object-drag-mode-provider]
    (fn []
      (set app.activity-object-drag-mode-provider nil)
      (assert (= (Runtime.activity-object-drag-mode) nil)
              "activity-object-drag-mode must return nil when no provider is installed")
      (set app.activity-object-drag-mode-provider (fn [] :move))
      (assert (= (Runtime.activity-object-drag-mode) :move)
              "activity-object-drag-mode must return :move when provider returns :move")
      (set app.activity-object-drag-mode-provider (fn [] :grab))
      (assert (= (Runtime.activity-object-drag-mode) :grab)
              "activity-object-drag-mode must return :grab when provider returns :grab")
      (set app.activity-object-drag-mode-provider (fn [] nil))
      (assert (= (Runtime.activity-object-drag-mode) nil)
              "activity-object-drag-mode must return nil when provider returns nil")
      (set app.activity-object-drag-mode-provider (fn [] :invalid))
      (local (ok err) (pcall Runtime.activity-object-drag-mode))
      (assert (not ok)
              "activity-object-drag-mode must fail loudly on invalid provider values")
      (assert (string.find (tostring err) "Invalid activity object drag mode")
              (.. "Invalid drag mode error should name invalid mode, got: " (tostring err)))
      true)))

(fn sandbox-snapshot-includes-toolbar-state []
  "Sandbox snapshot must include toolbar state under scene.toolbar."
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :activity-top-toolbar-builder
     :activity-object-drag-mode-provider
     :sandbox-toolbar-state
     :engine]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (var now-ms 0)
      (set app.engine {:now-ms (fn [_self] (set now-ms (+ now-ms 16)) now-ms)})
      (local empty-svc (ActivitySceneState.empty-state))
      (var captured-state {:panels []
                           :lights empty-svc.lights
                           :skybox empty-svc.skybox
                           :background empty-svc.background
                           :containment empty-svc.containment
                           :terrains []})
      (set mock-scene.capture-activity-slot-state
           (fn [_self _activity-id] captured-state))
      (set app.active-world-runtime {:scene mock-scene
                                      :activity-session-state
                                      {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      ;; Snapshot and verify toolbar state
      (local snapshot-result (sandbox-unit.snapshot-sandbox-activity!))
      (assert snapshot-result "Snapshot must return result")
      (assert snapshot-result.scene "Snapshot must have scene")
      (assert (= (type snapshot-result.scene.toolbar) :table)
              (.. "Snapshot scene must include toolbar, got " (tostring (type snapshot-result.scene.toolbar))))
      (assert (= snapshot-result.scene.toolbar.interaction-mode "flight")
              "Snapshot toolbar interaction-mode must be 'flight'")
      true)))

(fn sandbox-restore-includes-toolbar-state []
  "Sandbox restore must restore scene.toolbar into the toolbar state."
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :activity-top-toolbar-builder
     :activity-object-drag-mode-provider
     :sandbox-toolbar-state
     :engine]
    (fn []
      (ensure-built-in-activities!)
      (local mock-scene (make-mock-scene))
      (var now-ms 0)
      (set app.engine {:now-ms (fn [_self] (set now-ms (+ now-ms 16)) now-ms)})
      (set app.active-world-runtime {:scene mock-scene
                                      :activity-session-state
                                      {:sandbox {:scene (ActivitySceneState.empty-state)}}})
      (set app.scene mock-scene)
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (Activities.activate-activity "sandbox")
      ;; Verify default state
      (local toolbar-state app.active-world-runtime.sandbox-toolbar-state)
      (assert toolbar-state "Toolbar state must exist")
      (assert (= toolbar-state.interaction-mode :flight)
              "Default interaction-mode must be :flight")
      ;; Restore with custom toolbar state
      (local session {:scene {:panels []
                              :toolbar {:interaction-mode :grab}}})
      (sandbox-unit.restore-sandbox-activity! nil session session)
      (assert (= toolbar-state.interaction-mode :grab)
              "After restore, interaction-mode must be :grab")
      true)))

(fn sandbox-activation-reuses-previous-raw-controls []
  "When a previous raw FirstPersonControls is stored at
  activity-controls.scene.sandbox (without a wrapper), activation must
  reuse it as the flight-controls inside the new SandboxCameraControls
  wrapper."
  (local FirstPersonControlsModule (require :first-person-controls))
  (with-restored-app
    [:active-world-runtime
     :scene
     :activity-root-actions
     :activity-target-enabled?
     :activity-update
     :activity-preferred-interaction-surface
     :activity-surface-state
     :canvas-surface-interactive?
     :activity-context-enricher
     :active-activity-id
     :activity-top-toolbar-builder
     :activity-object-drag-mode-provider
     :sandbox-toolbar-state]
    (fn []
      (ensure-built-in-activities!)
      ;; Deactivate any lingering sandbox FIRST before setting up controls,
      ;; otherwise deactivation would clear our pre-populated state.
      (when (= (Activities.active-activity-id) "sandbox")
        (Activities.deactivate-active-activity))
      (local mock-scene (make-mock-scene))
      ;; Create a real Camera for the controls
      (local Camera (require :camera))
      (local glm (require :glm))
      (local camera (Camera {:position (glm.vec3 0 0 30)}))
      ;; Create a previous raw FirstPersonControls
      (local raw-controls (FirstPersonControlsModule.FirstPersonControls
                            {:camera camera}))
      ;; Give it a marker so we can identify it later
      (set raw-controls._test-marker true)
      ;; Set up runtime with the pre-populated raw controls at sandbox key
      (local activity-controls {:scene {"sandbox" raw-controls}})
      (set app.active-world-runtime {:scene mock-scene
                                      :activity-session-state
                                      {:sandbox {:scene (ActivitySceneState.empty-state)}}
                                      :activity-cameras {:scene {"sandbox" camera}}
                                      :activity-controls activity-controls})
      (set app.scene mock-scene)
      (Activities.activate-activity "sandbox")
      ;; After activation, the wrapper should be at sandbox key
      (local wrapper (. activity-controls.scene "sandbox"))
      (assert wrapper "Activation must store wrapper at sandbox key")
      (assert (= (type wrapper.flight-controls) :table)
              "Wrapper must have flight-controls")
      ;; The wrapper's flight-controls should be the original raw controls
      (assert wrapper.flight-controls._test-marker
              "Wrapper flight-controls must be the previous raw controls")
      true)))

(table.insert tests {:name "sandbox activity unit registers spec"
                     :fn sandbox-activity-unit-registers-spec})
(table.insert tests {:name "with-restored-app restores registry owner"
                     :fn with-restored-app-restores-registry-owner})
(table.insert tests {:name "sandbox activation sets scene interaction surface"
                     :fn sandbox-activation-sets-scene-interaction-surface})
(table.insert tests {:name "sandbox activation installs root actions"
                     :fn sandbox-activation-installs-root-actions})
(table.insert tests {:name "sandbox activation installs update hook"
                     :fn sandbox-activation-installs-update-hook})
(table.insert tests {:name "sandbox activation installs target predicate"
                     :fn sandbox-activation-installs-target-predicate})
(table.insert tests {:name "sandbox panel hydration processes one per frame"
                     :fn sandbox-panel-hydration-one-per-frame})
(table.insert tests {:name "sandbox retains state across activity switches"
                     :fn sandbox-retains-state-across-switches})
(table.insert tests {:name "sandbox activity actions includes scene root actions"
                     :fn sandbox-activity-actions-includes-scene-root-actions})
(table.insert tests {:name "root context menu delegates scene actions to sandbox"
                     :fn root-context-menu-delegates-scene-actions-to-sandbox})
(table.insert tests {:name "snapshot preserves remaining hydration queue panels"
                     :fn sandbox-snapshot-preserves-remaining-hydration-panels})
(table.insert tests {:name "deactivation resets services when no successor slot"
                      :fn sandbox-deactivation-resets-services-when-no-successor})
(table.insert tests {:name "sandbox activation creates toolbar state"
                      :fn sandbox-activation-creates-toolbar-state})
(table.insert tests {:name "sandbox activation installs toolbar builder"
                      :fn sandbox-activation-installs-toolbar-builder})
(table.insert tests {:name "sandbox activation installs object drag mode provider"
                      :fn sandbox-activation-installs-object-drag-mode-provider})
(table.insert tests {:name "Runtime.activity-object-drag-mode respects provider"
                      :fn runtime-object-drag-mode-respects-provider})
(table.insert tests {:name "snapshot includes toolbar state"
                      :fn sandbox-snapshot-includes-toolbar-state})
(table.insert tests {:name "restore includes toolbar state"
                      :fn sandbox-restore-includes-toolbar-state})
(table.insert tests {:name "activation reuses previous raw FirstPersonControls"
                      :fn sandbox-activation-reuses-previous-raw-controls})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-activity"
                       :tests tests})))

{:name "sandbox-activity"
 :tests tests
 :main main}
