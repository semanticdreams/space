(global app (or app {}))

(local fs (require :fs))
(local Activities (require :activities))
(local ActivitySceneState (require :activity-scene-state))

(fn sandbox-activity-owned-paths []
  (local runtime (require :runtime))
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  [(fs.join-path lua-root "sandbox-activity-unit.fnl")])

(fn activate-sandbox-activity! [ctx]
  (local world-runtime (assert app.active-world-runtime
                                "Sandbox activity requires app.active-world-runtime"))
  (local scene (assert world-runtime.scene
                       "Sandbox activity requires runtime.scene"))
  ;; Resolve the canonical scene state from the runtime's activity session state
  ;; (which is cloned from world.state.activity.sessions on world creation).
  (local canonical-scene-state
    (or (and world-runtime.activity-session-state
             (. world-runtime.activity-session-state "sandbox")
             (. world-runtime.activity-session-state "sandbox" :scene))
        (ActivitySceneState.default-sandbox-state)))
  ;; Ensure the sandbox scene slot exists and restore its state
  (scene:restore-activity-slot-state "sandbox" canonical-scene-state)
  ;; Activate the sandbox slot (populates services and builds terrain)
  (scene:activate-activity-slot "sandbox")
  ;; Sandbox is the primary 3D workspace; canvas is not visible by default
  (ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})
  (ctx:set-preferred-interaction-surface! :scene)
  {:activity-id "sandbox"})

(fn deactivate-sandbox-activity! [_ctx _session]
  (when (and app.active-world-runtime app.active-world-runtime.scene)
    (app.active-world-runtime.scene:deactivate-activity-slot "sandbox"))
  true)

(fn snapshot-sandbox-activity! []
  (when (and app.active-world-runtime app.active-world-runtime.scene)
    (app.active-world-runtime.scene:capture-activity-slot-state "sandbox"))
  nil)

(fn restore-sandbox-activity! [state]
  (when (and app.active-world-runtime app.active-world-runtime.scene state)
    (app.active-world-runtime.scene:restore-activity-slot-state "sandbox" state))
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
