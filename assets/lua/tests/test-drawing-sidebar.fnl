(local glm (require :glm))
(local _ (require :main))
(local fs (require :fs))
(local BuildContext (require :build-context))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local MathUtils (require :math-utils))
(local Signal (require :signal))
(local Activities (require :activities))
(local DrawingController (require :drawing/controller))
(local DrawingSidebarView (require :drawing/sidebar-view))
(local ActivityDockView (require :activity-dock-view))
(local Themes (require :themes))
(local DarkTheme (require :dark-theme))
(local LightTheme (require :light-theme))

(local tests [])

(local temp-root (fs.join-path "/tmp/space/tests" "drawing-sidebar"))
(var temp-counter 0)

(fn with-temp-dir [f]
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "drawing-sidebar-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (when (not ok)
    (error result))
  result)

(fn with-controller [f]
  (with-temp-dir
    (fn [dir]
      (f (DrawingController {:data_dir dir}) dir))))

(fn with-vector-controller [f]
  (with-controller
    (fn [controller dir]
      (controller:add-layer "vector")
      (f controller dir))))

(fn ensure-built-in-activities! []
  (local registry (Activities.ensure-registry))
  (when (not (. registry.activities "graph"))
    (Activities.register-activity
      {:id "graph"
       :label "Graph"
       :icon "account_tree"
       :button-name "graph-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "graph"})
       :deactivate (fn [_ctx _session] true)}))
  (when (not (. registry.activities "drawing"))
    (Activities.register-activity
      {:id "drawing"
       :label "Draw"
       :icon "draw"
       :button-name "drawing-activity"
       :show-in-switcher? true
       :activate (fn [ctx]
                   (ctx:set-drawing-enabled! true)
                   (ctx:set-left-dock-builder!
                     (fn [build-ctx]
                       (if app.drawing-controller
                           ((DrawingSidebarView {:controller app.drawing-controller}) build-ctx)
                           nil)))
                   {:activity-id "drawing"})
       :deactivate (fn [_ctx _session] true)}))
  true)

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
                   :active-activity-id app.active-activity-id
                   :activity-activate-focused app.activity-activate-focused
                   :activity-command-hints-provider app.activity-command-hints-provider
                   :activity-context-enricher app.activity-context-enricher
                   :activity-delete-selection app.activity-delete-selection
                   :activity-drawing-enabled? app.activity-drawing-enabled?
                   :activity-input-handlers app.activity-input-handlers
                   :activity-left-dock-builder app.activity-left-dock-builder
                   :activity-registry app.activity-registry
                   :activity-root-actions app.activity-root-actions
                   :activity-selection-actions app.activity-selection-actions
                   :activity-target-enabled? app.activity-target-enabled?
                   :activity-update app.activity-update
                   :activities-changed app.activities-changed
                   :workspace-shell-changed app.workspace-shell-changed
                   :activity-units app.activity-units
                   :themes app.themes})
  (set app.clickables (Clickables))
  (set app.hoverables (Hoverables))
  (set app.activity-registry nil)
  (set app.activities-changed (Signal))
  (set app.workspace-shell-changed (Signal))
  (set app.canvas {})
  (set app.canvas-visible? true)
  (set app.preferred-interaction-surface :canvas)
  (set app.active-interaction-surface :canvas)
  (Activities.clear-activity-runtime-hooks!)
  (ensure-built-in-activities!)
  (Activities.activate-activity "graph")
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

(fn emit-workspace-shell-changed [reason]
  (when app.workspace-shell-changed
    (app.workspace-shell-changed:emit {:reason reason
                                    :current {:interaction-surface app.active-interaction-surface
                                              :activity app.active-activity-id
                                              :canvas-visible? app.canvas-visible?}})))

(fn set-activity-id [mode-id]
  (Activities.activate-activity mode-id)
  (set app.active-activity-id mode-id)
  (emit-workspace-shell-changed "activity")
  mode-id)

(fn set-interaction-surface [surface]
  (if app.set-active-interaction-surface
      (app.set-active-interaction-surface surface)
      (do
        (set app.preferred-interaction-surface surface)
        (set app.active-interaction-surface surface)
        (set app.canvas-visible? (= surface :canvas))
        (emit-workspace-shell-changed "interaction-surface"))))

(fn sidebar-width-reflects-active-activity-id []
  (with-sidebar-env
    (fn []
      (with-controller
        (fn [controller]
          (local original-controller app.drawing-controller)
          (set app.drawing-controller controller)
          (local dock ((ActivityDockView {}) (make-ctx)))
          (dock.layout:measurer)
          (local graph-width (. dock.layout.measure 1))
          (assert (> graph-width 0))
          (set-activity-id "drawing")
          (dock:update)
          (dock.layout:measurer)
          (local drawing-width (. dock.layout.measure 1))
          (assert (> drawing-width graph-width))
          (dock:drop)
          (set app.drawing-controller original-controller))))))

(fn sidebar-width-follows-panel-measure []
  (with-sidebar-env
    (fn []
      (with-controller
        (fn [controller]
          (local ctx (make-ctx))
          (local sidebar-builder (DrawingSidebarView {:controller controller}))
          (local sidebar (sidebar-builder ctx))
          (sidebar.layout:measurer)
          (local content-layout (. sidebar.layout.children 1))
          (local panel-layout (and content-layout (. content-layout.children 1)))
          (assert content-layout "drawing sidebar should create its composed content layout")
          (assert panel-layout "drawing sidebar should create its drawing panel layout")
          (assert (MathUtils.approx (. sidebar.layout.measure 1)
                                    (. panel-layout.measure 1))
                  "drawing sidebar width should match the measured drawing panel width")
          (sidebar:drop))))))

(fn sidebar-feature-buttons-fill-rail-width []
  (with-sidebar-env
    (fn []
      (with-controller
        (fn [controller]
          (local original-controller app.drawing-controller)
          (set app.drawing-controller controller)
          (local dock ((ActivityDockView {}) (make-ctx)))
          (dock.layout:measurer)
          (set dock.layout.position (glm.vec3 0 0 0))
          (set dock.layout.size dock.layout.measure)
          (set dock.layout.rotation (glm.quat 1 0 0 0))
          (set dock.layout.clip-region nil)
          (set dock.layout.depth-offset-index 0)
          (dock.layout:layouter)
          (local content-layout (. dock.layout.children 1))
          (local rail-layout (and content-layout (. content-layout.children 1)))
          (assert rail-layout "drawing sidebar should create its feature rail layout")
          (local rail-flex-layout (. rail-layout.children 2))
          (assert rail-flex-layout "drawing sidebar feature rail should place controls directly inside a flex layout")
          (local graph-button-layout (. rail-flex-layout.children 1))
          (local draw-button-layout (. rail-flex-layout.children 2))
          (assert graph-button-layout "drawing sidebar feature rail should create a graph button")
          (assert draw-button-layout "drawing sidebar feature rail should create a draw button")
          (local graph-button (find-clickable-button-by-icon "account_tree"))
          (local draw-button (find-clickable-button-by-icon "draw"))
          (assert graph-button
                  "drawing sidebar feature rail should expose an account_tree graph button")
          (assert draw-button
                  "drawing sidebar feature rail should expose a draw icon button")
          (assert (MathUtils.approx graph-button-layout.size.x rail-flex-layout.size.x)
                  "drawing sidebar graph button should fill the feature rail width")
          (assert (MathUtils.approx draw-button-layout.size.x rail-flex-layout.size.x)
                  "drawing sidebar draw button should fill the feature rail width")
          (assert (= graph-button.text.child.style.scale 3.2)
                  "drawing sidebar graph button should enlarge its icon through the shared icon sizing path")
          (assert (= draw-button.text.child.style.scale 3.2)
                  "drawing sidebar draw button should enlarge its icon through the shared icon sizing path")
          (assert (= rail-flex-layout.position.x rail-layout.position.x)
                  "drawing sidebar feature rail should not inset buttons horizontally")
          (assert (= rail-flex-layout.position.y rail-layout.position.y)
                  "drawing sidebar feature rail should not inset buttons vertically")
          (assert (MathUtils.approx rail-flex-layout.size.x rail-layout.size.x)
                  "drawing sidebar feature rail should not reserve horizontal padding around buttons")
          (assert (MathUtils.approx rail-flex-layout.size.y rail-layout.size.y)
                  "drawing sidebar feature rail should not reserve vertical padding around buttons")
          (assert (MathUtils.approx (+ graph-button-layout.size.y draw-button-layout.size.y)
                                    rail-flex-layout.size.y)
                  "drawing sidebar feature rail should stack icon buttons without spacing")
          (dock:drop)
          (set app.drawing-controller original-controller))))))

(fn sidebar-rename-input-syncs-after-history []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-vector-controller
        (fn [controller]
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
          (sidebar:drop))))))

(fn sidebar-keeps-fill-toggle-clickable []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-vector-controller
        (fn [controller]
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
          (sidebar:drop))))))

(fn sidebar-disables-raster-move-without-selection []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-controller
        (fn [controller]
          (controller:add-layer "raster")
          (local ctx (make-ctx))
          (local sidebar-builder (DrawingSidebarView {:controller controller}))
          (local sidebar (sidebar-builder ctx))
          (sidebar.layout:measurer)
          (local move-button (find-clickable-button "Move"))
          (assert move-button "drawing sidebar should expose a Move button for raster layers")
          (assert (= move-button.enabled? false)
                  "drawing sidebar should disable Move until a raster selection exists")
          (sidebar:drop))))))

(fn sidebar-empty-state-shows-create-actions-only []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-controller
        (fn [controller]
          (local ctx (make-ctx))
          (local sidebar-builder (DrawingSidebarView {:controller controller}))
          (local sidebar (sidebar-builder ctx))
          (sidebar.layout:measurer)
          (assert (find-clickable-button "+ Vector")
                  "drawing sidebar should expose + Vector in the empty state")
          (local raster-button (find-clickable-button "+ Raster"))
          (assert raster-button "drawing sidebar should expose + Raster in the empty state")
          (assert raster-button.enabled?
                  "drawing sidebar should keep + Raster enabled in the empty state")
          (assert (= (find-clickable-button "Select") nil)
                  "drawing sidebar should hide tool controls in the empty state")
          (assert (= (find-clickable-button "Save") nil)
                  "drawing sidebar should hide rename controls in the empty state")
          (sidebar:drop))))))

(fn sidebar-ignores-gesture-only-controller-noise []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-vector-controller
        (fn [controller]
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
          (sidebar:drop))))))

(fn sidebar-ignores-raster-edit-noise-when-visible-state-stays-stable []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-controller
        (fn [controller]
          (controller:add-layer "raster")
          (controller:set-active-tool "brush")
          (local ctx (make-ctx))
          (local sidebar-builder (DrawingSidebarView {:controller controller}))
          (local sidebar (sidebar-builder ctx))
          (sidebar.layout:measurer)
          (controller:begin-gesture "brush" (glm.vec3 0 0 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 4 0 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (sidebar:update)
          (sidebar.layout:measurer)
          (local stable-input (find-text-input))
          (assert stable-input "drawing sidebar should expose its rename input after the first raster edit rebuild")
          (controller:begin-gesture "brush" (glm.vec3 8 0 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 12 0 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (sidebar:update)
          (sidebar.layout:measurer)
          (local current-input (find-text-input))
          (assert (= current-input stable-input)
                  "drawing sidebar should not rebuild for raster edits that leave sidebar-visible state unchanged")
          (sidebar:drop))))))

(fn sidebar-rejects-untrimmed-rename-input []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-vector-controller
        (fn [controller]
          (local ctx (make-ctx))
          (local sidebar-builder (DrawingSidebarView {:controller controller}))
          (local sidebar (sidebar-builder ctx))
          (sidebar.layout:measurer)
          (local input (find-text-input))
          (local save-button (find-clickable-button "Save"))
          (assert input "drawing sidebar should expose its layer rename input")
          (assert save-button "drawing sidebar should expose a Save button for layer renames")
          (assert (not save-button.enabled?)
                  "drawing sidebar should keep Save disabled before the rename buffer changes")
          (input:set-text "  Sketch  ")
          (assert (not save-button.enabled?)
                  "drawing sidebar should keep Save disabled for non-canonical rename input")
          (local active-layer (controller:active-layer))
          (assert (= active-layer.name "Layer 1")
                  "drawing sidebar should not silently trim and apply non-canonical rename input")
          (sidebar:drop))))))

(fn sidebar-enables-save-for-valid-rename-input []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-vector-controller
        (fn [controller]
          (local ctx (make-ctx))
          (local sidebar-builder (DrawingSidebarView {:controller controller}))
          (local sidebar (sidebar-builder ctx))
          (sidebar.layout:measurer)
          (local input (find-text-input))
          (local save-button (find-clickable-button "Save"))
          (assert input "drawing sidebar should expose its layer rename input")
          (assert save-button "drawing sidebar should expose a Save button for layer renames")
          (assert (not save-button.enabled?)
                  "drawing sidebar should start with Save disabled when the rename buffer matches the layer name")
          (input:set-text "Sketch")
          (assert save-button.enabled?
                  "drawing sidebar should enable Save as soon as the rename buffer becomes valid")
          (save-button:on-click {})
          (sidebar:update)
          (sidebar.layout:measurer)
          (local active-layer (controller:active-layer))
          (assert (= active-layer.name "Sketch")
                  "drawing sidebar should apply valid rename input through the real save button path")
          (sidebar:drop))))))

(fn sidebar-ignores-selection-count-noise-when-delete-stays-enabled []
  (with-sidebar-env
    (fn []
      (set app.active-activity-id "drawing")
      (with-vector-controller
        (fn [controller]
          (controller:set-active-tool "rectangle")
          (controller:begin-gesture "rectangle" (glm.vec3 0 0 0))
          (controller:update-gesture (glm.vec3 10 8 0) false)
          (assert (controller:commit-gesture))
          (controller:begin-gesture "rectangle" (glm.vec3 20 0 0))
          (controller:update-gesture (glm.vec3 30 8 0) false)
          (assert (controller:commit-gesture))
          (local layer (controller:active-layer))
          (local object1 (. layer.objects 1))
          (local object2 (. layer.objects 2))
          (local ctx (make-ctx))
          (local sidebar-builder (DrawingSidebarView {:controller controller}))
          (local sidebar (sidebar-builder ctx))
          (sidebar.layout:measurer)
          (local stable-input (find-text-input))
          (assert stable-input "drawing sidebar should expose its rename input after vector selection changes")
          (controller:set-selection! [object1.id object2.id])
          (sidebar:update)
          (sidebar.layout:measurer)
          (local current-input (find-text-input))
          (assert (= current-input stable-input)
                  "drawing sidebar should not rebuild when selection count changes but Delete stays enabled")
          (sidebar:drop))))))

(fn sidebar-reconciles-on-activity-changes []
  (with-sidebar-env
    (fn []
      (with-controller
        (fn [controller]
          (local original-controller app.drawing-controller)
          (set app.drawing-controller controller)
          (local sidebar ((ActivityDockView {}) (make-ctx)))
          (sidebar.layout:measurer)
          (set-activity-id "drawing")
          (local (ok err)
            (pcall
              (fn []
                (sidebar:update)
                (sidebar.layout:measurer))))
          (assert ok (.. "sidebar should reconcile cleanly after app canvas feature changes: " (tostring err)))
          (local drawing-content-layout (. sidebar.layout.children 1))
          (local drawing-panel-layout (and drawing-content-layout (. drawing-content-layout.children 2)))
          (assert drawing-panel-layout
                  "activity dock should rebuild to include the drawing panel after switching activities")
          (sidebar:drop)
          (set app.drawing-controller original-controller))))))

(fn sidebar-appears-when-switching-to-canvas-surface []
  (with-sidebar-env
    (fn []
      (set app.active-interaction-surface :scene)
      (set app.canvas-visible? false)
      (with-controller
        (fn [controller]
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
          (sidebar:drop))))))

(fn sidebar-fills-allocated-dock-height []
  (with-sidebar-env
    (fn []
      (with-vector-controller
        (fn [controller]
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
          (local content-layout (. sidebar.layout.children 1))
          (local panel-layout (and content-layout (. content-layout.children 1)))
          (assert content-layout "drawing sidebar should create its composed content layout in drawing mode")
          (assert panel-layout "drawing sidebar should create the drawing panel layout in drawing mode")
          (assert (= panel-layout.position.y 7)
                  "drawing sidebar panel should start at the top-left dock origin")
          (assert (= panel-layout.position.x 5)
                  "drawing sidebar panel should start at the left dock origin")
          (assert (= panel-layout.size.y (+ measured.y 8))
                  "drawing sidebar panel should fill the allocated dock height")
          (sidebar:drop))))))

(fn sidebar-adopts-light-theme-colors []
  (with-sidebar-env
    (fn []
      (local themes (Themes))
      (themes.add-theme :dark DarkTheme)
      (themes.add-theme :light LightTheme)
      (set app.themes themes)
      (set app.active-activity-id "drawing")
      (themes.set-theme :dark)
      (with-vector-controller
        (fn [controller]
          (local dark-sidebar ((DrawingSidebarView {:controller controller}) (make-ctx)))
          (dark-sidebar.layout:measurer)
          (local dark-select (find-clickable-button "Select"))
          (local dark-primary-colors (themes.get-button-colors :primary))
          (local dark-primary (. dark-primary-colors :background))
          (assert dark-select "drawing sidebar should expose a Select button in dark theme")
          (assert (color-array= dark-select.background-color dark-primary)
                  "drawing sidebar active tool button should use the dark theme primary color")
          (dark-sidebar:drop)

          (themes.set-theme :light)
          (local light-sidebar ((DrawingSidebarView {:controller controller}) (make-ctx)))
          (light-sidebar.layout:measurer)
          (local light-select (find-clickable-button "Select"))
          (local light-primary-colors (themes.get-button-colors :primary))
          (local light-primary (. light-primary-colors :background))
          (assert light-select "drawing sidebar should expose a Select button in light theme")
          (assert (color-array= light-select.background-color light-primary)
                  "drawing sidebar active tool button should use the light theme primary color")
          (light-sidebar:drop))))))

(fn activity-dock-view-rebuilds-without-stale-layout-children []
  (with-sidebar-env
    (fn []
      (with-controller
        (fn [controller]
          (local original-controller app.drawing-controller)
          (set app.drawing-controller controller)
          (local dock ((ActivityDockView {}) (make-ctx)))
          (dock.layout:measurer)
          (assert (= (length dock.layout.children) 1)
                  "activity dock should start with exactly one root child")
          (set-activity-id "drawing")
          (dock:update)
          (dock.layout:measurer)
          (assert (= (length dock.layout.children) 1)
                  "activity dock should replace its root child when switching to drawing")
          (set-activity-id "graph")
          (dock:update)
          (dock.layout:measurer)
          (assert (= (length dock.layout.children) 1)
                  "activity dock should not accumulate stale root children when switching back")
          (dock:drop)
          (set app.drawing-controller original-controller))))))

(fn activity-dock-view-rebuilds-when-activities-register-at-runtime []
  (with-sidebar-env
    (fn []
      (local original-registry app.activity-registry)
      (local original-signal app.activities-changed)
      (set app.activity-registry nil)
      (set app.activities-changed nil)
      (Activities.register-activity
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-activity"
         :show-in-switcher? true
         :activate (fn [_ctx] {:activity-id "graph"})
         :deactivate (fn [_ctx _session] true)})
      (Activities.register-activity
        {:id "drawing"
         :label "Draw"
         :icon "draw"
         :button-name "drawing-activity"
         :show-in-switcher? true
         :activate (fn [_ctx] {:activity-id "drawing"})
         :deactivate (fn [_ctx _session] true)})
      (set app.active-activity-id "graph")
      (set app.active-activity-id "graph")
      (local dock ((ActivityDockView {}) (make-ctx)))
      (dock.layout:measurer)
      (var content-layout (. dock.layout.children 1))
      (var rail-layout (and content-layout (. content-layout.children 1)))
      (var rail-flex-layout (and rail-layout (. rail-layout.children 2)))
      (assert (= (length rail-flex-layout.children) 2)
              "activity dock should start with two built-in activity buttons")
      (Activities.register-activity
        {:id "custom-note"
         :label "Custom"
         :icon "draw"
         :button-name "custom-note-activity"
         :show-in-switcher? true
         :activate (fn [_ctx] {:activity-id "custom-note"})
         :deactivate (fn [_ctx _session] true)})
      (dock:update)
      (dock.layout:measurer)
      (set content-layout (. dock.layout.children 1))
      (set rail-layout (and content-layout (. content-layout.children 1)))
      (set rail-flex-layout (and rail-layout (. rail-layout.children 2)))
      (assert (= (length rail-flex-layout.children) 3)
              "activity dock should rebuild when a new runtime activity is registered")
      (dock:drop)
      (set app.activity-registry original-registry)
      (set app.activities-changed original-signal))))

(fn activity-dock-always-shows-feature-rail-in-scene-mode []
  (with-sidebar-env
    (fn []
      (with-controller
        (fn [controller]
          (local original-controller app.drawing-controller)
          (set app.drawing-controller controller)

          ;; Activate drawing activity to ensure left-dock-builder is available
          (set-activity-id "drawing")

          ;; Switch to scene mode before creating dock
          (set app.active-interaction-surface :scene)
          (set app.canvas-visible? false)

          ;; Create dock - should still show feature rail
          (local dock ((ActivityDockView {}) (make-ctx)))
          (dock.layout:measurer)

          ;; Feature rail should still be visible (> 0 measurement)
          (local scene-width (. dock.layout.measure 1))
          (assert (> scene-width 0)
                  "activity dock should show feature rail even in scene mode")

          ;; Content should exist (not nil)
          (local content-layout (. dock.layout.children 1))
          (assert content-layout "activity dock should have content layout even in scene mode")

          ;; Feature rail (FlexChild) should be present as first child
          (local rail-flex-child (. content-layout.children 1))
          (assert rail-flex-child "feature rail FlexChild should be present in scene mode")

          ;; Activity-specific panel should NOT be present
          (local activity-panel-child (. content-layout.children 2))
          (assert (not activity-panel-child)
                  "activity-specific panel should not be present in scene mode")

          ;; Switch back to canvas mode
          (set-interaction-surface :canvas)
          (dock:update)
          (dock.layout:measurer)

          ;; Width should increase (activity panel added)
          (local canvas-width (. dock.layout.measure 1))
          (assert (> canvas-width scene-width)
                  "activity dock should widen when switching to canvas")

          ;; Activity panel should now be present
          (local updated-content (. dock.layout.children 1))
          (local updated-activity-panel (. updated-content.children 2))
          (assert updated-activity-panel
                  "activity-specific panel should be present after switching to canvas")

          (dock:drop)
          (set app.drawing-controller original-controller))))))

(table.insert tests {:name "Activity dock always shows feature rail in scene mode"
                     :fn activity-dock-always-shows-feature-rail-in-scene-mode})
(table.insert tests {:name "Drawing sidebar expands in drawing activity"
                     :fn sidebar-width-reflects-active-activity-id})
(table.insert tests {:name "Drawing sidebar width follows panel measure"
                     :fn sidebar-width-follows-panel-measure})
(table.insert tests {:name "Drawing sidebar feature buttons fill rail width"
                     :fn sidebar-feature-buttons-fill-rail-width})
(table.insert tests {:name "Drawing sidebar rename input follows controller history"
                     :fn sidebar-rename-input-syncs-after-history})
(table.insert tests {:name "Drawing sidebar keeps fill toggle clickable"
                     :fn sidebar-keeps-fill-toggle-clickable})
(table.insert tests {:name "Drawing sidebar disables raster move without selection"
                     :fn sidebar-disables-raster-move-without-selection})
(table.insert tests {:name "Drawing sidebar empty state shows only create actions"
                     :fn sidebar-empty-state-shows-create-actions-only})
(table.insert tests {:name "Drawing sidebar ignores gesture-only controller noise"
                     :fn sidebar-ignores-gesture-only-controller-noise})
(table.insert tests {:name "Drawing sidebar ignores raster edit noise when visible state stays stable"
                     :fn sidebar-ignores-raster-edit-noise-when-visible-state-stays-stable})
(table.insert tests {:name "Drawing sidebar rejects untrimmed rename input"
                     :fn sidebar-rejects-untrimmed-rename-input})
(table.insert tests {:name "Drawing sidebar enables save for valid rename input"
                     :fn sidebar-enables-save-for-valid-rename-input})
(table.insert tests {:name "Drawing sidebar ignores selection count noise when delete stays enabled"
                     :fn sidebar-ignores-selection-count-noise-when-delete-stays-enabled})
(table.insert tests {:name "Drawing sidebar reconciles on activity changes"
                     :fn sidebar-reconciles-on-activity-changes})
(table.insert tests {:name "Drawing sidebar appears when switching to canvas surface"
                     :fn sidebar-appears-when-switching-to-canvas-surface})
(table.insert tests {:name "Drawing sidebar fills allocated dock height"
                     :fn sidebar-fills-allocated-dock-height})
(table.insert tests {:name "Drawing sidebar adopts light theme colors"
                     :fn sidebar-adopts-light-theme-colors})
(table.insert tests {:name "Activity dock view rebuilds without stale layout children"
                     :fn activity-dock-view-rebuilds-without-stale-layout-children})
(table.insert tests {:name "Activity dock view rebuilds when activities register at runtime"
                     :fn activity-dock-view-rebuilds-when-activities-register-at-runtime})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-sidebar"
                       :tests tests})))

{:name "drawing-sidebar"
 :tests tests
 :main main}
