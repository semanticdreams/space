(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))

(fn canvas-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (local graph-view-root (fs.join-path (fs.join-path lua-root "graph") "view"))
  (icollect [_ path (ipairs [(fs.join-path lua-root "canvas-unit.fnl")
                             (fs.join-path lua-root "canvas.fnl")
                             (fs.join-path lua-root "canvas-controls.fnl")
                             (fs.join-path lua-root "canvas-mode-dock-view.fnl")
                             (fs.join-path lua-root "canvas-modes.fnl")
                             (fs.join-path lua-root "object-selector.fnl")
                             (fs.join-path lua-root "graph/view.fnl")
                             graph-view-root
                             (fs.join-path lua-root "graph-view-control-view.fnl")
                             (fs.join-path (fs.join-path lua-root "drawing") "render.fnl")
                             (fs.join-path lua-root "home-world-canvas-runtime.fnl")
                             (fs.join-path lua-root "home-world-canvas-shell-state.fnl")])]
    path))

(fn resolve-runtime []
  (local entry (assert app.active-world-entry "CanvasUnit requires app.active-world-entry"))
  (local world-runtime (assert app.active-world-runtime "CanvasUnit requires app.active-world-runtime"))
  (assert world-runtime.load-canvas-runtime "CanvasUnit requires runtime.load-canvas-runtime")
  (assert world-runtime.unload-canvas-runtime "CanvasUnit requires runtime.unload-canvas-runtime")
  (assert world-runtime.capture-canvas-unit-state "CanvasUnit requires runtime.capture-canvas-unit-state")
  (assert world-runtime.restore-canvas-unit-state "CanvasUnit requires runtime.restore-canvas-unit-state")
  {:entry entry
   :runtime world-runtime})

(fn rebind-runtime! [entry world-runtime]
  (assert app.bind-active-world-runtime "CanvasUnit requires app.bind-active-world-runtime")
  (app.bind-active-world-runtime entry world-runtime)
  true)

(fn load-canvas! []
  (local resolved (resolve-runtime))
  (local entry resolved.entry)
  (local world-runtime resolved.runtime)
  (world-runtime:load-canvas-runtime)
  (rebind-runtime! entry world-runtime))

(fn unload-canvas! []
  (local resolved (resolve-runtime))
  (local entry resolved.entry)
  (local world-runtime resolved.runtime)
  (world-runtime:unload-canvas-runtime)
  (rebind-runtime! entry world-runtime))

(fn snapshot-canvas! []
  (local resolved (resolve-runtime))
  (local world-runtime resolved.runtime)
  (world-runtime:capture-canvas-unit-state))

(fn restore-canvas! [state]
  (local resolved (resolve-runtime))
  (local entry resolved.entry)
  (local world-runtime resolved.runtime)
  (world-runtime:restore-canvas-unit-state state)
  (rebind-runtime! entry world-runtime))

{:canvas-owned-paths canvas-owned-paths
 :load-canvas! load-canvas!
 :unload-canvas! unload-canvas!
 :snapshot-canvas! snapshot-canvas!
 :restore-canvas! restore-canvas!}
