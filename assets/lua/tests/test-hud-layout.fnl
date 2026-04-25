(local glm (require :glm))
(local BuildContext (require :build-context))
(local HudLayout (require :hud-layout))
(local {: StatusAnchored} (require :hud-layout))
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

(fn status-anchored-follows-status-height []
  (var status-height 2)
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 20
              :half-height 15
              :entity nil})
  (local ctx (BuildContext {:pointer-target hud}))

  (fn dynamic-status [_ctx]
    (local layout
      (Layout {:name "dynamic-status"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 8 status-height 0)))
               :layouter (fn [self]
                           (set self.size (or self.size self.measure)))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))})

  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder dynamic-status}))
  (local entity (builder ctx))
  (set hud.entity entity)
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 4 5 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)

  (local anchored ((StatusAnchored {:hud hud
                                    :child (fixed-widget "overlay" (glm.vec3 8 1 0))})
                   ctx))
  (anchored.layout:measurer)
  (set anchored.layout.position (glm.vec3 4 5 0))
  (set anchored.layout.size anchored.layout.measure)
  (set anchored.layout.rotation (glm.quat 1 0 0 0))
  (set anchored.layout.clip-region nil)
  (set anchored.layout.depth-offset-index 0)
  (anchored.layout:layouter)
  (assert (= anchored.child.layout.position.y 7)
          "status-anchored should start directly above the current status height")

  (set status-height 5)
  (entity.layout:measurer)
  (set entity.layout.size entity.layout.measure)
  (entity.layout:layouter)
  (anchored.layout:measurer)
  (set anchored.layout.size anchored.layout.measure)
  (anchored.layout:layouter)
  (assert (= anchored.child.layout.position.y 10)
          "status-anchored should follow status height changes without manual repositioning")

  (anchored:drop)
  (entity:drop))

(fn status-anchored-fails-without-status-root []
  (local hud {:world-units-per-pixel 1
              :margin-px 0
              :half-width 20
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local anchored ((StatusAnchored {:hud hud
                                    :child (fixed-widget "overlay" (glm.vec3 8 1 0))})
                   ctx))
  (anchored.layout:measurer)
  (set anchored.layout.position (glm.vec3 4 5 0))
  (set anchored.layout.size anchored.layout.measure)
  (set anchored.layout.rotation (glm.quat 1 0 0 0))
  (set anchored.layout.clip-region nil)
  (set anchored.layout.depth-offset-index 0)
  (local (ok err) (pcall (fn []
                           (anchored.layout:layouter))))
  (assert (not ok)
          "status-anchored should fail loudly when status-root wiring is missing")
  (assert (and err (string.find err "StatusAnchored requires hud.entity"))
          "status-anchored should report the missing HUD status-root wiring")
  (anchored:drop))

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

(table.insert tests {:name "Hud layout left dock fills canvas band height"
                     :fn left-dock-fills-canvas-band-height})
(table.insert tests {:name "Hud layout left dock reserves width from tiles"
                     :fn left-dock-reserves-width-from-tiles})
(table.insert tests {:name "Hud layout status anchored follows status height"
                     :fn status-anchored-follows-status-height})
(table.insert tests {:name "Hud layout status anchored fails without status root"
                     :fn status-anchored-fails-without-status-root})
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
