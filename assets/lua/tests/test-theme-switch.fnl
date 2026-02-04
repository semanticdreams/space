(local tests [])

(local AppBootstrap (require :app-bootstrap))
(local BuildContext (require :build-context))
(local ControlPanel (require :hud-control-panel))
(local Icons (require :icons))
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
  (local themes (Themes))
  (themes.add-theme :dark (require :dark-theme))
  (themes.add-theme :light (require :light-theme))
  (themes.set-theme :dark)
  (set app.themes themes)
  (local settings-state {:value nil :saved false})
  (set app.settings
       {:set-value (fn [_key value _opts]
                     (set settings-state.value value)
                     value)
        :save (fn []
                (set settings-state.saved true))})
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
  (assert (= (themes.get-active-theme-name) :light))
  (assert (= settings-state.value "light"))
  (assert settings-state.saved)
  (when panel
    (panel:drop))
  (when icons
    (icons:drop))
  (set app.icons previous-icons)
  (set app.settings previous-settings)
  (set app.themes previous-themes)
  true)

(table.insert tests {:name "Init themes uses stored UI theme" :fn init-themes-reads-settings})
(table.insert tests {:name "Control panel toggles theme" :fn control-panel-toggles-theme})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "theme-switch"
                       :tests tests})))

{:name "theme-switch"
 :tests tests
 :main main}
