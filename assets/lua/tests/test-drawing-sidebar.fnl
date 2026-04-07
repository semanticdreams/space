(local glm (require :glm))
(local _ (require :main))
(local BuildContext (require :build-context))
(local DrawingController (require :drawing/controller))
(local DrawingSidebarView (require :drawing/sidebar-view))

(local tests [])

(fn make-ctx []
  (BuildContext {:theme (and app.themes app.themes.get-active-theme (app.themes.get-active-theme))
                 :clickables app.clickables
                 :hoverables app.hoverables
                 :system-cursors app.system-cursors
                 :states app.states}))

(fn sidebar-width-reflects-active-canvas-feature []
  (set app.canvas {})
  (set app.canvas-visible? true)
  (set app.active-interaction-surface :canvas)
  (set app.active-canvas-feature "graph")
  (local controller (DrawingController {}))
  (local ctx (make-ctx))
  (local sidebar-builder (DrawingSidebarView {:controller controller}))
  (local sidebar (sidebar-builder ctx))
  (sidebar.layout:measurer)
  (local graph-width (. sidebar.layout.measure 1))
  (assert (> graph-width 0))
  (set app.active-canvas-feature "drawing")
  (controller:emit-changed {:reason "test"})
  (sidebar.layout:measurer)
  (local drawing-width (. sidebar.layout.measure 1))
  (assert (> drawing-width graph-width))
  (sidebar:drop))

(table.insert tests {:name "Drawing sidebar expands in drawing feature mode"
                     :fn sidebar-width-reflects-active-canvas-feature})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-sidebar"
                       :tests tests})))

{:name "drawing-sidebar"
 :tests tests
 :main main}
