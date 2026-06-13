(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local CanvasModes (require :canvas-modes))
(local DrawingInput (require :drawing/input))
(local DrawingCanvasModeActions (require :drawing-canvas-mode-actions))

(fn drawing-mode-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  [(fs.join-path lua-root "drawing-canvas-mode-unit.fnl")
   (fs.join-path lua-root "drawing-canvas-mode-actions.fnl")
   (fs.join-path (fs.join-path lua-root "drawing") "input.fnl")
   (fs.join-path (fs.join-path lua-root "drawing") "sidebar-view.fnl")])

(fn drawing-left-dock-builder [ctx]
  (local DrawingSidebarView (require :drawing/sidebar-view))
  (if app.drawing-controller
      ((DrawingSidebarView {:controller app.drawing-controller})
       ctx)
      nil))

(fn enrich-drawing-context! [context]
  (local controller app.drawing-controller)
  (local active-layer
    (and controller controller.active-layer
         (controller:active-layer)))
  (local selection-count
    (if (and controller controller.selection-count)
        (controller:selection-count)
        0))
  (local layer-count
    (if (and controller controller.layer-count)
        (controller:layer-count)
        0))
  (set context.drawing
       {:controller controller
        :active-layer active-layer
        :selection-count selection-count
        :layer-count layer-count
        :has-selection? (> selection-count 0)})
  context)

(fn drawing-target-enabled? [target]
  (= (and target target.canvas-target-kind) nil))

(fn drawing-mode-update [payload]
  (local runtime (and payload payload.runtime))
  (when (and runtime runtime.drawing-render)
    (runtime.drawing-render:update))
  nil)

(fn root-actions [context]
  ((. DrawingCanvasModeActions :drawing-root-actions) context))

(fn selection-actions [context]
  ((. DrawingCanvasModeActions :drawing-selection-actions) context))

(fn activate-mode! [ctx]
  (ctx:set-drawing-enabled! true)
  (ctx:set-root-actions! root-actions)
  (ctx:set-selection-actions! selection-actions)
  (ctx:set-left-dock-builder! drawing-left-dock-builder)
  (ctx:set-command-hints-provider! (. DrawingInput :CommandHintsProvider))
  (ctx:set-context-enricher! enrich-drawing-context!)
  (ctx:set-input-handlers! {:key-down (. DrawingInput :DrawingKeyDown)
                            :mouse-button-down (. DrawingInput :DrawingMouseButtonDown)
                            :mouse-motion (. DrawingInput :DrawingMouseMotion)
                            :mouse-button-up (. DrawingInput :DrawingMouseButtonUp)})
  (ctx:set-target-enabled! drawing-target-enabled?)
  (ctx:set-update! drawing-mode-update)
  {:mode-id "drawing"})

(fn deactivate-mode! [_ctx _session]
  true)

(fn snapshot-drawing-canvas-mode! []
  {:active? (= (CanvasModes.active-mode-id) "drawing")})

(fn restore-state-arg [first _session maybe-state]
  (if (and first (. first :mode))
      maybe-state
      first))

(fn restore-drawing-canvas-mode! [first session maybe-state]
  (local state (restore-state-arg first session maybe-state))
  (when (and state state.active?)
    (CanvasModes.activate-mode "drawing"))
  true)

(fn mode-registered? [mode-id]
  (local (ok _resolved) (pcall CanvasModes.resolve mode-id))
  ok)

(fn load-drawing-canvas-mode! []
  (when (not (mode-registered? "drawing"))
    (CanvasModes.register-mode
      {:id "drawing"
       :label "Draw"
       :icon "draw"
       :button-name "drawing-canvas-mode"
       :show-in-sidebar? true
       :activate activate-mode!
       :deactivate deactivate-mode!}))
  true)

(fn unload-drawing-canvas-mode! []
  (local registered? (mode-registered? "drawing"))
  (local active? (and registered?
                      (= (CanvasModes.active-mode-id) "drawing")))
  (when active?
    (CanvasModes.deactivate-active-mode))
  (when registered?
    (CanvasModes.unregister-mode "drawing"))
  true)

{:drawing-mode-owned-paths drawing-mode-owned-paths
 :load-drawing-canvas-mode! load-drawing-canvas-mode!
 :unload-drawing-canvas-mode! unload-drawing-canvas-mode!
 :snapshot-drawing-canvas-mode! snapshot-drawing-canvas-mode!
 :restore-drawing-canvas-mode! restore-drawing-canvas-mode!}
