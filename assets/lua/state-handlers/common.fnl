(local Runtime (require :state-runtime))

(fn app-from [ctx]
  (. ctx :app))

(fn controls-from [ctx]
  (let [app-obj (app-from ctx)]
    (when app-obj.presentation-input-controls
      (app-obj.presentation-input-controls))))

(fn selector-from [_ctx]
  (Runtime.selection-handler))

(fn click-blocked? []
  (Runtime.clickables-active?))

(fn move-blocked? []
  (Runtime.movables-active?))

(fn resize-blocked? []
  (Runtime.resizables-active?))

(fn pointer-blocked? []
  (or (move-blocked?)
      (resize-blocked?)
      (click-blocked?)))

(fn hoverables-from [ctx]
  (local hoverables (. (app-from ctx) :hoverables))
  (assert hoverables "state handlers require app.hoverables")
  hoverables)

{:app-from app-from
 :controls-from controls-from
 :selector-from selector-from
 :click-blocked? click-blocked?
 :move-blocked? move-blocked?
 :resize-blocked? resize-blocked?
 :pointer-blocked? pointer-blocked?
 :hoverables-from hoverables-from}
