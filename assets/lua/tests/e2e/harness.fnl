(global app (or app {}))

(local IoUtils (require :io-utils))
(global read-file IoUtils.read-file)

(local EngineModule (require :engine))
(local glm (require :glm))
(local Snapshots (require :snapshots))
(local gl (require :gl))
(local BuildContext (require :build-context))
(local {: Layout : LayoutRoot} (require :layout))
(local Button (require :button))
(local Sized (require :sized))
(local Text (require :text))
(local TextStyle (require :text-style))
(local {: Flex : FlexChild} (require :flex))
(local Hud (require :hud))
(local AppBootstrap (require :app-bootstrap))
(local AppViewport (require :app-viewport))
(local AppProjection (require :app-projection))
(local {:to-table viewport->table :to-glm-vec4 viewport->glm-vec4} (require :viewport-utils))
(local {: FocusManager} (require :focus))
(local HudLayout (require :hud-layout))
(local {: ControlPanelLayout} (require :hud-control-panel-layout))
(local {: StatusPanelLayout} (require :hud-status-panel-layout))

(fn number-or [value fallback]
  (if (not (= value nil)) value fallback))

(fn screen-pos-ray-from-matrices [pos view projection viewport]
  (local sample-pos (or pos
                        {:x (+ viewport.x (/ viewport.width 2))
                         :y (+ viewport.y (/ viewport.height 2))}))
  (local px (number-or sample-pos.x viewport.x))
  (local py (number-or sample-pos.y viewport.y))
  (local inverted-y (- (+ viewport.height viewport.y) py))
  (local viewport-vec (viewport->glm-vec4 viewport))
  (local near (glm.unproject (glm.vec3 px inverted-y 0.0) view projection viewport-vec))
  (local far (glm.unproject (glm.vec3 px inverted-y 1.0) view projection viewport-vec))
  (local direction (glm.normalize (- far near)))
  {:origin near :direction direction})

(fn cleanup-target [target]
  (when (and target target.drop)
    (target:drop))
  (when (and target target.__e2e_focus_manager target.__e2e_focus_manager.drop)
    (target.__e2e_focus_manager:drop)
    (set target.__e2e_focus_manager nil)))

(fn cleanup []
  (when (and app app.renderers app.renderers.drop)
    (app.renderers:drop))
  (when (and app app.engine)
    (app.engine:shutdown))
  (set app nil))

(fn sync-texture-loading []
  (local textures (require :textures))
  (set textures.load-texture-async textures.load-texture)
  (set textures.load-texture-from-bytes-async textures.load-texture-from-bytes))

(fn configure-viewport [width height]
  (local viewport (app.set-viewport {:width width :height height}))
  (gl.glViewport 0 0 width height)
  viewport)

(fn init-test-app [width height]
  (global app {})
  (set app.testing true)
  (set app.engine (EngineModule.Engine {:headless false
                                        :width width
                                        :height height
                                        :maximized false}))
  (when (not (app.engine:start))
    (error "[e2e] engine failed to start (window/GL init failed)"))
  (set app.engine.audio nil)
  (sync-texture-loading)
  (AppBootstrap.init-themes)
  (AppBootstrap.init-input-systems)
  (AppBootstrap.init-icons)
  (AppBootstrap.init-states)
  (set app.set-viewport AppViewport.set-viewport)
  (set app.create-default-projection AppProjection.create-default-projection)
  (configure-viewport width height)
  (AppBootstrap.init-renderers {:viewport app.viewport}))

(fn assert-font-ready [label]
  (local theme (app.themes.get-active-theme))
  (local font (and theme theme.font))
  (assert (and font font.texture font.texture.ready)
          (.. (or label "e2e") " requires ready font texture"))
  font)

(fn make-context [opts]
  (local options (or opts {}))
  (local width (or options.width 640))
  (local height (or options.height 360))
  (local units-per-pixel (or options.units-per-pixel 0.05))
  (init-test-app width height)
  {:width width
   :height height
   :units-per-pixel units-per-pixel
   :world-size (glm.vec3 (* width units-per-pixel)
                         (* height units-per-pixel)
                         0)
   :font (assert-font-ready "e2e")})

(fn with-app [opts run-fn]
  (local ctx (make-context opts))
  (local (ok err)
    (pcall run-fn ctx))
  (cleanup)
  (when (not ok)
    (error err)))

(fn make-button-builder [opts]
  (local options (or opts {}))
  (local button-opts {:text (or options.text "Button")
                      :variant (or options.variant :secondary)
                      :padding (or options.padding [0.7 0.7])
                      :foreground-color (or options.foreground-color (glm.vec4 1 0 0 1))
                      :text-style (or options.text-style
                                      (TextStyle {:scale (or options.text-scale 4)
                                                  :color (or options.text-color (glm.vec4 1 0 0 1))}))})
  (fn [ctx]
    (local button ((Button button-opts) ctx))
    (when options.on-built
      (options.on-built button))
    (if options.size
        ((Sized {:size options.size
                 :child (fn [_] button)}) ctx)
        button)))

(fn make-test-button-row []
  (Flex {:axis :x
         :xspacing 0.5
         :yalign :center
         :children [(FlexChild (Button {:text "Run"
                                        :variant :primary
                                        :padding [0.4 0.4]}) 0)
                    (FlexChild (Button {:text "Pause"
                                        :variant :secondary
                                        :padding [0.4 0.4]}) 0)
                    (FlexChild (Button {:text "Reset"
                                        :variant :secondary
                                        :padding [0.4 0.4]}) 0)]}))

(fn make-test-hud-builder []
  (local theme (app.themes.get-active-theme))
  (local text-color (and theme theme.text theme.text.foreground))
  (assert text-color "e2e HUD builder requires theme text color")
  (local control-title-style (TextStyle {:scale 1.6
                                         :color text-color}))
  (local control-status-style (TextStyle {:scale 1.6
                                          :color text-color}))
  (local status-style (TextStyle {:scale 1.6
                                  :color text-color}))
  (local title-builder
    (fn [child-ctx]
      ((Text {:text "CONTROL"
              :style control-title-style}) child-ctx)))
  (local status-builder
    (fn [child-ctx]
      ((Text {:text "Status: OK"
              :style control-status-style}) child-ctx)))
  (local state-builder
    (fn [child-ctx]
      ((Text {:text "State: test"
              :style status-style}) child-ctx)))
  (local focus-builder
    (fn [child-ctx]
      ((Text {:text "Focus: none"
              :style status-style}) child-ctx)))
  (local control-builder
    (ControlPanelLayout {:title-builder title-builder
                         :status-builder status-builder
                         :button-row-builder (make-test-button-row)}))
  (local status-builder-node
    (StatusPanelLayout {:state-builder state-builder
                        :focus-builder focus-builder}))
  (HudLayout.make-hud-builder {:control-builder control-builder
                               :status-builder status-builder-node}))

(fn make-screen-target [opts]
  (local options (or opts {}))
  (local width (or options.width 640))
  (local height (or options.height 360))
  (local units-per-pixel (or options.world-units-per-pixel 0.05))
  (local world-width (* width units-per-pixel))
  (local world-height (* height units-per-pixel))
  (local world-size (glm.vec3 world-width world-height 0))
  (local layout-root (LayoutRoot))
  (local focus-manager options.focus-manager)
  (local focus-scope (or options.focus-scope
                         (and focus-manager
                              (focus-manager:create-scope
                                {:name (or options.focus-scope-name "e2e-screen")}))))
  (local ctx (BuildContext {:theme (app.themes.get-active-theme)
                            :clickables app.clickables
                            :hoverables app.hoverables
                            :system-cursors app.system-cursors
                            :icons app.icons
                            :states app.states
                            :layout-root layout-root
                            :movables app.movables
                            :focus-manager focus-manager
                            :focus-scope focus-scope}))
  (local target {:layout-root layout-root
                 :build-context ctx
                 :projection (or options.projection
                                 (glm.ortho 0 world-width 0 world-height -100.0 100.0))
                 :view-matrix (or options.view-matrix (glm.mat4 1))
                 :screen-pos-ray (fn [self pos opts]
                                   (local options (or opts {}))
                                   (local viewport (viewport->table (or options.viewport app.viewport)))
                                   (local view (or options.view self.view-matrix))
                                   (local projection (or options.projection self.projection))
                                   (assert view "screen target requires view matrix")
                                   (assert projection "screen target requires projection")
                                   (screen-pos-ray-from-matrices pos view projection viewport))
                 :element nil
                 :root-layout nil
                 :world-size world-size
                 :update (fn [self] (self.layout-root:update))
                 :get-view-matrix (fn [self] (or self.view-matrix (glm.mat4 1)))
                 :get-triangle-vector (fn [self] self.build-context.triangle-vector)
                 :get-triangle-batches (fn [self] (self.build-context:get-triangle-batches))
                 :get-line-vector (fn [self] self.build-context.line-vector)
                 :get-point-vector (fn [self] self.build-context.point-vector)
                 :get-line-strips (fn [self] self.build-context.line-strips)
                 :get-text-vectors (fn [self] self.build-context.text-vectors)
                 :get-text-batches (fn [self] (self.build-context:get-text-batches))
                 :get-image-batches (fn [self] self.build-context.image-batches)
                 :get-mesh-batches (fn [self] (self.build-context:get-mesh-batches))
                 :drop (fn [self]
                         (when self.root-layout
                           (self.root-layout:drop))
                         (when (and self.element self.element.drop)
                           (self.element:drop)))})
  (set ctx.pointer-target target)
  (when focus-manager
    (set target.__e2e_focus_manager focus-manager))
  (local builder (assert options.builder "screen target requires :builder"))
  (local element (builder ctx))
  (set target.element element)
  (local root-layout
    (Layout {:name "e2e-screen-root"
             :children [element.layout]
             :measurer (fn [self]
                         (element.layout:measurer)
                         (set self.measure world-size))
             :layouter (fn [self]
                         (set self.size self.measure)
                         (local child-size (or element.layout.measure (glm.vec3 0 0 0)))
                         (set element.layout.size child-size)
                         (local offset (glm.vec3 (/ (- self.size.x child-size.x) 2)
                                                 (/ (- self.size.y child-size.y) 2)
                                                 0))
                         (set element.layout.position (+ self.position offset))
                         (set element.layout.rotation self.rotation)
                         (set element.layout.depth-offset-index self.depth-offset-index)
                         (set element.layout.clip-region self.clip-region)
                         (element.layout:layouter))}))
  (set target.root-layout root-layout)
  (root-layout:set-root layout-root)
  (root-layout:mark-measure-dirty)
  (layout-root:update)
  target)

(fn make-scene-target [opts]
  (local options (or opts {}))
  (local layout-root (LayoutRoot))
  (local focus-manager options.focus-manager)
  (local focus-scope (or options.focus-scope
                         (and focus-manager
                              (focus-manager:create-scope
                                {:name (or options.focus-scope-name "e2e-scene")}))))
  (local ctx (BuildContext {:theme (app.themes.get-active-theme)
                            :clickables app.clickables
                            :hoverables app.hoverables
                            :system-cursors app.system-cursors
                            :icons app.icons
                            :states app.states
                            :layout-root layout-root
                            :movables app.movables
                            :focus-manager focus-manager
                            :focus-scope focus-scope}))
  (local target {:layout-root layout-root
                 :build-context ctx
                 :projection (or options.projection (app.create-default-projection))
                 :view-matrix (or options.view-matrix (glm.mat4 1))
                 :element nil
                 :root-layout nil
                 :update (fn [self] (self.layout-root:update))
                 :get-view-matrix (fn [self] (or self.view-matrix (glm.mat4 1)))
                 :get-triangle-vector (fn [self] self.build-context.triangle-vector)
                 :get-triangle-batches (fn [self] (self.build-context:get-triangle-batches))
                 :get-line-vector (fn [self] self.build-context.line-vector)
                 :get-point-vector (fn [self] self.build-context.point-vector)
                 :get-line-strips (fn [self] self.build-context.line-strips)
                 :get-text-vectors (fn [self] self.build-context.text-vectors)
                 :get-text-batches (fn [self] (self.build-context:get-text-batches))
                 :get-image-batches (fn [self] self.build-context.image-batches)
                 :get-mesh-batches (fn [self] (self.build-context:get-mesh-batches))
                 :drop (fn [self]
                         (when self.root-layout
                           (self.root-layout:drop))
                         (when (and self.element self.element.drop)
                           (self.element:drop)))})
  (set ctx.pointer-target target)
  (when focus-manager
    (set target.__e2e_focus_manager focus-manager))
  (local builder (assert options.builder "scene target requires :builder"))
  (local element (builder ctx))
  (set target.element element)
  (local root-layout
    (Layout {:name "e2e-scene-root"
             :children [element.layout]
             :measurer (fn [self]
                         (element.layout:measurer)
                         (set self.measure element.layout.measure))
             :layouter (fn [self]
                         (set self.size self.measure)
                         (local child-size (or element.layout.measure (glm.vec3 0 0 0)))
                         (set element.layout.size child-size)
                         (local center-offset (glm.vec3 (- (/ child-size.x 2))
                                                        (- (/ child-size.y 2))
                                                        0))
                         (local base-position (or options.child-position (glm.vec3 0 0 0)))
                         (local child-offset (+ base-position center-offset))
                         (set element.layout.position (+ self.position (self.rotation:rotate child-offset)))
                         (local child-rotation (or options.child-rotation (glm.quat 1 0 0 0)))
                         (set element.layout.rotation (* self.rotation child-rotation))
                         (set element.layout.depth-offset-index self.depth-offset-index)
                         (set element.layout.clip-region self.clip-region)
                         (element.layout:layouter))}))
  (set target.root-layout root-layout)
  (root-layout:set-root layout-root)
  (root-layout:mark-measure-dirty)
  (layout-root:update)
  target)

(fn make-hud-target [opts]
  (local options (or opts {}))
  (local focus-manager (FocusManager {:root-name "e2e-focus"}))
  (local hud (Hud {:scene nil
                   :focus-manager focus-manager
                   :icons app.icons
                   :states app.states
                   :movables app.movables
                   :scale-factor (or options.scale-factor 2.0)}))
  (set hud.__e2e_focus_manager focus-manager)
  (if options.builder
      (hud:build options.builder)
      (hud:build-default options.hud-options))
  (hud:update-projection {:width options.width :height options.height})
  (hud:update)
  hud)

(fn draw-targets [width height targets]
  (configure-viewport width height)
  (gl.glBindFramebuffer gl.GL_FRAMEBUFFER 0)
  (gl.glBindFramebuffer gl.GL_READ_FRAMEBUFFER 0)
  (gl.glBindFramebuffer gl.GL_DRAW_FRAMEBUFFER 0)
  (gl.glDisable gl.GL_CULL_FACE)
  (gl.glEnable gl.GL_DEPTH_TEST)
  (gl.glDepthFunc gl.GL_LESS)
  (gl.glClearColor 0.05 0.06 0.08 1.0)
  (gl.glClear (bor gl.GL_COLOR_BUFFER_BIT gl.GL_DEPTH_BUFFER_BIT))
  (each [_ entry (ipairs targets)]
    (when entry.clear-depth?
      (gl.glClear gl.GL_DEPTH_BUFFER_BIT))
    (when (and entry.target entry.target.update)
      (entry.target:update))
    (app.renderers:draw-target entry.target (or entry.options {}))))

(fn assert-button-label [button expected-font]
  (assert button "button snapshot missing button entity")
  (local label (and button button.text))
  (assert label "button snapshot missing text label")
  (local label-font (and label.style label.style.font))
  (assert label-font "button snapshot missing label font")
  (when expected-font
    (assert (= label-font expected-font) "button snapshot label font mismatch"))
  (local codepoints (label:get-codepoints))
  (assert (> (length codepoints) 0) "button snapshot missing label codepoints")
  (assert (not (label.layout:effective-culled?))
          "button snapshot label is culled")
  (assert (> label.layout.measure.x 0) "button snapshot label measure missing")
  (assert (> label.layout.size.x 0) "button snapshot label size missing"))

(fn add-centered-overlay-button [hud opts]
  (assert (and hud hud.overlay-root) "overlay button requires hud overlay root")
  (hud:update)
  (local overlay-layout hud.overlay-root.layout)
  (local center
    (+ overlay-layout.position
       (glm.vec3 (/ overlay-layout.size.x 2)
                 (/ overlay-layout.size.y 2)
                 0)))
  (local options (or opts {}))
  (local builder-options {})
  (each [key value (pairs options)]
    (set (. builder-options key) value))
  (var built nil)
  (set builder-options.on-built (fn [button]
                                  (set built button)))
  (local button-node
    (hud:add-overlay-child {:builder (fn [ctx]
                                       ((make-button-builder builder-options) ctx))
                            :position center}))
  (or built
      (or (. button-node :child) button-node)))

(fn capture-snapshot [opts]
  (gl.glFinish)
  (Snapshots.capture-and-compare opts))

{:app app
 :cleanup-target cleanup-target
 :cleanup cleanup
 :make-context make-context
 :with-app with-app
 :make-button-builder make-button-builder
 :make-test-button-row make-test-button-row
 :make-test-hud-builder make-test-hud-builder
 :make-screen-target make-screen-target
 :make-scene-target make-scene-target
 :make-hud-target make-hud-target
 :draw-targets draw-targets
 :assert-button-label assert-button-label
 :add-centered-overlay-button add-centered-overlay-button
 :capture-snapshot capture-snapshot}
