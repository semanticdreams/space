(local {:to-table viewport->table} (require :viewport-utils))

(fn set-viewport [data]
  (set app.viewport (viewport->table data))
  (when app.scene
    (app.scene:on-viewport-changed app.viewport))
  (when app.hud
    (app.hud:on-viewport-changed app.viewport))
  (when app.renderers
    (app.renderers:on-viewport-changed app.viewport))
  app.viewport)

{:set-viewport set-viewport}
