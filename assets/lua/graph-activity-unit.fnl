(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local Activities (require :activities))
(local GraphView (require :graph/view))
(local GraphActivityActions (require :graph-activity-actions))
(local {: entry : section} (require :command-hints))

(fn graph-activity-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (local graph-view-root (fs.join-path (fs.join-path lua-root "graph") "view"))
  [(fs.join-path lua-root "graph-activity-unit.fnl")
   (fs.join-path lua-root "graph-activity-actions.fnl")
   (fs.join-path lua-root "graph/view.fnl")
   graph-view-root
   (fs.join-path lua-root "graph-view-control-view.fnl")])

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
  (local graph (assert world-runtime.graph
                        "Graph activity requires runtime.graph"))
  (local object-selector (assert world-runtime.object-selector
                                   "Graph activity requires runtime.object-selector"))
  (local slot (canvas:activate-activity-slot "graph"))
  (slot:set-canvas-target-kind! :graph-view)
  (local graph-view
    (or world-runtime.graph-view
        (GraphView {:graph graph
                    :ctx slot.ctx
                    :movables world-runtime.movables
                    :selector object-selector
                    :view-target canvas
                    :pointer-target slot.pointer-target
                    :camera world-runtime.canvas-camera
                    :data-dir (assert world-runtime.world-dir
                                      "Graph activity requires runtime.world-dir")})))
  (set slot.root graph-view)
  (set world-runtime.graph-view graph-view)
  (set app.graph-view graph-view)
  (when world-runtime.graph-view-state
    (graph-view:restore-state world-runtime.graph-view-state))
  graph-view)

(fn capture-graph-view-state! []
  (local world-runtime app.active-world-runtime)
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when (and world-runtime graph-view graph-view.capture-state)
    (set world-runtime.graph-view-state (graph-view:capture-state)))
  (and world-runtime world-runtime.graph-view-state))

(fn deactivate-graph-view! []
  (capture-graph-view-state!)
  (local world-runtime app.active-world-runtime)
  (local canvas (and world-runtime world-runtime.canvas))
  (when canvas
    (canvas:deactivate-activity-slot "graph"))
  (set app.graph-view nil)
  true)

(fn drop-graph-view! []
  (capture-graph-view-state!)
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
    (set world-runtime.graph-view nil))
  (set app.graph-view nil)
  true)

(fn graph-activity-update [payload]
  (local world-runtime (and payload payload.runtime))
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when graph-view
    (graph-view:update (and payload payload.delta)))
  nil)

(fn activate-activity! [ctx]
  (ctx:defer-cleanup! drop-graph-view!)
  (local graph-view (activate-graph-view!))
  (ctx:set-root-actions! root-actions)
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
  (deactivate-graph-view!))

(fn snapshot-graph-activity! []
  {:active? (= (Activities.active-activity-id) "graph")
   :graph-view-state (capture-graph-view-state!)})

(fn restore-state-arg [first _session maybe-state]
  (if (and first (. first :activity))
      maybe-state
      first))

(fn restore-graph-activity! [first session maybe-state]
  (local state (restore-state-arg first session maybe-state))
  (when (and app.active-world-runtime state state.graph-view-state)
    (set app.active-world-runtime.graph-view-state state.graph-view-state))
  (when (and state state.active?)
        (if (and (= (Activities.active-activity-id) "graph")
                 app.graph-view
                 state.graph-view-state)
            (app.graph-view:restore-state state.graph-view-state)
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
