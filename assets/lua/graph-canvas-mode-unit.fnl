(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local CanvasModes (require :canvas-modes))
(local GraphView (require :graph/view))
(local GraphCanvasModeActions (require :graph-canvas-mode-actions))
(local GraphMapSidebar (require :graph/map-sidebar))
(local {: entry : section} (require :command-hints))

(fn graph-mode-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (local graph-view-root (fs.join-path (fs.join-path lua-root "graph") "view"))
  [(fs.join-path lua-root "graph-canvas-mode-unit.fnl")
   (fs.join-path lua-root "graph-canvas-mode-actions.fnl")
   (fs.join-path lua-root "graph/view.fnl")
   (fs.join-path lua-root "graph/map-sidebar.fnl")
   graph-view-root
   (fs.join-path lua-root "graph-view-control-view.fnl")])

(var maps-changed-handler nil)
(var maps-will-change-handler nil)

(fn graph-left-dock-builder [ctx]
  (local world-runtime app.active-world-runtime)
  (local manager (and world-runtime world-runtime.graph-map-manager))
  (when manager
      ((GraphMapSidebar.GraphMapSidebar
         {:manager manager
          :selected-count-provider
          (fn []
            (if (and app.graph-view app.graph-view.selection app.graph-view.selection.selected-nodes)
                (length app.graph-view.selection.selected-nodes)
                0))})
       ctx)))

(fn active-graph-map []
    (local world-runtime app.active-world-runtime)
    (or (and world-runtime world-runtime.graph-map-manager
             (world-runtime.graph-map-manager:get-active-map))
        (and world-runtime world-runtime.graph-map)))

(fn ensure-view-states [world-runtime]
    (when (not world-runtime.graph-view-states)
        (set world-runtime.graph-view-states {})))

(fn view-state-key-for [graph-map]
    (if graph-map
        (or graph-map.id "main")
        "main"))

(fn view-state-key []
    (view-state-key-for (active-graph-map)))

(fn capture-graph-view-state-for-key! [map-id]
  (local world-runtime app.active-world-runtime)
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when (and world-runtime graph-view graph-view.capture-state)
    (ensure-view-states world-runtime)
    (set (. world-runtime.graph-view-states (or map-id "main"))
         (graph-view:capture-state)))
  (and world-runtime
       (. (or world-runtime.graph-view-states {}) (or map-id "main"))))

(fn activate-focused-node []
  (local graph-view app.graph-view)
  (and graph-view
       graph-view.open-focused-node
       (graph-view:open-focused-node)))

(fn delete-selection []
  (local graph-view app.graph-view)
  (and graph-view
       graph-view.remove-selected-nodes
       (> (graph-view:remove-selected-nodes) 0)))

(fn graph-selection-count []
  (local graph-view app.graph-view)
  (if (and graph-view graph-view.selection graph-view.selection.selected-nodes)
      (length graph-view.selection.selected-nodes)
      0))

(fn graph-command-hints [_payload]
  (if (> (graph-selection-count) 0)
      [(section :context "CONTEXT"
                [(entry "del" "delete-selection" {:priority 10})])]
      []))

(fn enrich-graph-context! [context]
  (local graph-view app.graph-view)
  (set context.graph
       {:graph app.graph
        :graph-map app.graph-map
        :view graph-view
        :selected-nodes (GraphCanvasModeActions.selected-graph-nodes graph-view)})
  context)

(fn graph-target-enabled? [target]
  (local target-kind (and target target.canvas-target-kind))
  (or (= target-kind nil)
      (= target-kind :graph-view)))

(fn root-actions [context]
  ((. GraphCanvasModeActions :graph-root-actions) context))

(fn make-graph-canvas-target [canvas]
  {:interaction-surface :canvas
   :canvas-target-kind :graph-view
   :screen-pos-ray (fn [_self pos opts]
                     (canvas:screen-pos-ray pos opts))})

(fn create-graph-view! []
  (local world-runtime (assert app.active-world-runtime
                               "Graph canvas mode requires app.active-world-runtime"))
  (local canvas (assert world-runtime.canvas
                        "Graph canvas mode requires runtime.canvas"))
  (local graph-map (active-graph-map))
  (assert graph-map
          "Graph canvas mode requires runtime.graph-map or graph-map-manager")
  (local object-selector (assert world-runtime.object-selector
                                 "Graph canvas mode requires runtime.object-selector"))
  (ensure-view-states world-runtime)
  (when world-runtime.graph-view
    (world-runtime.graph-view:drop)
    (set world-runtime.graph-view nil))
  (local graph-view
    (GraphView {:graph-map graph-map
                :ctx canvas.build-context
                :movables world-runtime.movables
                :selector object-selector
                :view-target canvas
                :camera world-runtime.canvas-camera
                :pointer-target (make-graph-canvas-target canvas)
                :data-dir (assert world-runtime.world-dir
                                  "Graph canvas mode requires runtime.world-dir")}))
  (set world-runtime.graph-view graph-view)
  (set app.graph-view graph-view)
  (set app.graph-map graph-map)
  (local stored-state (. world-runtime.graph-view-states (view-state-key)))
  (when stored-state
    (graph-view:restore-state stored-state))
  (when (and (not stored-state) graph-view.persistence graph-view.persistence.saved-panels)
    (local saved-panels (graph-view.persistence:saved-panels))
    (when (and saved-panels (> (length saved-panels) 0))
      (graph-view:restore-views-state {:open-views saved-panels})))
  (when (and (not stored-state) graph-view.persistence graph-view.persistence.saved-extra-panels)
    (local saved-extra-panels (graph-view.persistence:saved-extra-panels))
    (when (and saved-extra-panels (> (length saved-extra-panels) 0))
      (graph-view:restore-state {:extra_panels saved-extra-panels})))
  graph-view)

(fn capture-graph-view-state! []
  (local world-runtime app.active-world-runtime)
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when (and world-runtime graph-view graph-view.capture-state)
    (ensure-view-states world-runtime)
    (set (. world-runtime.graph-view-states (view-state-key))
         (graph-view:capture-state)))
  (and world-runtime
       (. (or world-runtime.graph-view-states {}) (view-state-key))))

(fn drop-graph-view! [skip-capture?]
  (when (not skip-capture?)
    (capture-graph-view-state!))
  (local world-runtime app.active-world-runtime)
  (local graph-view (or (and world-runtime world-runtime.graph-view)
                        app.graph-view))
  (when graph-view
    (graph-view:drop))
  (when world-runtime
    (set world-runtime.graph-view nil))
  (set app.graph-view nil)
  (set app.graph-map (and world-runtime (active-graph-map)))
  true)

(fn capture-and-drop-view-before-map-switch [payload]
  (when (and payload payload.active-id payload.previous-id
             (not= payload.active-id payload.previous-id))
    (when app.graph-view
      (local world-runtime app.active-world-runtime)
      (local scene (and world-runtime world-runtime.scene))
      ;; Capture live scene graph-node-cube panels into the view's extra_panels
      ;; so they survive the map switch.
      (when (and app.graph-view.extra-panels scene scene.scene-children)
        (each [_ metadata (ipairs scene.scene-children)]
          (when (and metadata metadata.persistence
                     (= metadata.persistence.kind "graph-node-cube"))
            (local element metadata.element)
            (local panel-state
              (when (and scene.capture-panel-element-state element)
                (scene:capture-panel-element-state element)))
            (table.insert app.graph-view.extra-panels
                          {:kind "graph-node-cube"
                           :node-key metadata.persistence.node-key
                           :graph-map-id metadata.persistence.graph-map-id
                           :restorer-module nil
                           :target-kind "scene"
                           :panel {:node-key metadata.persistence.node-key
                                   :label metadata.persistence.label
                                   :size (or (and panel-state panel-state.size)
                                            metadata.persistence.size)
                                   :position (or (and panel-state panel-state.position))
                                   :rotation (or (and panel-state panel-state.rotation))
                                   :graph-map-id metadata.persistence.graph-map-id}}))))
      (capture-graph-view-state-for-key! payload.previous-id)
      (drop-graph-view! true))))

(fn rebuild-graph-view-on-map-switch [payload]
  (when (and payload payload.active-id payload.previous-id
             (not= payload.active-id payload.previous-id))
    (local world-runtime app.active-world-runtime)
    (when world-runtime
      (set world-runtime.graph-map (active-graph-map))
      (set app.graph-map world-runtime.graph-map)
      (when (and world-runtime.scene world-runtime.scene.set-graph-map)
        (world-runtime.scene:set-graph-map world-runtime.graph-map))
      (create-graph-view!))))

(fn graph-mode-update [payload]
  (local world-runtime (and payload payload.runtime))
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when graph-view
    (graph-view:update (and payload payload.delta)))
  nil)

(fn disconnect-map-switch-handlers! []
  (local world-runtime app.active-world-runtime)
  (when maps-changed-handler
    (when (and world-runtime world-runtime.graph-map-manager)
      (world-runtime.graph-map-manager.maps-changed:disconnect maps-changed-handler true))
    (set maps-changed-handler nil))
  (when maps-will-change-handler
    (when (and world-runtime world-runtime.graph-map-manager)
      (world-runtime.graph-map-manager.maps-will-change:disconnect maps-will-change-handler true))
    (set maps-will-change-handler nil))
  true)

(fn activate-mode! [ctx]
  (ctx:defer-cleanup! drop-graph-view!)
  (local graph-view (create-graph-view!))
  (disconnect-map-switch-handlers!)
  (local world-runtime app.active-world-runtime)
  (when (and world-runtime world-runtime.graph-map-manager)
    (set maps-changed-handler
         (world-runtime.graph-map-manager.maps-changed:connect rebuild-graph-view-on-map-switch))
    (set maps-will-change-handler
         (world-runtime.graph-map-manager.maps-will-change:connect capture-and-drop-view-before-map-switch))
    (ctx:defer-cleanup! disconnect-map-switch-handlers!))
  (ctx:set-root-actions! root-actions)
  (ctx:set-left-dock-builder! graph-left-dock-builder)
  (ctx:set-selection-actions! nil)
  (ctx:set-activate-focused! activate-focused-node)
  (ctx:set-delete-selection! delete-selection)
  (ctx:set-command-hints-provider! graph-command-hints)
  (ctx:set-context-enricher! enrich-graph-context!)
  (ctx:set-target-enabled! graph-target-enabled?)
  (ctx:set-update! graph-mode-update)
  {:mode-id "graph"
   :graph-view graph-view})

(fn deactivate-mode! [_ctx _session]
  (disconnect-map-switch-handlers!)
  (drop-graph-view!))

(fn snapshot-graph-canvas-mode! []
  {:active? (= (CanvasModes.active-mode-id) "graph")
   :graph-view-state (capture-graph-view-state!)})

(fn restore-state-arg [first _session maybe-state]
  (if (and first (. first :mode))
      maybe-state
      first))

(fn restore-graph-canvas-mode! [first session maybe-state]
  (local state (restore-state-arg first session maybe-state))
  (local world-runtime app.active-world-runtime)
  (when (and world-runtime state state.graph-view-state)
    (ensure-view-states world-runtime)
    (set (. world-runtime.graph-view-states (view-state-key))
         state.graph-view-state))
  (when (and state state.active?)
    (if (and (= (CanvasModes.active-mode-id) "graph")
             app.graph-view
             state.graph-view-state)
        (app.graph-view:restore-state state.graph-view-state)
        (CanvasModes.activate-mode "graph")))
  true)

(fn mode-registered? [mode-id]
  (local (ok _resolved) (pcall CanvasModes.resolve mode-id))
  ok)

(fn load-graph-canvas-mode! []
  (when (not (mode-registered? "graph"))
    (CanvasModes.register-mode
      {:id "graph"
       :label "Graph"
       :icon "account_tree"
        :button-name "graph-canvas-mode"
        :show-in-sidebar? true
        :activate activate-mode!
        :deactivate deactivate-mode!
        :snapshot snapshot-graph-canvas-mode!
        :restore restore-graph-canvas-mode!}))
  true)

(fn unload-graph-canvas-mode! []
  (local registered? (mode-registered? "graph"))
  (local active? (and registered?
                      (= (CanvasModes.active-mode-id) "graph")))
  (when active?
    (CanvasModes.deactivate-active-mode))
  (when registered?
    (CanvasModes.unregister-mode "graph"))
  true)

{:graph-mode-owned-paths graph-mode-owned-paths
 :load-graph-canvas-mode! load-graph-canvas-mode!
 :unload-graph-canvas-mode! unload-graph-canvas-mode!
 :snapshot-graph-canvas-mode! snapshot-graph-canvas-mode!
 :restore-graph-canvas-mode! restore-graph-canvas-mode!}
