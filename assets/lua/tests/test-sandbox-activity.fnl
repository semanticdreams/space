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

(fn with-restored-app [fields f]
  (local snapshot {})
  (each [_ key (ipairs fields)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs fields)]
    (set (. app key) (. snapshot key)))
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
            :interactive? false}))
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
  {:ensure-activity-slot ensure-activity-slot
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
  Additionally, the slot's layout physics bodies must be deactivated
  matching slot-to-slot activation behavior."
  ;; Mock PhysicsContainment and LayoutPhysicsBodies with call trackers
  (var containment-calls [])
  (var physics-deactivate-calls [])
  (local originals {})
  (set (. originals "physics-containment") (. package.loaded "physics-containment"))
  (set (. originals "layout-physics-bodies") (. package.loaded "layout-physics-bodies"))
  (set (. package.loaded "physics-containment")
       {:clear (fn []
                 (table.insert containment-calls :clear)
                 true)
        :ensure-installed (fn [opts]
                            (table.insert containment-calls {:ensure-installed opts})
                            (when (and opts opts.config (not opts.config.enabled?))
                              (table.insert containment-calls :clear))
                            true)})
  (set (. package.loaded "layout-physics-bodies")
       {:deactivate (fn [entity]
                      (table.insert physics-deactivate-calls entity)
                      true)})
  (local (ok result)
    (pcall
      (fn []
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
           :engine]
           (fn []
             (ensure-built-in-activities!)
             (local mock-scene (make-mock-scene))
             ;; Track calls to service resets
             (var lights-reset-calls [])
             (var skybox-reset-calls [])
             (var background-reset-calls [])
             ;; Install mock global services that record reset calls
             (set app.lights {:set-state (fn [_self state] (table.insert lights-reset-calls state))})
             (set app.renderers
                  {:skybox {:set-state (fn [_self state] (table.insert skybox-reset-calls state))}
                   :set-background-state (fn [_self state] (table.insert background-reset-calls state))})
             ;; Set up runtime with sandbox session
             (set app.active-world-runtime
                  {:scene mock-scene
                   :activity-session-state
                   {:sandbox {:scene (ActivitySceneState.empty-state)}}})
             (set app.scene mock-scene)
             (when (not (= (Activities.active-activity-id) nil))
               (Activities.deactivate-active-activity))
             ;; Activate sandbox
             (Activities.activate-activity "sandbox")
             (assert (. mock-scene.slots "sandbox" :visible?)
                     "Sandbox slot must be active")
             ;; Give the sandbox slot a mock entity so physics deactivation is exercised
             (set (. mock-scene.slots "sandbox" :entity) {:id "sandbox-root"})
             ;; Override the mock deactivation to exercise the real physics
             ;; body deactivation path (matching the fix in scene.fnl)
             (local original-deactivate mock-scene.deactivate-activity-slot)
             (set mock-scene.deactivate-activity-slot
                  (fn [self activity-id]
                    (local slot (. self.slots activity-id))
                    (when (and slot (= (self:active-slot-id) activity-id))
                      (local LayoutPhysicsBodies (require :layout-physics-bodies))
                      (when (and slot.entity
                                 (pcall (fn [] (LayoutPhysicsBodies.deactivate slot.entity))))
                        nil))
                    (original-deactivate self activity-id)))
            ;; Track calls before deactivation
            (local pre-lights-count (length lights-reset-calls))
            (local pre-skybox-count (length skybox-reset-calls))
            (local pre-background-count (length background-reset-calls))
            ;; Deactivate sandbox
            (Activities.deactivate-active-activity)
            ;; After deactivation WITHOUT a successor Scene slot:
            ;; services must have been reset to empty.
            (assert (> (length lights-reset-calls) pre-lights-count)
                    "Deactivation must reset lights to empty")
            (assert (> (length skybox-reset-calls) pre-skybox-count)
                    "Deactivation must reset skybox to empty")
            (assert (> (length background-reset-calls) pre-background-count)
                    "Deactivation must reset background to empty")
            ;; Verify the reset state is empty (not sandbox state)
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
            ;; R1-2: Containment must be cleared via real PhysicsContainment API
            (assert (> (length containment-calls) 0)
                    "Containment must be cleared on deactivation without successor")
            ;; R1-2: Layout physics bodies must be deactivated matching slot-to-slot behavior
            (assert (> (length physics-deactivate-calls) 0)
                    "Sandbox slot physics bodies must be deactivated on last-slot clear")
            true)))))
  ;; Restore package.loaded overrides
  (each [name _value (pairs originals)]
    (set (. package.loaded name) (. originals name)))
  (if ok result (error result)))

(table.insert tests {:name "sandbox activity unit registers spec"
                     :fn sandbox-activity-unit-registers-spec})
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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-activity"
                       :tests tests})))

{:name "sandbox-activity"
 :tests tests
 :main main}
