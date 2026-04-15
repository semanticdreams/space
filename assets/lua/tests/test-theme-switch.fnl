(local tests [])

(local AppBootstrap (require :app-bootstrap))
(local BuildContext (require :build-context))
(local ControlPanel (require :hud-control-panel))
(local Icons (require :icons))
(local PanelUtils (require :target-panel-utils))
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
  (local restored-states [])
  (local rebuilt-selections [])
  (local node {:key "node-a"})
  (local panel-element {:layout {}})
  (local panel-metadata {:element panel-element
                         :persistence {:kind "graph-node-view"
                                       :node-key node.key}})
  (local canvas {:build-context {}
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
  (set app.active-world-entry {:world {:runtime {}}})
  (assert (= (length (PanelUtils.persistent-panels canvas {:kind "graph-node-view"})) 1)
          "test setup should expose one persisted graph node view panel on the canvas")
  (set app.graph-view
       {:selection {:selected-nodes [node]}
        :drop (fn [_self]
                (set drop-calls (+ drop-calls 1))
                (set canvas.float.children []))})
  (set (. package.loaded "graph/view")
       (fn [_opts]
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

(table.insert tests {:name "Init themes uses stored UI theme" :fn init-themes-reads-settings})
(table.insert tests {:name "Control panel toggles theme" :fn control-panel-toggles-theme})
(table.insert tests {:name "Apply theme restores graph node view panels on their target"
                     :fn apply-theme-restores-graph-node-view-panels-on-target})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "theme-switch"
                       :tests tests})))

{:name "theme-switch"
 :tests tests
 :main main}
