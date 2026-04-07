(local glm (require :glm))
(local _ (require :main))
(local BuildContext (require :build-context))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local DrawingController (require :drawing/controller))
(local DrawingSidebarView (require :drawing/sidebar-view))

(local tests [])

(fn make-ctx []
    (BuildContext {:theme (and app.themes app.themes.get-active-theme (app.themes.get-active-theme))
                   :clickables app.clickables
                   :hoverables app.hoverables
                   :system-cursors app.system-cursors
                   :states app.states}))

(fn codepoints->text [codepoints]
  (local parts [])
  (each [_ codepoint (ipairs (or codepoints []))]
    (table.insert parts (utf8.char codepoint)))
  (table.concat parts))

(fn clickable-labels []
  (local labels [])
  (each [_ obj (ipairs (or (and app.clickables app.clickables.left-click-objects) []))]
    (when (and obj obj.text obj.text.get-codepoints)
      (local text (codepoints->text (obj.text:get-codepoints)))
      (when (> (# text) 0)
        (table.insert labels text))))
  labels)

(fn contains-label? [labels target]
  (var found false)
  (each [_ label (ipairs labels)]
    (when (= label target)
      (set found true)))
  found)

(fn find-text-input []
  (var resolved nil)
  (each [_ obj (ipairs (or (and app.clickables app.clickables.left-click-objects) []))]
    (when (and (not resolved)
               obj
               obj.get-text
               obj.set-text)
      (set resolved obj)))
  resolved)

(fn with-sidebar-env [body]
  (local previous {:clickables app.clickables
                   :hoverables app.hoverables
                   :canvas app.canvas
                   :canvas-visible? app.canvas-visible?
                   :active-interaction-surface app.active-interaction-surface
                   :active-canvas-feature app.active-canvas-feature})
  (set app.clickables (Clickables))
  (set app.hoverables (Hoverables))
  (set app.canvas {})
  (set app.canvas-visible? true)
  (set app.active-interaction-surface :canvas)
  (set app.active-canvas-feature "graph")
  (local (ok result) (pcall body))
  (when (and app.clickables app.clickables.drop)
    (app.clickables:drop))
  (when (and app.hoverables app.hoverables.drop)
    (app.hoverables:drop))
  (each [key value (pairs previous)]
    (set (. app key) value))
  (when (not ok)
    (error result))
  result)

(fn sidebar-width-reflects-active-canvas-feature []
  (with-sidebar-env
    (fn []
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
      (sidebar:drop))))

(fn sidebar-rename-input-syncs-after-history []
  (with-sidebar-env
    (fn []
      (set app.active-canvas-feature "drawing")
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (sidebar.layout:measurer)
      (var input (find-text-input))
      (assert input "drawing sidebar should register its layer rename input")
      (assert (= (input:get-text) "Layer 1"))
      (assert (controller:rename-active-layer "Sketch"))
      (sidebar.layout:measurer)
      (set input (find-text-input))
      (assert input "drawing sidebar should rebuild its layer rename input")
      (assert (= (input:get-text) "Sketch"))
      (assert (controller:on-undo))
      (sidebar.layout:measurer)
      (set input (find-text-input))
      (assert input "drawing sidebar should keep its layer rename input after undo")
      (assert (= (input:get-text) "Layer 1"))
      (sidebar:drop))))

(fn sidebar-keeps-fill-toggle-clickable []
  (with-sidebar-env
    (fn []
      (set app.active-canvas-feature "drawing")
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (sidebar.layout:measurer)
      (assert (contains-label? (clickable-labels) "Fill Off"))
      (controller:set-defaults! {:fill_enabled true})
      (sidebar.layout:measurer)
      (assert (contains-label? (clickable-labels) "Fill On")
              "drawing sidebar should keep the fill toggle clickable when fill is enabled")
      (sidebar:drop))))

(table.insert tests {:name "Drawing sidebar expands in drawing feature mode"
                     :fn sidebar-width-reflects-active-canvas-feature})
(table.insert tests {:name "Drawing sidebar rename input follows controller history"
                     :fn sidebar-rename-input-syncs-after-history})
(table.insert tests {:name "Drawing sidebar keeps fill toggle clickable"
                     :fn sidebar-keeps-fill-toggle-clickable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-sidebar"
                       :tests tests})))

{:name "drawing-sidebar"
 :tests tests
 :main main}
