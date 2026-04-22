(local tests [])

(local AppBootstrap (require :app-bootstrap))
(local BuildContext (require :build-context))
(local ControlPanel (require :hud-control-panel))
(local Icons (require :icons))
(local PanelUtils (require :target-panel-utils))
(local PhysicsContainment (require :physics-containment))
(local ThemeActions (require :theme-actions))
(local Themes (require :themes))

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

(fn apply-theme-restores-graph-node-view-panels-on-target []
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
  (local original-graph-view-module (. package.loaded "graph/view"))
  (var drop-calls 0)
  (var hud-rebuild-calls 0)
  (var graph-view-theme nil)
  (local restored-states [])
  (local rebuilt-selections [])
  (local node {:key "node-a"})
  (local panel-element {:layout {}})
  (local panel-metadata {:element panel-element
                         :persistence {:kind "graph-node-view"
                                       :node-key node.key}})
  (local canvas {:build-context {:theme {:name :dark}
                                 :set-theme (fn [self theme]
                                              (set self.theme theme))}
                 :float {:children [panel-metadata]}
                 :capture-panel-element-state
                 (fn [_self element]
                   (when (= element panel-element)
                     {:layer "float"
                      :position [1 2 3]
                      :rotation [1 0 0 0]
                      :size [7 8 9]}))
                 :restore-state (fn [_self state]
                                  (table.insert restored-states state)
                                  true)})
  (local themes {:set-theme (fn [_theme] true)
                 :get-active-theme (fn [] {:name :light})})
  (set app.graph {})
  (set app.canvas canvas)
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
  (assert (= (length (PanelUtils.persistent-panels canvas {:kind "graph-node-view"})) 1)
          "test setup should expose one persisted graph node view panel on the canvas")
  (set app.graph-view
       {:selection {:selected-nodes [node]}
        :drop (fn [_self]
                (set drop-calls (+ drop-calls 1))
                (set canvas.float.children []))})
  (set (. package.loaded "graph/view")
       (fn [_opts]
         (set graph-view-theme (and _opts.ctx _opts.ctx.theme _opts.ctx.theme.name))
         {:selection {:set-selection (fn [_self selected]
                                       (table.insert rebuilt-selections selected))}}))
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light)
        (assert (= hud-rebuild-calls 1)
                "apply-theme should rebuild the HUD through the active-world HUD helper")
        (assert (= drop-calls 1)
                "apply-theme should rebuild the graph view")
        (assert (= (length restored-states) 1)
                "apply-theme should restore graph node view panels through the target")
        (local restored (. restored-states 1))
        (assert (= (length (or restored.panels [])) 1)
                "apply-theme should restore the captured graph node view panel")
        (assert (= (and (. restored.panels 1) (. (. restored.panels 1) :node-key))
                   node.key)
                "apply-theme should restore the same node-key")
        (assert (= (and (. restored.panels 1) (. (. restored.panels 1) :layer))
                   "float")
                "apply-theme should restore the captured panel placement")
        (assert (= graph-view-theme :light)
                "apply-theme should rebuild graph view with the active theme on the build context")
        (assert (= (length rebuilt-selections) 1)
                "apply-theme should restore graph selection on the rebuilt view"))))
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
  (set (. package.loaded "graph/view") original-graph-view-module)
  (when (not ok)
    (error err))
  true)

(fn apply-theme-drops-graph-view-before-target-rebuild []
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
  (local original-graph-view-module (. package.loaded "graph/view"))
  (var panel-dropped? false)
  (var graph-drop-calls 0)
  (var hud-rebuild-calls 0)
  (var old-graph-view nil)
  (local node {:key "node-a"})
  (local panel-element
    {:layout {}
     :drop (fn [_self]
             (assert (not panel-dropped?) "graph node view panel dropped twice")
             (set panel-dropped? true))})
  (local panel-metadata {:element panel-element
                         :persistence {:kind "graph-node-view"
                                       :node-key node.key}})
  (local ctx {:theme {:name :dark}
              :set-theme (fn [self theme]
                           (set self.theme theme))})
  (local hud {:build-context ctx
              :tiles {:children [panel-metadata]}
              :capture-panel-element-state
              (fn [_self element]
                (when (= element panel-element)
                  {:layer "tiles"
                   :align-x :center
                   :align-y :start}))
              :remove-panel-child
              (fn [self element]
                (var removed false)
                (local kept [])
                (each [_ metadata (ipairs self.tiles.children)]
                  (if (and (not removed) (= metadata.element element))
                      (do
                        (set removed true)
                        (when (and element element.drop)
                          (element:drop)))
                      (table.insert kept metadata)))
                (set self.tiles.children kept)
                removed)
              :build-default
              (fn [self]
                (set hud-rebuild-calls (+ hud-rebuild-calls 1))
                (assert (not app.active-world-runtime.graph-view)
                        "old graph view teardown should clear app.active-world-runtime.graph-view before HUD rebuild")
                (assert (not app.active-world-entry.world.runtime.graph-view)
                        "old graph view teardown should clear active world runtime graph-view before HUD rebuild")
                (each [_ metadata (ipairs self.tiles.children)]
                  (local element (and metadata metadata.element))
                  (when (and element element.drop)
                    (element:drop)))
                true)
              :restore-state
              (fn [_self _state] true)})
  (set app.graph {})
  (set app.canvas nil)
  (set app.scene {:build-context ctx
                  :build-default (fn [_self _payload] true)})
  (set app.hud hud)
  (set app.apply-active-world-hud-contrib
       (fn []
         (hud:build-default)))
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                     :save (fn [] true)})
  (set app.themes {:set-theme (fn [_theme] true)
                   :get-active-theme (fn [] {:name :light})})
  (set app.graph-view
       {:selection {:selected-nodes [node]}
        :drop (fn [_self]
                (set graph-drop-calls (+ graph-drop-calls 1))
                (app.hud:remove-panel-child panel-element))})
  (set old-graph-view app.graph-view)
  (local runtime {:graph-view old-graph-view})
  (set app.active-world-runtime runtime)
  (set app.active-world-entry {:world {:runtime runtime
                                       :state {:scene {:terrains []}}}})
  (set (. package.loaded "graph/view")
       (fn [_opts]
         {:selection {:set-selection (fn [_self _selected] true)}}))
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light)
        (assert (= graph-drop-calls 1)
                "apply-theme should drop the old graph view exactly once")
        (assert (= hud-rebuild-calls 1)
                "apply-theme should rebuild the HUD after graph view teardown")
        (assert panel-dropped?
                "graph view panel should be dropped during old graph view teardown")
        (assert (= (length hud.tiles.children) 0)
                "old graph view teardown should detach graph node view panels before HUD rebuild")
        (assert app.active-world-runtime.graph-view
                "apply-theme should install the rebuilt graph view on the active runtime")
        (assert (not (= app.active-world-runtime.graph-view old-graph-view))
                "apply-theme should not leave the dropped graph view on the active runtime"))))
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
  (set (. package.loaded "graph/view") original-graph-view-module)
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

(fn apply-theme-preserves-active-world-terrains []
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
  (var scene-payload nil)
  (local terrain-record {:id "terrain-a"
                         :kind "heightfield-terrain"
                         :options {:position [1 2 3]
                                   :rotation [1 0 0 0]
                                   :chunk-samples [17 17]
                                   :chunk-size [16 16]
                                   :default-height 0.0}
                         :chunks [{:coord [0 0]
                                   :size [17 17]
                                   :heights [0]}]})
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.canvas nil)
  (set app.scene {:build-default (fn [_self payload]
                                   (set scene-payload payload)
                                   true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                     :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] true)
                   :get-active-theme (fn [] {:name :light})})
  (set app.active-world-entry {:world {:state {:scene {:terrains [terrain-record]}}}})
  (local (ok err)
    (pcall
      (fn []
        (ThemeActions.apply-theme :light)
        (assert scene-payload "apply-theme should pass a scene payload to build-default when an active world exists")
        (assert (= (length (or scene-payload.terrains [])) 1)
                "apply-theme should preserve the active world terrain list during scene rebuild")
        (assert (= (and (. scene-payload.terrains 1) (. (. scene-payload.terrains 1) :id))
                   "terrain-a")
                "apply-theme should rebuild the scene with the persisted terrain id")
        (assert (not (= (. scene-payload.terrains 1) terrain-record))
                "apply-theme should clone persisted terrain records before handing them to the scene rebuild"))))
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
  (when (not ok)
    (error err))
  true)

(fn apply-theme-requires-active-world-terrain-state []
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
  (set app.scene {:build-default (fn [_self _payload] true)})
  (set app.hud {:build-default (fn [_self] true)})
  (set app.apply-active-world-hud-contrib nil)
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.settings {:set-value (fn [_key _value _opts] true)
                     :save (fn [] true)})
  (set app.themes {:set-theme (fn [_name] true)
                   :get-active-theme (fn [] {:name :light})})
  (set app.active-world-entry {:world {:state {:scene {}}}})
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
  (assert (not ok)
          "apply-theme should fail loudly when active world terrain state is missing")
  (assert (and err (string.find err "ThemeActions.apply-theme requires active world scene terrains" 1 true))
          "apply-theme should report that active world scene terrains are required")
  true)

(table.insert tests {:name "Init themes uses stored UI theme" :fn init-themes-reads-settings})
(table.insert tests {:name "Init themes falls back for unknown stored UI theme"
                     :fn init-themes-falls-back-for-unknown-stored-theme})
(table.insert tests {:name "Themes set-theme resolves string key"
                     :fn themes-set-theme-resolves-string-key})
(table.insert tests {:name "Control panel toggles theme" :fn control-panel-toggles-theme})
(table.insert tests {:name "Apply theme restores graph node view panels on their target"
                     :fn apply-theme-restores-graph-node-view-panels-on-target})
(table.insert tests {:name "Apply theme drops graph view before target rebuild"
                     :fn apply-theme-drops-graph-view-before-target-rebuild})
(table.insert tests {:name "Apply theme saves exact theme key"
                     :fn apply-theme-saves-exact-theme-key})
(table.insert tests {:name "Apply theme refreshes physics containment visualization"
                     :fn apply-theme-refreshes-physics-containment-visualization})
(table.insert tests {:name "Apply theme preserves active world terrains"
                     :fn apply-theme-preserves-active-world-terrains})
(table.insert tests {:name "Apply theme requires active world terrain state"
                     :fn apply-theme-requires-active-world-terrain-state})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "theme-switch"
                       :tests tests})))

{:name "theme-switch"
 :tests tests
 :main main}
