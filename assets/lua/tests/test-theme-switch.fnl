(local tests [])

(local AppBootstrap (require :app-bootstrap))
(local BuildContext (require :build-context))
(local ControlPanel (require :hud-control-panel))
(local Icons (require :icons))
(local PhysicsContainment (require :physics-containment))
(local ThemeActions (require :theme-actions))
(local Themes (require :themes))
(local Activities (require :activities))

(fn with-settings [value f]
  (local previous app.settings)
  (set app.settings
       {:get-value (fn [key fallback]
                     (if (= key "ui.theme") value fallback))
        :set-value (fn [_key _value _opts] nil)
        :save (fn [] true)})
  (local result (f))
  (set app.settings previous)
  result)

(fn init-themes-reads-settings []
  (local previous app.themes)
  (with-settings
    "light"
    (fn []
      (set app.themes nil)
      (local themes (AppBootstrap.init-themes))
      (assert (= (themes.get-active-theme-name) :light))
      true))
  (set app.themes previous))

(fn init-themes-falls-back-for-unknown-stored-theme []
  (local previous app.themes)
  (with-settings
    "solarized"
    (fn []
      (set app.themes nil)
      (local themes (AppBootstrap.init-themes))
      (assert (= (themes.get-active-theme-name) :dark))
      true))
  (set app.themes previous))

(fn themes-set-theme-resolves-string-key []
  (local themes (Themes))
  (themes.add-theme :dark (require :dark-theme))
  (themes.add-theme :light (require :light-theme))
  (themes.set-theme "light")
  (assert (= (themes.get-active-theme-name) :light))
  true)

(fn find-entity [root predicate]
  (var found nil)
  (fn walk [entity]
    (when (and entity (not found))
      (when (predicate entity)
        (set found entity))
      (when (and (not found) entity.children)
        (each [_ child (ipairs entity.children)]
          (walk (or child.element child))))
      (when (and (not found) entity.child)
        (walk entity.child))
      (when (and (not found) entity.element)
        (walk entity.element))))
  (walk root)
  found)

(fn control-panel-toggles-theme []
  (local previous-themes app.themes)
  (local previous-settings app.settings)
  (local previous-icons app.icons)
  (local previous-runtime-performance-ui-paused app.runtime-performance-ui-paused)
  (local previous-apply-theme ThemeActions.apply-theme)
  (local themes (Themes))
  (themes.add-theme :dark (require :dark-theme))
  (themes.add-theme :light (require :light-theme))
  (themes.set-theme :dark)
  (set app.themes themes)
  (set app.settings nil)
  (set app.runtime-performance-ui-paused false)
  (var applied-theme nil)
  (set ThemeActions.apply-theme
       (fn [theme-name]
         (set applied-theme theme-name)
         (themes.set-theme theme-name)
         theme-name))
  (local icons (Icons))
  (set app.icons icons)
  (local ctx
    (BuildContext {:theme (themes.get-active-theme)
                   :clickables app.clickables
                   :hoverables app.hoverables
                   :system-cursors app.system-cursors
                   :icons icons}))
  (local panel ((ControlPanel {}) ctx))
  (local toggle
    (find-entity panel (fn [entity]
                         (and entity.icon (= entity.icon "contrast")))))
  (assert toggle "Expected theme toggle button")
  (toggle.clicked.emit nil)
  (assert (= applied-theme nil)
          "control panel theme button should not apply the theme directly from the widget callback")
  (assert (= (themes.get-active-theme-name) :dark)
          "control panel theme button should leave the active theme unchanged until the next frame")
  (app.update 0)
  (assert (= applied-theme :light)
          "control panel theme button should apply the requested theme on the next frame boundary")
  (assert (= (themes.get-active-theme-name) :light)
          "control panel theme button should finish the deferred theme change on the next frame")
  (when panel
    (panel:drop))
  (when icons
    (icons:drop))
  (set ThemeActions.apply-theme previous-apply-theme)
  (set app.runtime-performance-ui-paused previous-runtime-performance-ui-paused)
  (set app.icons previous-icons)
  (set app.settings previous-settings)
  (set app.themes previous-themes)
  true)

(fn apply-theme-does-not-create-graph-view-outside-graph-mode []
  (local original-graph-view app.graph-view)
  (local original-graph app.graph)
  (local original-canvas app.canvas)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-active-world-entry app.active-world-entry)
  (local original-registry app.activity-registry)
  (local original-modes-changed app.activities-changed)
  (var hud-rebuild-calls 0)
  (local themes {:set-theme (fn [_theme] true)
                  :get-active-theme (fn [] {:name :light})})
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.graph {})
  (set app.graph-view nil)
  (set app.canvas {:build-context {}})
  (set app.scene {:build-default (fn [_self] true)})
  (set app.hud {})
  (set app.apply-active-world-hud-contrib
       (fn []
         (set hud-rebuild-calls (+ hud-rebuild-calls 1))
         true))
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes themes)
  (set app.active-world-entry {:world {:runtime {}
                                        :state {:scene {:terrains []}}}})
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light)
        (assert (= hud-rebuild-calls 1)
                "apply-theme should rebuild the HUD through the active-world HUD helper")
        (assert (not app.graph-view)
                "apply-theme should not create a graph view outside graph mode"))))
  (set app.graph-view original-graph-view)
  (set app.graph original-graph)
  (set app.canvas original-canvas)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  (set app.active-world-entry original-active-world-entry)
  (set app.activity-registry original-registry)
  (set app.activities-changed original-modes-changed)
  (when (not ok)
    (error err))
  true)

(fn apply-theme-rebuilds-active-graph-mode-through-mode-lifecycle []
  (local original-graph-view app.graph-view)
  (local original-graph app.graph)
  (local original-canvas app.canvas)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-active-world-entry app.active-world-entry)
  (local original-active-world-runtime app.active-world-runtime)
  (local original-registry app.activity-registry)
  (local original-modes-changed app.activities-changed)
  (local original-active-activity-id app.active-activity-id)
  (var activate-calls 0)
  (var deactivate-calls 0)
  (var hud-rebuild-calls 0)
  (var canvas-theme nil)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (local runtime {})
  (set app.graph {})
  (set app.canvas {:build-context {:theme {:name :dark}
                                    :set-theme (fn [self theme]
                                                 (set self.theme theme)
                                                 (set canvas-theme theme))}})
  (set app.scene {:build-context {}
                  :build-default (fn [_self _payload] true)})
  (set app.hud {:build-default
                (fn [_self]
                  (set hud-rebuild-calls (+ hud-rebuild-calls 1))
                  (assert (not app.active-world-runtime.graph-view)
                          "graph mode should be deactivated before HUD rebuild"))})
  (set app.apply-active-world-hud-contrib
        (fn []
          (app.hud:build-default)))
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes {:set-theme (fn [_theme] true)
                   :get-active-theme (fn [] {:name :light})})
  (set app.active-world-runtime runtime)
  (set app.active-world-entry {:world {:runtime runtime
                                        :state {:scene {:terrains []}}}})
  (Activities.register-activity
    {:id "graph"
     :label "Graph"
     :activate (fn [_ctx]
                 (set activate-calls (+ activate-calls 1))
                 (set runtime.graph-view {:mode-owned? true})
                 (set app.graph-view runtime.graph-view)
                 {:graph-view runtime.graph-view})
     :deactivate (fn [_ctx _session]
                   (set deactivate-calls (+ deactivate-calls 1))
                   (set runtime.graph-view nil)
                   (set app.graph-view nil)
                   true)})
  (Activities.activate-activity "graph")
  (set activate-calls 0)
  (set deactivate-calls 0)
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light)
        (assert (= deactivate-calls 1)
                "apply-theme should deactivate active graph mode")
        (assert (= activate-calls 1)
                "apply-theme should reactivate active graph mode")
        (assert (= hud-rebuild-calls 1)
                "apply-theme should rebuild the HUD while graph mode is inactive")
        (assert (= (and canvas-theme canvas-theme.name) :light)
                "apply-theme should update canvas build context before graph mode rebuild")
        (assert app.active-world-runtime.graph-view
                "apply-theme should restore the mode-owned graph view on the active runtime"))))
  (set app.graph-view original-graph-view)
  (set app.graph original-graph)
  (set app.canvas original-canvas)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  (set app.active-world-entry original-active-world-entry)
  (set app.active-world-runtime original-active-world-runtime)
  (set app.activity-registry original-registry)
  (set app.activities-changed original-modes-changed)
  (set app.active-activity-id original-active-activity-id)
  (when (not ok)
    (error err))
  true)

(fn apply-theme-saves-exact-theme-key []
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (var saved-key nil)
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.canvas nil)
  (set app.scene {:build-default (fn [_self] true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key value _opts]
                                  (set saved-key value)
                                  true)
                     :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] true)
                   :get-active-theme (fn [] {:name :custom})})
  (ThemeActions.apply-theme :solarized)
  (assert (= saved-key "solarized")
          "apply-theme should persist the exact theme key string")
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  true)

(fn apply-theme-updates-scene-and-hud-build-contexts-without-canvas []
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (var scene-theme nil)
  (var hud-theme nil)
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.canvas nil)
  (set app.scene {:build-context {:set-theme (fn [_self theme]
                                                (set scene-theme theme))}
                  :build-default (fn [_self _payload] true)})
  (set app.hud {:build-context {:set-theme (fn [_self theme]
                                             (set hud-theme theme))}
                :build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes {:set-theme (fn [_theme] true)
                   :get-active-theme (fn [] {:name :dark})})
  (ThemeActions.apply-theme :dark)
  (assert scene-theme "apply-theme should update scene build context theme")
  (assert (= (and scene-theme scene-theme.name) :dark)
          "apply-theme should set scene build context theme name")
  (assert hud-theme "apply-theme should update hud build context theme")
  (assert (= (and hud-theme hud-theme.name) :dark)
          "apply-theme should set hud build context theme name")
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  true)

(fn apply-theme-refreshes-physics-containment-visualization []
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-containment-scene app.physics-containment-scene)
  (local original-containment-config app.physics-containment-config)
  (local original-refresh-visualization PhysicsContainment.refresh-visualization)
  (var refresh-payload nil)
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.canvas nil)
  (set app.scene {:build-default (fn [_self] true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                     :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] true)
                   :get-active-theme (fn [] {:name :light})})
  (set app.physics-containment-scene {:id "containment-scene"})
  (set app.physics-containment-config {:mode "manual-bounds"
                                       :bounds {:min [-1 -2 -3]
                                                :max [1 2 3]}
                                       :visualization {:enabled true}})
  (set PhysicsContainment.refresh-visualization
       (fn [opts]
         (set refresh-payload opts)
         true))
  (ThemeActions.apply-theme :light)
  (assert (= (and refresh-payload.scene refresh-payload.scene.id) "containment-scene")
          "apply-theme should refresh the active containment visualization with the current scene")
  (assert (= (and refresh-payload.config refresh-payload.config.mode) "manual-bounds")
          "apply-theme should refresh the active containment visualization with the current config")
  (set PhysicsContainment.refresh-visualization original-refresh-visualization)
  (set app.physics-containment-scene original-containment-scene)
  (set app.physics-containment-config original-containment-config)
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  true)

(fn apply-theme-applies-canonical-sandbox-skybox []
  ;; R1-1: apply-theme must resolve skybox from canonical Sandbox scene state
  ;; (world.state.activity.sessions.sandbox.scene.skybox) and must NOT attempt
  ;; a legacy rebuild from world.state.scene.terrains.
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-active-world-entry app.active-world-entry)
  (var build-default-called? false)
  (var skybox-applied nil)
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.canvas nil)
  ;; Mock scene: build-default should NOT be called by theme-actions anymore
  (set app.scene {:build-default (fn [_self _payload]
                                  (set build-default-called? true)
                                  true)
                  :build-context {}
                  ;; set-skybox-state is called by reapply-active-world-skybox
                  :set-skybox-state (fn [_self state]
                                     (set skybox-applied state)
                                     true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] true)
                    :get-active-theme (fn [] {:name :light})})
  ;; Set up canonical Sandbox scene state with custom skybox
  (local sandbox-skybox {:enabled? true
                         :name "ocean"
                         :brightness 0.75
                         :tint-color [0.8 0.9 1.0]})
  (set app.active-world-entry
       {:world {:runtime {:scene app.scene}
                :state {:scene {}  ;; legacy scene is empty
                        :activity {:active_id "sandbox"
                                   :sessions {:sandbox
                                              {:scene {:panels []
                                                       :terrains []
                                                       :lights {:ambient {} :directional [] :point [] :spot []}
                                                       :skybox sandbox-skybox
                                                       :background {:color [0 0 0]}
                                                       :containment {:enabled? false}}}}}}}})
  (ThemeActions.apply-theme :light)
  ;; R1-1: verify canonical skybox was applied
  (assert skybox-applied "apply-theme should apply skybox from canonical sandbox state")
  (assert skybox-applied.enabled? "canonical skybox should be enabled")
  (assert (= skybox-applied.name "ocean")
          "canonical skybox should use the name from sandbox session scene")
  ;; R1-1: verify legacy scene rebuild was NOT triggered
  (assert (not build-default-called?)
          "apply-theme must NOT call build-default (no legacy terrain rebuild)")
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  (set app.active-world-entry original-active-world-entry)
  true)

(fn apply-theme-succeeds-without-legacy-terrain-state []
  ;; R1-1: apply-theme must NOT fail when legacy world.state.scene.terrains
  ;; is absent. ThemeActions reads skybox from canonical Sandbox state and
  ;; does not assert on legacy terrain state.
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-active-world-entry app.active-world-entry)
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.canvas nil)
  (set app.scene {:build-context {}
                  :set-skybox-state (fn [_self _state] true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] true)
                    :get-active-theme (fn [] {:name :light})})
  ;; Legacy scene has no terrains key; canonical sandbox scene has skybox
  (set app.active-world-entry
       {:world {:runtime {:scene app.scene}
                :state {:scene {}  ;; empty legacy scene (no terrains)
                        :activity {:active_id "sandbox"
                                   :sessions {:sandbox
                                              {:scene {:panels []
                                                       :terrains []
                                                       :lights {:ambient {} :directional [] :point [] :spot []}
                                                       :skybox {:enabled? true :name "lake" :brightness 0.1 :tint-color [1 1 1]}
                                                       :background {:color [0 0 0]}
                                                       :containment {:enabled? false}}}}}}}})
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light))))
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  (set app.active-world-entry original-active-world-entry)
  (assert ok (.. "apply-theme should succeed without legacy terrain state, got: " (tostring err)))
  true)

(fn apply-theme-rebuilds-active-board-mode-through-mode-lifecycle []
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-active-world-entry app.active-world-entry)
  (local original-active-world-runtime app.active-world-runtime)
  (local original-registry app.activity-registry)
  (local original-modes-changed app.activities-changed)
  (local original-active-activity-id app.active-activity-id)
  (local original-board-view app.board-view)
  (local original-board app.board)
  (var activate-calls 0)
  (var deactivate-calls 0)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.graph {})
  (set app.graph-view nil)
  (set app.canvas {:build-context {:theme {:name :dark}
                                    :set-theme (fn [self theme]
                                                 (set self.theme theme))}})
  (set app.scene {:build-context {}
                  :build-default (fn [_self _payload] true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes {:set-theme (fn [_theme] true)
                   :get-active-theme (fn [] {:name :light})})
  (local runtime {})
  (set app.active-world-runtime runtime)
  (set app.active-world-entry {:world {:runtime runtime
                                        :state {:scene {:terrains []}}}})
  (Activities.register-activity
    {:id "board"
     :label "Board"
     :activate (fn [_ctx]
                 (set activate-calls (+ activate-calls 1))
                 (set runtime.board-view {:mode-owned? true})
                 (set app.board-view runtime.board-view)
                 {:board-view runtime.board-view})
     :deactivate (fn [_ctx _session]
                   (set deactivate-calls (+ deactivate-calls 1))
                   (set runtime.board-view nil)
                   (set app.board-view nil)
                   true)})
  (Activities.activate-activity "board")
  (set activate-calls 0)
  (set deactivate-calls 0)
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light)
        (assert (= deactivate-calls 1)
                "apply-theme should deactivate active board mode")
        (assert (= activate-calls 1)
                "apply-theme should reactivate active board mode")
        (assert app.board-view
                "apply-theme should restore the mode-owned board view on the active runtime"))))
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  (set app.active-world-entry original-active-world-entry)
  (set app.active-world-runtime original-active-world-runtime)
  (set app.activity-registry original-registry)
  (set app.activities-changed original-modes-changed)
  (set app.active-activity-id original-active-activity-id)
  (set app.board-view original-board-view)
  (set app.board original-board)
  (when (not ok)
    (error err))
  true)

(table.insert tests {:name "Init themes uses stored UI theme" :fn init-themes-reads-settings})
(table.insert tests {:name "Init themes falls back for unknown stored UI theme"
                     :fn init-themes-falls-back-for-unknown-stored-theme})
(table.insert tests {:name "Themes set-theme resolves string key"
                     :fn themes-set-theme-resolves-string-key})
(table.insert tests {:name "Control panel toggles theme" :fn control-panel-toggles-theme})
(table.insert tests {:name "Apply theme does not create graph view outside graph mode"
                     :fn apply-theme-does-not-create-graph-view-outside-graph-mode})
(table.insert tests {:name "Apply theme rebuilds active graph mode through mode lifecycle"
                     :fn apply-theme-rebuilds-active-graph-mode-through-mode-lifecycle})
(table.insert tests {:name "Apply theme saves exact theme key"
                      :fn apply-theme-saves-exact-theme-key})
(table.insert tests {:name "Apply theme updates scene and HUD build contexts without canvas"
                      :fn apply-theme-updates-scene-and-hud-build-contexts-without-canvas})
(table.insert tests {:name "Apply theme refreshes physics containment visualization"
                     :fn apply-theme-refreshes-physics-containment-visualization})
(table.insert tests {:name "Apply theme applies canonical sandbox skybox"
                      :fn apply-theme-applies-canonical-sandbox-skybox})
(table.insert tests {:name "Apply theme succeeds without legacy terrain state"
                      :fn apply-theme-succeeds-without-legacy-terrain-state})
(table.insert tests {:name "Apply theme rebuilds active board mode through mode lifecycle"
                     :fn apply-theme-rebuilds-active-board-mode-through-mode-lifecycle})

(fn apply-theme-fails-when-reactivation-fails-despite-successful-theme []
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-active-world-entry app.active-world-entry)
  (local original-active-world-runtime app.active-world-runtime)
  (local original-registry app.activity-registry)
  (local original-modes-changed app.activities-changed)
  (local original-active-activity-id app.active-activity-id)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.graph {})
  (set app.graph-view nil)
  (set app.canvas {:build-context {:theme {:name :dark}
                                    :set-theme (fn [self theme]
                                                 (set self.theme theme))}})
  (set app.scene {:build-context {}
                  :build-default (fn [_self _payload] true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] true)
                   :get-active-theme (fn [] {:name :light})})
  (local runtime {})
  (set app.active-world-runtime runtime)
  (set app.active-world-entry {:world {:runtime runtime
                                        :state {:scene {:terrains []}}}})
  (var activate-fails? false)
  (Activities.register-activity
    {:id "graph"
     :label "Graph"
     :activate (fn [_ctx]
                 (if activate-fails?
                     (error "reactivation failed")
                     {:mode-owned? true}))
     :deactivate (fn [_ctx _session] true)})
  (Activities.activate-activity "graph")
  (set activate-fails? true)
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light))))
  (Activities.unregister-activity "graph")
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  (set app.active-world-entry original-active-world-entry)
  (set app.active-world-runtime original-active-world-runtime)
  (set app.activity-registry original-registry)
  (set app.activities-changed original-modes-changed)
  (set app.active-activity-id original-active-activity-id)
  (assert (not ok)
          "apply-theme should surface reactivation failure even when theme rebuild succeeds")
  (assert (and err (string.find err "Failed to reactivate activity" 1 true))
          "apply-theme should report reactivation failure when theme succeeds")
  (assert (not (string.find (tostring err) "theme rebuild" 1 true))
          "apply-theme should not report a theme rebuild failure when theme succeeded")
  true)

(table.insert tests {:name "Apply theme fails when reactivation fails despite successful theme"
                     :fn apply-theme-fails-when-reactivation-fails-despite-successful-theme})

(fn apply-theme-surfaces-reactivation-failure []
  (local original-settings app.settings)
  (local original-themes app.themes)
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-renderers app.renderers)
  (local original-graph-view app.graph-view)
  (local original-canvas app.canvas)
  (local original-graph app.graph)
  (local original-apply-active-world-hud-contrib app.apply-active-world-hud-contrib)
  (local original-active-world-entry app.active-world-entry)
  (local original-active-world-runtime app.active-world-runtime)
  (local original-registry app.activity-registry)
  (local original-modes-changed app.activities-changed)
  (local original-active-activity-id app.active-activity-id)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.graph {})
  (set app.graph-view nil)
  (set app.canvas {:build-context {:theme {:name :dark}
                                    :set-theme (fn [self theme]
                                                 (set self.theme theme))}})
  (set app.scene {:build-context {}
                  :build-default (fn [_self _payload] true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                      :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] (error "theme rebuild failed"))
                   :get-active-theme (fn [] {:name :light})})
  (local runtime {})
  (set app.active-world-runtime runtime)
  (set app.active-world-entry {:world {:runtime runtime
                                        :state {:scene {:terrains []}}}})
  (var activate-fails? false)
  (Activities.register-activity
    {:id "graph"
     :label "Graph"
     :activate (fn [_ctx]
                 (if activate-fails?
                     (error "reactivation failed")
                     {:mode-owned? true}))
     :deactivate (fn [_ctx _session] true)})
  (Activities.activate-activity "graph")
  (set activate-fails? true)
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light))))
  (Activities.unregister-activity "graph")
  (set app.settings original-settings)
  (set app.themes original-themes)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.renderers original-renderers)
  (set app.graph-view original-graph-view)
  (set app.canvas original-canvas)
  (set app.graph original-graph)
  (set app.apply-active-world-hud-contrib original-apply-active-world-hud-contrib)
  (set app.active-world-entry original-active-world-entry)
  (set app.active-world-runtime original-active-world-runtime)
  (set app.activity-registry original-registry)
  (set app.activities-changed original-modes-changed)
  (set app.active-activity-id original-active-activity-id)
  (assert (not ok)
          "apply-theme should surface original error when mode reactivation also fails")
  (assert (and err (string.find err "theme rebuild failed" 1 true))
          "apply-theme should report the original theme error")
  (assert (and err (string.find err "reactivation failed" 1 true))
          "apply-theme should also report the mode reactivation error")
  true)

(table.insert tests {:name "Apply theme surfaces reactivation failure alongside original error"
                     :fn apply-theme-surfaces-reactivation-failure})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "theme-switch"
                       :tests tests})))

{:name "theme-switch"
 :tests tests
 :main main}
