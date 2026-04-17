(local glm (require :glm))
(local _ (require :main))
(local BuildContext (require :build-context))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local MathUtils (require :math-utils))
(local Signal (require :signal))
(local {: LayoutRoot} (require :layout))
(local DrawingController (require :drawing/controller))
(local DrawingSidebarView (require :drawing/sidebar-view))
(local Themes (require :themes))
(local DarkTheme (require :dark-theme))
(local LightTheme (require :light-theme))

(local tests [])

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}})
  (local stub {:font font
               :codepoints {:account_tree 4242
                            :draw 4242}})
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(fn make-ctx []
  (BuildContext {:theme (and app.themes app.themes.get-active-theme (app.themes.get-active-theme))
                 :clickables app.clickables
                 :hoverables app.hoverables
                 :system-cursors app.system-cursors
                 :icons (make-icons-stub)
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

(fn color-array= [a b]
  (and a b
       (= (or (. a 1) a.x 0) (or (. b 1) b.x 0))
       (= (or (. a 2) a.y 0) (or (. b 2) b.y 0))
       (= (or (. a 3) a.z 0) (or (. b 3) b.z 0))
       (= (or (. a 4) a.w 0) (or (. b 4) b.w 0))))

(fn find-clickable-button [target]
  (var resolved nil)
  (each [_ obj (ipairs (or (and app.clickables app.clickables.left-click-objects) []))]
    (when (and (not resolved)
               obj
               obj.text
               obj.text.get-codepoints)
      (local text (codepoints->text (obj.text:get-codepoints)))
      (when (= text target)
        (set resolved obj))))
  resolved)

(fn find-clickable-button-by-icon [target]
  (var resolved nil)
  (each [_ obj (ipairs (or (and app.clickables app.clickables.left-click-objects) []))]
    (when (and (not resolved)
               obj
               (= obj.icon target))
      (set resolved obj)))
  resolved)

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
                   :canvas-shell-changed app.canvas-shell-changed
                   :themes app.themes})
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

(fn sidebar-width-follows-panel-measure []
  (with-sidebar-env
    (fn []
      (set app.active-canvas-feature "drawing")
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (sidebar.layout:measurer)
      (local rail-layout (. sidebar.layout.children 1))
      (local panel-layout (. sidebar.layout.children 2))
      (assert rail-layout "drawing sidebar should create its feature rail layout")
      (assert panel-layout "drawing sidebar should create its drawing panel layout")
      (assert (MathUtils.approx (. sidebar.layout.measure 1)
                                (+ 6.4 (. panel-layout.measure 1)))
              "drawing sidebar width should be derived from the panel measurement rather than a fixed width")
      (sidebar:drop))))

(fn sidebar-feature-buttons-fill-rail-width []
  (with-sidebar-env
    (fn []
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (sidebar.layout:measurer)
      (set sidebar.layout.position (glm.vec3 0 0 0))
      (set sidebar.layout.size sidebar.layout.measure)
      (set sidebar.layout.rotation (glm.quat 1 0 0 0))
      (set sidebar.layout.clip-region nil)
      (set sidebar.layout.depth-offset-index 0)
      (sidebar.layout:layouter)
      (local rail-layout (. sidebar.layout.children 1))
      (assert rail-layout "drawing sidebar should create its feature rail layout")
      (local rail-padding-layout (. rail-layout.children 2))
      (assert rail-padding-layout "drawing sidebar feature rail should wrap controls in padding")
      (local rail-flex-layout (. rail-padding-layout.children 1))
      (assert rail-flex-layout "drawing sidebar feature rail should place controls inside a flex layout")
      (local graph-button-layout (. rail-flex-layout.children 1))
      (local draw-button-layout (. rail-flex-layout.children 2))
      (assert graph-button-layout "drawing sidebar feature rail should create a graph button")
      (assert draw-button-layout "drawing sidebar feature rail should create a draw button")
      (assert (find-clickable-button-by-icon "account_tree")
              "drawing sidebar feature rail should expose an account_tree graph button")
      (assert (find-clickable-button-by-icon "draw")
              "drawing sidebar feature rail should expose a draw icon button")
      (assert (MathUtils.approx graph-button-layout.size.x rail-flex-layout.size.x)
              "drawing sidebar graph button should fill the feature rail width")
      (assert (MathUtils.approx draw-button-layout.size.x rail-flex-layout.size.x)
              "drawing sidebar draw button should fill the feature rail width")
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

(fn sidebar-fills-allocated-dock-height []
  (with-sidebar-env
    (fn []
      (set app.active-canvas-feature "drawing")
      (local controller (DrawingController {}))
      (local ctx (make-ctx))
      (local sidebar-builder (DrawingSidebarView {:controller controller}))
      (local sidebar (sidebar-builder ctx))
      (sidebar.layout:measurer)
      (local measured sidebar.layout.measure)
      (set sidebar.layout.position (glm.vec3 5 7 0))
      (set sidebar.layout.size (glm.vec3 measured.x (+ measured.y 8) measured.z))
      (set sidebar.layout.rotation (glm.quat 1 0 0 0))
      (set sidebar.layout.clip-region nil)
      (set sidebar.layout.depth-offset-index 0)
      (sidebar.layout:layouter)
      (local rail-layout (. sidebar.layout.children 1))
      (local panel-layout (. sidebar.layout.children 2))
      (assert rail-layout "drawing sidebar should create the feature rail layout in drawing mode")
      (assert panel-layout "drawing sidebar should create the drawing panel layout in drawing mode")
      (assert (= rail-layout.position.y 7)
              "drawing sidebar feature rail should start at the top-left dock origin")
      (assert (= panel-layout.position.y 7)
              "drawing sidebar panel should start at the top-left dock origin")
      (assert (MathUtils.approx panel-layout.position.x
                                (+ rail-layout.position.x rail-layout.size.x))
              "drawing sidebar panel should sit flush against the feature rail without a gap")
      (assert (= rail-layout.size.y (+ measured.y 8))
              "drawing sidebar feature rail should fill the allocated dock height")
      (assert (= panel-layout.size.y (+ measured.y 8))
              "drawing sidebar panel should fill the allocated dock height")
      (sidebar:drop))))

(fn sidebar-adopts-light-theme-colors []
  (with-sidebar-env
    (fn []
      (local themes (Themes))
      (themes.add-theme :dark DarkTheme)
      (themes.add-theme :light LightTheme)
      (set app.themes themes)
      (set app.active-canvas-feature "drawing")
      (themes.set-theme :dark)
      (local dark-sidebar ((DrawingSidebarView {:controller (DrawingController {})}) (make-ctx)))
      (dark-sidebar.layout:measurer)
      (local dark-draw (find-clickable-button-by-icon "draw"))
      (local dark-select (find-clickable-button "Select"))
      (local dark-primary-colors (themes.get-button-colors :primary))
      (local dark-primary (. dark-primary-colors :background))
      (assert dark-draw "drawing sidebar should expose a Draw button in dark theme")
      (assert dark-select "drawing sidebar should expose a Select button in dark theme")
      (assert (color-array= dark-draw.background-color dark-primary)
              "drawing sidebar active rail button should use the dark theme primary color")
      (assert (color-array= dark-select.background-color dark-primary)
              "drawing sidebar active tool button should use the dark theme primary color")
      (dark-sidebar:drop)

      (themes.set-theme :light)
      (local light-sidebar ((DrawingSidebarView {:controller (DrawingController {})}) (make-ctx)))
      (light-sidebar.layout:measurer)
      (local light-draw (find-clickable-button-by-icon "draw"))
      (local light-select (find-clickable-button "Select"))
      (local light-primary-colors (themes.get-button-colors :primary))
      (local light-primary (. light-primary-colors :background))
      (assert light-draw "drawing sidebar should expose a Draw button in light theme")
      (assert light-select "drawing sidebar should expose a Select button in light theme")
      (assert (color-array= light-draw.background-color light-primary)
              "drawing sidebar active rail button should use the light theme primary color")
      (assert (color-array= light-select.background-color light-primary)
              "drawing sidebar active tool button should use the light theme primary color")
      (light-sidebar:drop))))

(table.insert tests {:name "Drawing sidebar expands in drawing feature mode"
                     :fn sidebar-width-reflects-active-canvas-feature})
(table.insert tests {:name "Drawing sidebar width follows panel measure"
                     :fn sidebar-width-follows-panel-measure})
(table.insert tests {:name "Drawing sidebar feature buttons fill rail width"
                     :fn sidebar-feature-buttons-fill-rail-width})
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
(table.insert tests {:name "Drawing sidebar fills allocated dock height"
                     :fn sidebar-fills-allocated-dock-height})
(table.insert tests {:name "Drawing sidebar adopts light theme colors"
                     :fn sidebar-adopts-light-theme-colors})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-sidebar"
                       :tests tests})))

{:name "drawing-sidebar"
 :tests tests
 :main main}
