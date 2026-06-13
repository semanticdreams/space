(local PanelUtils (require :target-panel-utils))
(local SkyboxState (require :skybox-state))
(local PhysicsContainment (require :physics-containment))
(local CanvasModes (require :canvas-modes))

(fn reapply-active-world-skybox [theme-name]
  (local entry (and app app.active-world-entry))
  (local world (and entry entry.world))
  (local runtime
    (if (and world world.get-runtime)
        (world:get-runtime)
        (and world world.runtime)))
  (local scene (and runtime runtime.scene))
  (local skybox-policy (and world world.state world.state.scene world.state.scene.skybox))
  (when (and scene scene.set-skybox-state skybox-policy)
    (scene:set-skybox-state
      (SkyboxState.resolve-for-theme skybox-policy theme-name))))

(fn require-active-world-scene-state []
  (local entry (and app app.active-world-entry))
  (if (= entry nil)
      nil
      (do
        (assert entry.world "ThemeActions.apply-theme requires active-world-entry.world")
        (assert entry.world.state "ThemeActions.apply-theme requires active world state")
        (assert entry.world.state.scene "ThemeActions.apply-theme requires active world scene state")
        (assert (= (type entry.world.state.scene.terrains) :table)
                "ThemeActions.apply-theme requires active world scene terrains")
        entry.world.state.scene)))

(fn active-world-scene-build-payload []
  (local scene-state (require-active-world-scene-state))
  (if (= scene-state nil)
      nil
      {:terrains (PanelUtils.clone-table scene-state.terrains)}))

(fn apply-active-theme-to-build-contexts []
  (local active-theme (and app.themes app.themes.get-active-theme
                           (app.themes.get-active-theme)))
  (local canvas-ctx (and app.canvas app.canvas.build-context))
  (when (and canvas-ctx canvas-ctx.set-theme)
    (canvas-ctx:set-theme active-theme))
  (local scene-ctx (and app.scene app.scene.build-context))
  (when (and scene-ctx scene-ctx.set-theme)
    (scene-ctx:set-theme active-theme))
  (local hud-ctx (and app.hud app.hud.build-context))
  (when (and hud-ctx hud-ctx.set-theme)
    (hud-ctx:set-theme active-theme))
  active-theme)

(fn apply-theme [theme-name]
  (local graph-active? (= (CanvasModes.active-mode-id) "graph"))
  (local board-active? (= (CanvasModes.active-mode-id) "board"))
  (local previous-shell-state (when (or graph-active? board-active?)
                                {:interaction-surface app.active-interaction-surface
                                 :canvas-mode app.active-canvas-mode
                                 :canvas-visible? (= app.canvas-visible? true)}))
  (when (or graph-active? board-active?)
    (CanvasModes.deactivate-active-mode))
  (local (ok err)
    (pcall
      (fn []
        (local themes app.themes)
        (when (and themes themes.set-theme)
          (themes.set-theme theme-name))
        (apply-active-theme-to-build-contexts)
        (when (and app.scene app.scene.build-default)
          (app.scene:build-default (active-world-scene-build-payload)))
        (if app.apply-active-world-hud-contrib
            (app.apply-active-world-hud-contrib)
            (when (and app.hud app.hud.build-default)
              (app.hud:build-default)))
        (when (and app.renderers app.renderers.apply-theme)
          (app.renderers:apply-theme (and app.themes (app.themes.get-active-theme))))
        (PhysicsContainment.refresh-visualization
          {:scene app.physics-containment-scene
           :config app.physics-containment-config})
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
          (CanvasModes.activate-mode "board"))
        (when graph-active?
          (CanvasModes.activate-mode "graph")))))
  (when reactivate-ok
    (when (or graph-active? board-active?)
      (local current {:interaction-surface app.active-interaction-surface
                      :canvas-mode app.active-canvas-mode
                      :canvas-visible? (= app.canvas-visible? true)})
      (local previous (or previous-shell-state {}))
      (when (and app.canvas-shell-changed
                 (not (and (= previous.interaction-surface current.interaction-surface)
                          (= previous.canvas-mode current.canvas-mode)
                          (= previous.canvas-visible? current.canvas-visible?))))
        (app.canvas-shell-changed:emit {:reason "canvas-mode"
                                        :previous previous
                                        :current current}))
      (when app.mark-active-world-hud-dirty
        (app.mark-active-world-hud-dirty))))
  (if (not ok)
      (if reactivate-ok
          (error err)
          (do
            (when (and app.canvas-shell-changed (or graph-active? board-active?))
              (app.canvas-shell-changed:emit {:reason "canvas-mode"
                                              :previous (or previous-shell-state {})
                                              :current {:interaction-surface app.active-interaction-surface
                                                        :canvas-mode app.active-canvas-mode
                                                        :canvas-visible? (= app.canvas-visible? true)}}))
            (error (.. (tostring err)
                       " (also failed to reactivate canvas mode: "
                       (tostring reactivate-err) ")"))))
      (not reactivate-ok)
      (do
        (local current {:interaction-surface app.active-interaction-surface
                        :canvas-mode app.active-canvas-mode
                        :canvas-visible? (= app.canvas-visible? true)})
        (local previous (or previous-shell-state {}))
        (when (and app.canvas-shell-changed
                   (not (and (= previous.interaction-surface current.interaction-surface)
                            (= previous.canvas-mode current.canvas-mode)
                            (= previous.canvas-visible? current.canvas-visible?))))
          (app.canvas-shell-changed:emit {:reason "canvas-mode"
                                          :previous previous
                                          :current current}))
        (error (.. "Failed to reactivate canvas mode after theme change: "
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
