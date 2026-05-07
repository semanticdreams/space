(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local CanvasModes (require :canvas-modes))
(local GraphCanvasModeActions (require :graph-canvas-mode-actions))
(local {: entry : section} (require :command-hints))

(fn graph-mode-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  [(fs.join-path lua-root "graph-canvas-mode-unit.fnl")
   (fs.join-path lua-root "graph-canvas-mode-actions.fnl")])

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

(fn activate-mode! [ctx]
  (ctx:set-root-actions! root-actions)
  (ctx:set-selection-actions! nil)
  (ctx:set-activate-focused! activate-focused-node)
  (ctx:set-delete-selection! delete-selection)
  (ctx:set-command-hints-provider! graph-command-hints)
  (ctx:set-context-enricher! enrich-graph-context!)
  (ctx:set-target-enabled! graph-target-enabled?)
  {:mode-id "graph"})

(fn deactivate-mode! [_ctx _session]
  true)

(fn snapshot-graph-canvas-mode! []
  {:active? (= (CanvasModes.active-mode-id) "graph")})

(fn restore-graph-canvas-mode! [state]
  (when (and state state.active?)
    (CanvasModes.activate-mode "graph"))
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
       :deactivate deactivate-mode!}))
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
