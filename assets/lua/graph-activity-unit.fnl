(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local Activities (require :activities))
(local GraphView (require :graph/view))
(local GraphActivityActions (require :graph-activity-actions))
(local GraphMapSidebar (require :graph/map-sidebar))
(local {: entry : section} (require :command-hints))

(var maps-changed-handler nil)
(var maps-will-change-handler nil)

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn graph-activity-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (local graph-view-root (fs.join-path (fs.join-path lua-root "graph") "view"))
  [(fs.join-path lua-root "graph-activity-unit.fnl")
    (fs.join-path lua-root "graph-activity-actions.fnl")
    (fs.join-path lua-root "graph/view.fnl")
    (fs.join-path lua-root "graph/map-sidebar.fnl")
    graph-view-root
    (fs.join-path lua-root "graph-view-control-view.fnl")])

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
      (and world-runtime world-runtime.graph-map)
      app.graph-map))

(fn ensure-view-states [world-runtime]
  (when (not world-runtime.graph-view-states)
    (set world-runtime.graph-view-states {})))

(fn view-state-key-for [graph-map]
  (if graph-map
      (or graph-map.id "main")
      "main"))

(fn view-state-key []
  (view-state-key-for (active-graph-map)))

(fn normalize-legacy-graph-view-state [state map-id]
  (local normalized (clone-table state))
  (local open-views (and normalized normalized.views normalized.views.open-views))
  (when (= (type open-views) :table)
    (each [_ entry (ipairs open-views)]
      (when (and (= (type entry) :table)
                 (= entry.graph-map-id nil))
        (set entry.graph-map-id map-id))))
  normalized)

(fn restore-graph-view-state! [graph-view state map-id]
  (when state
    (graph-view:restore-state (normalize-legacy-graph-view-state state (or map-id "main")))))

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
         :selected-nodes (GraphActivityActions.selected-graph-nodes graph-view)})
  context)

(fn graph-target-enabled? [target]
  (local target-kind (and target target.canvas-target-kind))
  (or (= target-kind nil)
      (= target-kind :graph-view)))

(fn root-actions [context]
  ((. GraphActivityActions :graph-root-actions) context))

(fn activate-graph-view! []
  (local world-runtime (assert app.active-world-runtime
                                 "Graph activity requires app.active-world-runtime"))
  (local canvas (assert world-runtime.canvas
                          "Graph activity requires runtime.canvas"))
  (local graph-map (active-graph-map))
  (assert graph-map
          "Graph activity requires runtime.graph-map or graph-map-manager")
  (local object-selector (assert world-runtime.object-selector
                                    "Graph activity requires runtime.object-selector"))
  (local slot (canvas:activate-activity-slot "graph"))
  (slot:set-canvas-target-kind! :graph-view)
  (ensure-view-states world-runtime)
  (local map-id (view-state-key-for graph-map))
  (when (and world-runtime.graph-view
             (not (= world-runtime.graph-view-map-id map-id)))
    (capture-graph-view-state-for-key! world-runtime.graph-view-map-id)
    (world-runtime.graph-view:drop)
    (set world-runtime.graph-view nil))
  (local graph-view
    (or world-runtime.graph-view
        (GraphView {:graph-map graph-map
                     :ctx slot.ctx
                     :movables world-runtime.movables
                     :selector object-selector
                     :view-target slot
                     :pointer-target slot.pointer-target
                    :camera world-runtime.canvas-camera
                    :data-dir (assert world-runtime.world-dir
                                      "Graph activity requires runtime.world-dir")})))
   (set slot.root graph-view)
  (set world-runtime.graph-view graph-view)
  (set world-runtime.graph-view-map-id map-id)
  (set app.graph-view graph-view)
  (set app.graph-map graph-map)
  (local stored-state (. world-runtime.graph-view-states map-id))
  (if stored-state
      (restore-graph-view-state! graph-view stored-state map-id)
      world-runtime.graph-view-state
      (do
        (restore-graph-view-state! graph-view world-runtime.graph-view-state map-id)
        (set world-runtime.graph-view-state nil))
      (do
        (when (and graph-view.persistence graph-view.persistence.saved-panels)
          (local saved-panels (graph-view.persistence:saved-panels))
          (when (and saved-panels (> (length saved-panels) 0))
            (graph-view:restore-views-state {:open-views saved-panels})))
        (when (and graph-view.persistence graph-view.persistence.saved-extra-panels)
          (local saved-extra-panels (graph-view.persistence:saved-extra-panels))
          (when (and saved-extra-panels (> (length saved-extra-panels) 0))
            (graph-view:restore-state {:extra_panels saved-extra-panels})))))
  graph-view)

(fn capture-graph-view-state! []
  (local world-runtime app.active-world-runtime)
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when (and world-runtime graph-view graph-view.capture-state)
    (ensure-view-states world-runtime)
    (set (. world-runtime.graph-view-states (or world-runtime.graph-view-map-id
                                                (view-state-key)))
         (graph-view:capture-state)))
  (and world-runtime
       (. (or world-runtime.graph-view-states {})
          (or world-runtime.graph-view-map-id (view-state-key)))))

(fn deactivate-graph-view! []
  (capture-graph-view-state!)
  (local world-runtime app.active-world-runtime)
  (local canvas (and world-runtime world-runtime.canvas))
  (when canvas
    (canvas:deactivate-activity-slot "graph"))
  (set app.graph-view nil)
  true)

(fn drop-graph-view! [skip-capture?]
  (when (not skip-capture?)
    (capture-graph-view-state!))
  (local world-runtime app.active-world-runtime)
  (local graph-view (or (and world-runtime world-runtime.graph-view)
                         app.graph-view))
  (local canvas (and world-runtime world-runtime.canvas))
  (local slot (and canvas (canvas:activity-slot "graph")))
  (when slot
    (set slot.root nil))
  (when graph-view
    (graph-view:drop))
  (when canvas
    (canvas:deactivate-activity-slot "graph"))
  (when world-runtime
    (set world-runtime.graph-view nil)
    (set world-runtime.graph-view-map-id nil))
  (set app.graph-view nil)
  (set app.graph-map (and world-runtime (active-graph-map)))
  true)

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

(fn capture-and-drop-view-before-map-switch [payload]
  (when (and (= (Activities.active-activity-id) "graph")
             payload payload.active-id payload.previous-id
             (not= payload.active-id payload.previous-id))
    (when app.graph-view
      (local world-runtime app.active-world-runtime)
      (local scene (and world-runtime world-runtime.scene))
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
  (when (and (= (Activities.active-activity-id) "graph")
             payload payload.active-id payload.previous-id
             (not= payload.active-id payload.previous-id))
    (local world-runtime app.active-world-runtime)
    (when world-runtime
      (set world-runtime.graph-map (active-graph-map))
      (set app.graph-map world-runtime.graph-map)
      (when (and world-runtime.scene world-runtime.scene.set-graph-map)
        (world-runtime.scene:set-graph-map world-runtime.graph-map))
      (activate-graph-view!))))

(fn graph-activity-update [payload]
  (local world-runtime (and payload payload.runtime))
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when graph-view
    (graph-view:update (and payload payload.delta)))
  nil)

(fn activate-activity! [ctx]
  (ctx:defer-cleanup! drop-graph-view!)
  (local graph-view (activate-graph-view!))
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
  (ctx:set-update! graph-activity-update)
  (ctx:set-surface-state! {:canvas {:visible? true :interactive? true}})
  (ctx:set-preferred-interaction-surface! :canvas)
  {:activity-id "graph"
   :graph-view graph-view})

(fn deactivate-activity! [_ctx _session]
  (disconnect-map-switch-handlers!)
  (deactivate-graph-view!))

(fn snapshot-graph-activity! []
  {:active? (= (Activities.active-activity-id) "graph")
   :graph-view-state (capture-graph-view-state!)
   :graph-view-states (clone-table (and app.active-world-runtime
                                        app.active-world-runtime.graph-view-states))})

(fn restore-state-arg [first _session maybe-state]
  (if (and first (. first :activity))
      maybe-state
      first))

(fn restore-graph-activity! [first session maybe-state]
  (local state (restore-state-arg first session maybe-state))
  (when (and app.active-world-runtime state)
    (when state.graph-view-states
      (set app.active-world-runtime.graph-view-states (clone-table state.graph-view-states)))
    (when state.graph-view-state
      (set app.active-world-runtime.graph-view-state state.graph-view-state)))
  (when (and state state.active?)
        (if (and (= (Activities.active-activity-id) "graph")
                  app.graph-view
                  state.graph-view-state)
            (restore-graph-view-state! app.graph-view state.graph-view-state (view-state-key))
            (if app.set-active-activity
                (app.set-active-activity "graph")
                (Activities.activate-activity "graph"))))
  true)

(fn activity-registered? [activity-id]
  (local (ok _resolved) (pcall Activities.resolve activity-id))
  ok)

(fn load-graph-activity! []
  (when (not (activity-registered? "graph"))
    (Activities.register-activity
      {:id "graph"
       :label "Graph"
       :icon "account_tree"
       :button-name "graph-activity"
       :show-in-switcher? true
       :activate activate-activity!
       :deactivate deactivate-activity!
       :snapshot snapshot-graph-activity!
       :restore restore-graph-activity!}))
  true)

(fn unload-graph-activity! []
  (local registered? (activity-registered? "graph"))
  (local active? (and registered?
                      (= (Activities.active-activity-id) "graph")))
  (when active?
    (if app.set-active-activity
        (app.set-active-activity nil)
        (Activities.deactivate-active-activity)))
  (when registered?
    (Activities.unregister-activity "graph"))
  true)

{:graph-activity-owned-paths graph-activity-owned-paths
 :load-graph-activity! load-graph-activity!
 :unload-graph-activity! unload-graph-activity!
 :snapshot-graph-activity! snapshot-graph-activity!
 :restore-graph-activity! restore-graph-activity!}
