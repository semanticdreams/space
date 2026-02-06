(fn copy-list [items]
  (local result [])
  (when items
    (each [_ item (ipairs items)]
      (table.insert result item)))
  result)

(fn rebuild-graph-view [selected]
  (when app.graph-view
    (app.graph-view:drop)
    (set app.graph-view nil))
  (when (and app.graph app.scene app.hud)
    (local GraphView (require :graph/view))
    (set app.graph-view (GraphView {:graph app.graph
                                    :ctx (and app.scene app.scene.build-context)
                                    :movables app.movables
                                    :selector app.object-selector
                                    :view-target app.hud
                                    :camera app.camera
                                    :pointer-target app.scene}))
    (when (and selected app.graph-view.selection)
      (app.graph-view.selection:set-selection selected))))

(fn apply-theme [theme-name]
  (local previous-selected
    (and app.graph-view app.graph-view.selection
         (copy-list app.graph-view.selection.selected-nodes)))
  (local themes app.themes)
  (when (and themes themes.set-theme)
    (themes.set-theme theme-name))
  (when (and app.settings app.settings.set-value app.settings.save)
    (app.settings.set-value "ui.theme"
                            (if (= theme-name :light) "light" "dark")
                            {:save? false})
    (app.settings.save))
  (when (and app.scene app.scene.build-default)
    (app.scene:build-default))
  (when (and app.hud app.hud.build-default)
    (app.hud:build-default))
  (when (and app.renderers app.renderers.apply-theme)
    (app.renderers:apply-theme (and app.themes (app.themes.get-active-theme))))
  (rebuild-graph-view previous-selected))

(fn toggle-theme []
  (local themes app.themes)
  (local current (and themes themes.get-active-theme-name (themes.get-active-theme-name)))
  (local next (if (= current :light) :dark :light))
  (apply-theme next))

{:apply-theme apply-theme
 :toggle-theme toggle-theme}

