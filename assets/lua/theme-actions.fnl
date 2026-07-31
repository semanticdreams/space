(local Activities (require :activities))

(fn workspace-shell-state []
  {:interaction-surface app.active-interaction-surface
   :activity app.active-activity-id
   :canvas-visible? (= app.canvas-visible? true)})

(fn workspace-shell-state= [a b]
  (and a b
       (= a.interaction-surface b.interaction-surface)
       (= a.activity b.activity)
       (= a.canvas-visible? b.canvas-visible?)))

(fn emit-workspace-shell-changed [reason previous]
  (local current (workspace-shell-state))
  (when (and app.workspace-shell-changed
             (not app.suppress-workspace-shell-change?)
             (not (workspace-shell-state= previous current)))
    (app.workspace-shell-changed:emit {:reason reason
                                       :previous previous
                                       :current current}))
  current)

(fn resolve-canonical-sandbox-skybox [world]
  (and world
       world.state
       world.state.activity
       world.state.activity.sessions
       world.state.activity.sessions.sandbox
       world.state.activity.sessions.sandbox.scene
       world.state.activity.sessions.sandbox.scene.skybox))

(fn reapply-active-world-skybox [theme-name]
  ;; Only apply Sandbox skybox when Sandbox is the active activity.
  ;; When another activity (Drawing, Graph, Board) is active, the
  ;; renderer should stay with the active slot's skybox policy —
  ;; not receive an out-of-band Sandbox skybox override.
  (local sandbox-active? (= (Activities.active-activity-id) "sandbox"))
  (when (not sandbox-active?)
    (lua "return nil"))
  (local entry (and app app.active-world-entry))
  (local world (and entry entry.world))
  (local runtime
    (if (and world world.get-runtime)
        (world:get-runtime)
        (and world world.runtime)))
  (local scene (and runtime runtime.scene))
  (local skybox-state (resolve-canonical-sandbox-skybox world))
  (when (and scene scene.set-skybox-state skybox-state)
    ;; R3-3: Resolve skybox by-theme override for current theme before
    ;; applying to the renderer.  This ensures theme-switch activates
    ;; the correct per-theme skybox entry, not just the default.
    (local SkyboxState (require :skybox-state))
    (local resolved (SkyboxState.resolve-for-theme skybox-state theme-name))
    (scene:set-skybox-state resolved)))

(fn apply-active-theme-to-build-contexts []
  (local active-theme (and app.themes app.themes.get-active-theme
                           (app.themes.get-active-theme)))
  (local canvas-ctx (and app.canvas app.canvas.build-context))
  (if (and app.canvas app.canvas.apply-active-theme-to-contexts)
      (app.canvas:apply-active-theme-to-contexts)
      (when (and canvas-ctx canvas-ctx.set-theme)
        (canvas-ctx:set-theme active-theme)))
  (if (and app.scene app.scene.apply-active-theme-to-contexts)
      (app.scene:apply-active-theme-to-contexts)
      (let [scene-ctx (and app.scene app.scene.build-context)]
        (when (and scene-ctx scene-ctx.set-theme)
          (scene-ctx:set-theme active-theme))))
  (local hud-ctx (and app.hud app.hud.build-context))
  (when (and hud-ctx hud-ctx.set-theme)
    (hud-ctx:set-theme active-theme))
  active-theme)

(fn apply-theme [theme-name]
  (local graph-active? (= (Activities.active-activity-id) "graph"))
  (local board-active? (= (Activities.active-activity-id) "board"))
  (local previous-shell-state (when (or graph-active? board-active?)
                                (workspace-shell-state)))
  (when (or graph-active? board-active?)
    (Activities.with-workspace-shell-change-suppressed
      (fn []
        (Activities.deactivate-active-activity))))
  (local (ok err)
    (pcall
      (fn []
        (local themes app.themes)
        (when (and themes themes.set-theme)
          (themes.set-theme theme-name))
        (apply-active-theme-to-build-contexts)
        (if app.apply-active-world-hud-contrib
            (app.apply-active-world-hud-contrib)
            (when (and app.hud app.hud.build-default)
              (app.hud:build-default)))
        (when (and app.renderers app.renderers.apply-theme)
          (app.renderers:apply-theme (and app.themes (app.themes.get-active-theme))))
        (let [manager (and app.scene app.scene.active-containment-manager
                           (app.scene:active-containment-manager))]
          (when manager
            (manager:refresh-visualization {})))
        (reapply-active-world-skybox theme-name)
        (when (and app.settings app.settings.set-value app.settings.save)
          (app.settings.set-value "ui.theme"
                                  (tostring theme-name)
                                  {:save? false})
          (app.settings.save)))))
  (local (reactivate-ok reactivate-err)
    (pcall
      (fn []
        (when board-active?
          (Activities.with-workspace-shell-change-suppressed
            (fn []
              (Activities.activate-activity "board"))))
        (when graph-active?
          (Activities.with-workspace-shell-change-suppressed
            (fn []
              (Activities.activate-activity "graph")))))))
  (when reactivate-ok
    (when (or graph-active? board-active?)
      (emit-workspace-shell-changed "activity" previous-shell-state)
      (when app.mark-active-world-hud-dirty
        (app.mark-active-world-hud-dirty))))
  (if (not ok)
      (if reactivate-ok
          (error err)
          (do
            (when (or graph-active? board-active?)
              (emit-workspace-shell-changed "activity" previous-shell-state))
            (error (.. (tostring err)
                       " (also failed to reactivate activity: "
                       (tostring reactivate-err) ")"))))
      (not reactivate-ok)
      (do
        (emit-workspace-shell-changed "activity" previous-shell-state)
        (error (.. "Failed to reactivate activity after theme change: "
                   (tostring reactivate-err))))))

(fn request-theme [theme-name]
  (if app.request-theme-change
      (app.request-theme-change theme-name)
      (apply-theme theme-name)))

(fn toggle-theme []
  (local themes app.themes)
  (local current (and themes themes.get-active-theme-name (themes.get-active-theme-name)))
  (local next (if (= (tostring current) "light") :dark :light))
  (apply-theme next))

(fn request-toggle-theme []
  (local themes app.themes)
  (local current (and themes themes.get-active-theme-name (themes.get-active-theme-name)))
  (local next (if (= (tostring current) "light") :dark :light))
  (request-theme next))

{:apply-theme apply-theme
 :request-theme request-theme
 :toggle-theme toggle-theme
 :request-toggle-theme request-toggle-theme}
