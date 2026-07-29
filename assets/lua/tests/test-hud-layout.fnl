(local glm (require :glm))
(local BuildContext (require :build-context))
(local HudLayout (require :hud-layout))
(local {: StatusPanelLayout} (require :hud-status-panel-layout))
(local {: Layout} (require :layout))

(local tests [])

(fn fixed-widget [name measure]
  (fn [_ctx]
    (local layout
      (Layout {:name name
               :measurer (fn [self]
                           (set self.measure measure))
               :layouter (fn [_self] nil)}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))}))

(fn captured-widget [name measure captured]
  (fn [_ctx]
    (local layout
      (Layout {:name name
               :measurer (fn [self]
                           (set self.measure measure))
               :layouter (fn [self]
                           (set self.size (or self.size self.measure))
                           (set captured.size self.size)
                           (set captured.position self.position))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))}))

(fn left-dock-fills-canvas-band-height []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 20
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))
       :left-dock-builder (fixed-widget "left-dock" (glm.vec3 6 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 4 5 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (local left-dock entity.left-dock-root)
  (assert left-dock "hud layout should create a left dock root when configured")
  (assert (= left-dock.layout.position.y 7)
          "left dock should start above the status panel at the canvas band origin")
  (assert (= left-dock.layout.size.y 25)
          "left dock should span the full canvas band between status and control panels")
  (entity:drop))

(fn left-dock-reserves-width-from-tiles []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 20
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))
       :left-dock-builder (fixed-widget "left-dock" (glm.vec3 6 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 4 5 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (local left-dock entity.left-dock-root)
  (local tiles entity.tiles-root)
  (assert left-dock "hud layout should create a left dock root when configured")
  (assert tiles "hud layout should create a tiles root")
  (assert (= tiles.layout.position.x 10)
          "tiles should start to the right of the reserved left dock width")
  (assert (= tiles.layout.size.x 34)
          "tiles should lose the reserved left dock width instead of overlapping it")
  (entity:drop))

(fn status-panel-layout-uses-single-gap-with-two-columns []
  (local commands-captured {})
  (local info-captured {})
  (local builder
    (StatusPanelLayout
      {:commands-builder (captured-widget "commands" (glm.vec3 3 1 0) commands-captured)
       :info-builder (captured-widget "info" (glm.vec3 4 1 0) info-captured)}))
  (local panel (builder (BuildContext {})))
  (panel.layout:measurer)
  (set panel.layout.position (glm.vec3 0 0 0))
  (set panel.layout.size (glm.vec3 20 4 0))
  (set panel.layout.rotation (glm.quat 1 0 0 0))
  (set panel.layout.clip-region nil)
  (set panel.layout.depth-offset-index 0)
  (panel.layout:layouter)
  (local commands-width (panel:commands-max-width))
  (assert (< (math.abs (- commands-width 14.0)) 0.001)
          (.. "status panel should reserve exactly one inter-column gap when body column is absent; got "
              commands-width))
  (assert (< (math.abs (- commands-captured.size.x 14.0)) 0.001)
          (.. "commands column child should receive the full remaining width after one gap; got "
              commands-captured.size.x))
  (local row-layout (. (. panel.children 2) :child :layout))
  (assert (= (length row-layout.children) 2)
          "status panel row should keep commands and info layouts when body column is absent")
  (assert info-captured.position
          "status panel should lay out the info column when body column is absent")
  (panel:drop))

(fn right-dock-appears-when-configured []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 30
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))
       :right-dock-builder (fixed-widget "right-dock" (glm.vec3 5 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 4 5 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (local right-dock entity.right-dock-root)
  (assert right-dock "hud layout should create a right dock root when configured")
  (entity:drop))

(fn right-dock-absent-when-not-configured []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 20
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 4 5 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (assert (not entity.right-dock-root) "hud layout should not create right dock when not configured")
  (entity:drop))

(fn right-dock-fills-canvas-band-height []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 30
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))
       :right-dock-builder (fixed-widget "right-dock" (glm.vec3 5 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 4 5 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (local right-dock entity.right-dock-root)
  (assert (= right-dock.layout.size.y 25)
          "right dock should span the full canvas band between status and control panels")
  (entity:drop))

(fn right-dock-coexists-with-left-dock []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 40
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))
       :left-dock-builder (fixed-widget "left-dock" (glm.vec3 6 4 0))
       :right-dock-builder (fixed-widget "right-dock" (glm.vec3 5 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 4 5 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (assert entity.left-dock-root "left dock should be present")
  (assert entity.right-dock-root "right dock should be present alongside left dock")
  (local tiles entity.tiles-root)
  (assert (> tiles.layout.size.x 0) "tiles should have positive width between docks")
  (entity:drop))

(fn right-dock-uses-natural-measured-width []
  (local hud {:world-units-per-pixel 0.05
              :margin-px 0
              :half-width 50
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))
       :right-dock-width 99
       :right-dock-builder (fixed-widget "right-dock" (glm.vec3 5 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 0 0 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (assert (= entity.right-dock-root.layout.size.x 5)
          "right dock should use its natural measured width, ignoring right-dock-width")
  (assert (= entity.tiles-root.layout.size.x 95)
          "tiles should reserve exactly the natural right dock width")
  (entity:drop))

(fn top-toolbar-reserves-center-column-between-full-height-rails []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 50
              :half-height 20})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 100 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 100 2 0))
       :left-dock-builder (fixed-widget "left" (glm.vec3 5 7 0))
       :right-dock-builder (fixed-widget "right" (glm.vec3 6 7 0))
       :top-toolbar-builder (fixed-widget "toolbar" (glm.vec3 20 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 0 0 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (assert entity.top-toolbar-root "top-toolbar-root should be created when top-toolbar-builder is set")
  (assert (= entity.top-toolbar-root.layout.size.x 89) ; 100 - 5 - 6
          (.. "top-toolbar width should be 89 (= 100 - 5 - 6), got " entity.top-toolbar-root.layout.size.x))
  (assert (= entity.top-toolbar-root.layout.size.y 4)
          (.. "top-toolbar height should be 4, got " entity.top-toolbar-root.layout.size.y))
  (assert (= entity.left-dock-root.layout.size.y 35) ; 40 - control 3 - status 2
          (.. "left dock should remain full-height 35, got " entity.left-dock-root.layout.size.y))
  (assert (= entity.right-dock-root.layout.size.y 35)
          (.. "right dock should remain full-height 35, got " entity.right-dock-root.layout.size.y))
  (assert (= entity.tiles-root.layout.size.y 31) ; middle 35 - toolbar 4
          (.. "tiles height should be 31 (= 35 - 4), got " entity.tiles-root.layout.size.y))
  (entity:drop))

(table.insert tests {:name "Hud layout top toolbar reserves center column between full-height rails"
                     :fn top-toolbar-reserves-center-column-between-full-height-rails})

(table.insert tests {:name "Hud layout left dock fills canvas band height"
                     :fn left-dock-fills-canvas-band-height})
(table.insert tests {:name "Hud layout left dock reserves width from tiles"
                     :fn left-dock-reserves-width-from-tiles})
(table.insert tests {:name "Hud layout right dock appears when configured"
                     :fn right-dock-appears-when-configured})
(table.insert tests {:name "Hud layout right dock absent when not configured"
                     :fn right-dock-absent-when-not-configured})
(table.insert tests {:name "Hud layout right dock fills canvas band height"
                     :fn right-dock-fills-canvas-band-height})
(table.insert tests {:name "Hud layout right dock coexists with left dock"
                     :fn right-dock-coexists-with-left-dock})
(table.insert tests {:name "Hud layout right dock uses natural measured width"
                     :fn right-dock-uses-natural-measured-width})
(table.insert tests {:name "Status panel layout uses one gap with two columns"
                     :fn status-panel-layout-uses-single-gap-with-two-columns})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud-layout"
                       :tests tests})))

{:name "hud-layout"
 :tests tests
 :main main}
