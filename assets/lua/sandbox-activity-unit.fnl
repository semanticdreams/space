(global app (or app {}))

(local fs (require :fs))
(local Activities (require :activities))
(local ActivitySceneState (require :activity-scene-state))
(local SandboxActivityActions (require :sandbox-activity-actions))

(fn sandbox-activity-owned-paths []
  (local runtime (require :runtime))
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  [(fs.join-path lua-root "sandbox-activity-unit.fnl")
   (fs.join-path lua-root "sandbox-activity-actions.fnl")])

;; ---------------------------------------------------------------------------
;; Scene-target predicate
;; ---------------------------------------------------------------------------

(fn sandbox-target-enabled? [target]
  "Allow any target when the active surface is Scene.  The scene surface
  already routes targets through the active activity slot — no further
  filtering is needed for Sandbox."
  true)

;; ---------------------------------------------------------------------------
;; Incremental panel hydration per frame
;; ---------------------------------------------------------------------------

(fn hydration-now-ms []
  (assert (and app app.engine app.engine.now-ms)
          "Sandbox hydration timing requires app.engine.now-ms")
  (app.engine:now-ms))

(fn restore-one-hydration-panel! [runtime]
  "Restore a single queued hydration panel from runtime.hydration.
  Returns true when all panels have been restored (hydration complete),
  nil otherwise."
  (local hydration runtime.hydration)
  (local scene runtime.scene)
  (local panels (or hydration.scene-panels []))
  (if (> hydration.scene-panel-index (length panels))
      true   ;; no panels left — already complete
      (do
        (scene:restore-panel-state
          (. panels hydration.scene-panel-index)
          hydration.scene-panel-index)
        (scene:sync-scene-objects)
        (set hydration.scene-panel-index (+ hydration.scene-panel-index 1))
        (when (> hydration.scene-panel-index (length panels))
          true))))

(fn mark-hydration-complete! [hydrated? world]
  (local runtime app.active-world-runtime)
  (when (and runtime runtime.hydration)
    (local hydration runtime.hydration)
    (set hydration.completed? true)
    (set hydration.phase "complete")
    (set hydration.completed-at-ms (hydration-now-ms)))
  (when (and hydrated? world world.id app app.set-startup-physics-paused)
    (app.set-startup-physics-paused world.id false))
  true)

(fn sandbox-activity-update [payload]
  "Activity-owned update hook: restore at most one queued scene panel
  per frame from runtime.hydration, then sync completion state."
  (local runtime (or (and payload payload.runtime)
                     app.active-world-runtime))
  (local world (and payload payload.world))
  (when (and runtime runtime.hydration)
    (local hydration runtime.hydration)
    (when (and hydration.ready?
               (not hydration.completed?))
      ;; First hydrating frame: record start time
      (when (not hydration.started?)
        (set hydration.started? true)
        (set hydration.started-at-ms (hydration-now-ms)))
      (if (= hydration.phase "scene-panels")
          (let [all-done? (restore-one-hydration-panel! runtime)]
            (when all-done?
              (mark-hydration-complete! true world)))
          (mark-hydration-complete! false world))))
  nil)

;; ---------------------------------------------------------------------------
;; Activity lifecycle
;; ---------------------------------------------------------------------------

(fn sandbox-root-actions [context]
  "Delegated from root-context-menu-actions when Sandbox is the active activity."
  ((. SandboxActivityActions :sandbox-root-actions) context))

(fn activate-sandbox-activity! [ctx]
  (local world-runtime (assert app.active-world-runtime
                                "Sandbox activity requires app.active-world-runtime"))
  (local scene (assert world-runtime.scene
                        "Sandbox activity requires runtime.scene"))
  ;; Ensure the slot exists but do NOT overwrite its retained scene-state.
  ;; Pending session state (restored by Activities after activation) or the
  ;; existing retained state provides the canonical scene data.
  (scene:ensure-activity-slot "sandbox")
  ;; Activate the sandbox slot (populates services and builds terrain from retained state).
  (scene:activate-activity-slot "sandbox")
  ;; Sandbox is the primary 3D workspace; canvas is not visible by default
  (ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})
  (ctx:set-preferred-interaction-surface! :scene)
  ;; Install Sandbox-specific root actions (replaces global scene actions)
  (ctx:set-root-actions! sandbox-root-actions)
  ;; Scene surface accepts any target — the active slot handles routing
  (ctx:set-target-enabled! sandbox-target-enabled?)
  ;; Incremental hydration: restore queued panels one per frame
  (ctx:set-update! sandbox-activity-update)
  {:activity-id "sandbox"})

(fn slice-array-from [entries start-index]
  "Return a new array containing entries from start-index onward."
  (local out [])
  (each [idx entry (ipairs (or entries []))]
    (when (>= idx start-index)
      (table.insert out entry)))
  out)

(fn merge-panel-arrays [restored pending]
  "Concatenate two panel arrays."
  (local panels [])
  (each [_ panel (ipairs (or restored []))]
    (table.insert panels panel))
  (each [_ panel (ipairs (or pending []))]
    (table.insert panels panel))
  panels)

(fn deactivate-sandbox-activity! [_ctx _session]
  (when (and app.active-world-runtime app.active-world-runtime.scene)
    (local scene app.active-world-runtime.scene)
    (scene:deactivate-activity-slot "sandbox")
    ;; R1-2: After deactivating the Scene slot, if no successor Scene slot
    ;; is active, reset shared lights/skybox/background/containment to empty
    ;; so they don't leak sandbox state into other activities.
    (when (not (= (type scene.active-activity-slot-id) :string))
      (local empty (ActivitySceneState.empty-state))
      (when (and app app.lights app.lights.set-state)
        (app.lights:set-state empty.lights))
      (when (and app app.renderers app.renderers.skybox app.renderers.skybox.set-state)
        (app.renderers.skybox:set-state empty.skybox))
      (when (and app app.renderers app.renderers.set-background-state)
        (app.renderers:set-background-state empty.background))
      ;; Clear containment through the real PhysicsContainment API.
      ;; ensure-installed with enabled? false calls clear() internally.
      (local PhysicsContainment (require :physics-containment))
      (PhysicsContainment.ensure-installed {:config {:enabled? false} :scene scene})))
  true)

(fn snapshot-sandbox-activity! []
  ;; Return the canonical *session* shape {:scene <state>} because
  ;; Activities.snapshot-activity-sessions writes this as sessions.sandbox.
  (if (and app.active-world-runtime app.active-world-runtime.scene)
      (let [captured (app.active-world-runtime.scene:capture-activity-slot-state "sandbox")
            runtime app.active-world-runtime
            hydration (and runtime runtime.hydration)]
        ;; R1-1: Merge remaining hydration queue panels into captured state.
        ;; Without this, switching/suspending mid-hydration discards unhydrated panels.
        (when (and hydration captured
                   (= (type captured.panels) :table)
                   (> (length (or hydration.scene-panels [])) 0)
                   (not hydration.completed?))
          (local remaining (slice-array-from hydration.scene-panels hydration.scene-panel-index))
          (set captured.panels (merge-panel-arrays captured.panels remaining)))
        {:scene captured})
      nil))

(fn restore-sandbox-activity! [ctx session state]
  ;; Activities calls restore with (ctx, session, state).  The third argument
  ;; is the pending session shape {:scene <canonical-state>}.  Only pass the
  ;; inner canonical scene state to the Scene slot.
  (local scene-state (and (= (type state) :table) state.scene))
  (when (and app.active-world-runtime app.active-world-runtime.scene scene-state)
    (app.active-world-runtime.scene:restore-activity-slot-state "sandbox" scene-state))
  true)

(fn load-sandbox-activity! []
  (when (not (Activities.activity-registered? "sandbox"))
    (Activities.register-activity
      {:id "sandbox"
       :label "Sandbox"
       :icon "toys"
       :button-name "sandbox-activity"
       :show-in-switcher? true
       :activate activate-sandbox-activity!
       :deactivate deactivate-sandbox-activity!
       :snapshot snapshot-sandbox-activity!
       :restore restore-sandbox-activity!}))
  true)

(fn unload-sandbox-activity! []
  (local registered? (Activities.activity-registered? "sandbox"))
  (local active? (and registered?
                      (= (Activities.active-activity-id) "sandbox")))
  (when active?
    (if app.set-active-activity
        (app.set-active-activity nil)
        (Activities.deactivate-active-activity)))
  (when registered?
    (Activities.unregister-activity "sandbox"))
  true)

{:sandbox-activity-owned-paths sandbox-activity-owned-paths
 :load-sandbox-activity! load-sandbox-activity!
 :unload-sandbox-activity! unload-sandbox-activity!
 :snapshot-sandbox-activity! snapshot-sandbox-activity!
 :restore-sandbox-activity! restore-sandbox-activity!}
