(local glm (require :glm))
(local _ (require :main))
(local BuildContext (require :build-context))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Signal (require :signal))
(local {: LayoutRoot} (require :layout))
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
                   :preferred-interaction-surface app.preferred-interaction-surface
                   :active-interaction-surface app.active-interaction-surface
                   :active-canvas-feature app.active-canvas-feature
                   :canvas-shell-changed app.canvas-shell-changed})
  (set app.clickables (Clickables))
  (set app.hoverables (Hoverables))
  (set app.canvas-shell-changed (or app.canvas-shell-changed (Signal)))
  (set app.canvas {})
  (set app.canvas-visible? true)
  (set app.preferred-interaction-surface :canvas)
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

(fn emit-canvas-shell-changed [reason]
  (when app.canvas-shell-changed
    (app.canvas-shell-changed:emit {:reason reason
                                    :current {:interaction-surface app.active-interaction-surface
                                              :canvas-feature app.active-canvas-feature
                                              :canvas-visible? app.canvas-visible?}})))

(fn set-canvas-feature [feature]
  (if app.set-active-canvas-feature
      (app.set-active-canvas-feature feature)
      (do
        (set app.active-canvas-feature feature)
        (emit-canvas-shell-changed "canvas-feature"))))

(fn set-interaction-surface [surface]
  (if app.set-active-interaction-surface
      (app.set-active-interaction-surface surface)
      (do
        (set app.preferred-interaction-surface surface)
        (set app.active-interaction-surface surface)
        (set app.canvas-visible? (= surface :canvas))
        (emit-canvas-shell-changed "interaction-surface"))))

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
      (set-canvas-feature "drawing")
      (sidebar:update)
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
      (sidebar:update)
      (sidebar.layout:measurer)
      (set input (find-text-input))
      (assert input "drawing sidebar should rebuild its layer rename input")
      (assert (= (input:get-text) "Sketch"))
      (assert (controller:on-undo))
      (sidebar:update)
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
      (assert (contains-label? (clickable-labels) "Fill On"))
      (controller:set-defaults! {:fill_enabled false})
      (sidebar:update)
      (sidebar.layout:measurer)
      (assert (contains-label? (clickable-labels) "Fill Off")
              "drawing sidebar should keep the fill toggle clickable when fill is disabled")
      (sidebar:drop))))

(fn sidebar-ignores-gesture-only-controller-noise []
  (with-sidebar-env
    (fn []
      (set app.active-canvas-feature "drawing")
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (sidebar.layout:measurer)
      (local initial-input (find-text-input))
      (assert initial-input "drawing sidebar should build its rename input in drawing mode")
      (controller:begin-gesture "brush" (glm.vec3 0 0 0))
      (controller:update-gesture (glm.vec3 4 0 0) false)
      (sidebar:update)
      (sidebar.layout:measurer)
      (local current-input (find-text-input))
      (assert (= current-input initial-input)
              "drawing sidebar should not rebuild on gesture-only controller changes")
      (sidebar:drop))))

(fn sidebar-reconciles-on-canvas-feature-changes []
  (with-sidebar-env
    (fn []
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (local root (LayoutRoot))
      (sidebar.layout:set-root root)
      (sidebar.layout:mark-measure-dirty)
      (local (ok-initial err-initial) (pcall (fn [] (root:update))))
      (assert ok-initial (.. "initial layout update failed: " (tostring err-initial)))
      (local graph-width (. sidebar.layout.measure 1))
      (set-canvas-feature "drawing")
      (sidebar:update)
      (local (ok err) (pcall (fn [] (root:update))))
      (assert ok (.. "sidebar should reconcile cleanly after app canvas feature changes: " (tostring err)))
      (assert (> (. sidebar.layout.measure 1) graph-width)
              "sidebar should expand immediately after the canvas feature changes")
      (sidebar:drop))))

(fn sidebar-appears-when-switching-to-canvas-surface []
  (with-sidebar-env
    (fn []
      (set app.active-interaction-surface :scene)
      (set app.canvas-visible? false)
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (sidebar.layout:measurer)
      (assert (= (. sidebar.layout.measure 1) 0)
              "drawing sidebar should start hidden while canvas surface is inactive")
      (set-interaction-surface :canvas)
      (sidebar:update)
      (sidebar.layout:measurer)
      (assert (> (. sidebar.layout.measure 1) 0)
              "drawing sidebar should appear after switching to canvas surface")
      (sidebar:drop))))

(table.insert tests {:name "Drawing sidebar expands in drawing feature mode"
                     :fn sidebar-width-reflects-active-canvas-feature})
(table.insert tests {:name "Drawing sidebar rename input follows controller history"
                     :fn sidebar-rename-input-syncs-after-history})
(table.insert tests {:name "Drawing sidebar keeps fill toggle clickable"
                     :fn sidebar-keeps-fill-toggle-clickable})
(table.insert tests {:name "Drawing sidebar ignores gesture-only controller noise"
                     :fn sidebar-ignores-gesture-only-controller-noise})
(table.insert tests {:name "Drawing sidebar reconciles on canvas feature changes"
                     :fn sidebar-reconciles-on-canvas-feature-changes})
(table.insert tests {:name "Drawing sidebar appears when switching to canvas surface"
                     :fn sidebar-appears-when-switching-to-canvas-surface})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-sidebar"
                       :tests tests})))

{:name "drawing-sidebar"
 :tests tests
 :main main}
