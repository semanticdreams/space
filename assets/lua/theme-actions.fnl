(local PanelUtils (require :target-panel-utils))
(local SkyboxState (require :skybox-state))
(local PhysicsContainment (require :physics-containment))

(fn copy-list [items]
  (local result [])
  (when items
    (each [_ item (ipairs items)]
      (table.insert result item)))
  result)

(fn capture-target-panel-state [target kind]
  (local panels [])
  (when (and target
             target.capture-panel-element-state)
    (each [_ record (ipairs (PanelUtils.persistent-panels target {:kind kind}))]
      (local panel-state (target:capture-panel-element-state record.element))
      (when panel-state
        (local panel-record (PanelUtils.clone-table record.persistence))
        (each [key value (pairs panel-state)]
          (set (. panel-record key) value))
        (table.insert panels panel-record))))
  {:target target
   :panels panels})

(fn capture-graph-node-view-panel-states []
  (local seen {})
  (local captured [])
  (each [_ target (ipairs [app.scene app.canvas app.hud])]
    (when (and target (not (. seen target)))
      (set (. seen target) true)
      (table.insert captured
                    (capture-target-panel-state target "graph-node-view"))))
  captured)

(fn restore-panel-state [snapshot]
  (when (and snapshot
             snapshot.target
             snapshot.target.restore-state
             (> (length (or snapshot.panels [])) 0))
    (snapshot.target:restore-state {:panels snapshot.panels})))

(fn rebuild-graph-view [selected panel-states]
  (when app.graph-view
    (app.graph-view:drop)
    (set app.graph-view nil))
  (when (and app.graph (or app.canvas app.scene) app.hud)
    (local GraphView (require :graph/view))
    (local ctx (or (and app.canvas app.canvas.build-context)
                   (and app.scene app.scene.build-context)))
    (local active-theme
      (and app.themes app.themes.get-active-theme
           (app.themes.get-active-theme)))
    (when (and ctx ctx.set-theme active-theme)
      (ctx:set-theme active-theme))
    (local view-target (or app.canvas app.hud))
    (local pointer-target (or app.canvas app.scene))
    (local camera (or (and app.canvas app.canvas.camera) app.camera))
    (set app.graph-view (GraphView {:graph app.graph
                                    :ctx ctx
                                    :movables app.movables
                                    :selector app.object-selector
                                    :view-target view-target
                                    :camera camera
                                    :pointer-target pointer-target}))
    (when (and app.active-world-entry
               app.active-world-entry.world
               app.active-world-entry.world.runtime)
      (set (. app.active-world-entry.world.runtime :graph-view) app.graph-view))
    (when (and selected app.graph-view.selection)
      (app.graph-view.selection:set-selection selected))
    (each [_ snapshot (ipairs (or panel-states []))]
      (restore-panel-state snapshot))))

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

(fn apply-theme [theme-name]
  (local previous-selected
    (and app.graph-view app.graph-view.selection
         (copy-list app.graph-view.selection.selected-nodes)))
  (local graph-node-view-panels
    (capture-graph-node-view-panel-states))
  (local themes app.themes)
  (when (and themes themes.set-theme)
    (themes.set-theme theme-name))
  (when (and app.settings app.settings.set-value app.settings.save)
    (app.settings.set-value "ui.theme"
                            (tostring theme-name)
                            {:save? false})
    (app.settings.save))
  (when (and app.scene app.scene.build-default)
    (app.scene:build-default))
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
  (rebuild-graph-view previous-selected graph-node-view-panels))

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
