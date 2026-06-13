(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local CanvasModes (require :canvas-modes))
(local GraphView (require :graph/view))
(local GraphCanvasModeActions (require :graph-canvas-mode-actions))
(local {: entry : section} (require :command-hints))

(fn graph-mode-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (local graph-view-root (fs.join-path (fs.join-path lua-root "graph") "view"))
  [(fs.join-path lua-root "graph-canvas-mode-unit.fnl")
   (fs.join-path lua-root "graph-canvas-mode-actions.fnl")
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
  (local graph (assert world-runtime.graph
                       "Graph canvas mode requires runtime.graph"))
  (local object-selector (assert world-runtime.object-selector
                                 "Graph canvas mode requires runtime.object-selector"))
  (when world-runtime.graph-view
    (world-runtime.graph-view:drop)
    (set world-runtime.graph-view nil))
  (local graph-view
    (GraphView {:graph graph
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
  (when world-runtime.graph-view-state
    (graph-view:restore-state world-runtime.graph-view-state))
  graph-view)

(fn capture-graph-view-state! []
  (local world-runtime app.active-world-runtime)
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when (and world-runtime graph-view graph-view.capture-state)
    (set world-runtime.graph-view-state (graph-view:capture-state)))
  (and world-runtime world-runtime.graph-view-state))

(fn drop-graph-view! []
  (capture-graph-view-state!)
  (local world-runtime app.active-world-runtime)
  (local graph-view (or (and world-runtime world-runtime.graph-view)
                        app.graph-view))
  (when graph-view
    (graph-view:drop))
  (when world-runtime
    (set world-runtime.graph-view nil))
  (set app.graph-view nil)
  true)

(fn graph-mode-update [payload]
  (local world-runtime (and payload payload.runtime))
  (local graph-view (and world-runtime world-runtime.graph-view))
  (when graph-view
    (graph-view:update (and payload payload.delta)))
  nil)

(fn activate-mode! [ctx]
  (ctx:defer-cleanup! drop-graph-view!)
  (local graph-view (create-graph-view!))
  (ctx:set-root-actions! root-actions)
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
  (when (and app.active-world-runtime state state.graph-view-state)
    (set app.active-world-runtime.graph-view-state state.graph-view-state))
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
