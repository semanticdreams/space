(local glm (require :glm))
(local BuildContext (require :build-context))
(local HudLayout (require :hud-layout))
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

(table.insert tests {:name "Hud layout left dock fills canvas band height"
                     :fn left-dock-fills-canvas-band-height})
(table.insert tests {:name "Hud layout left dock reserves width from tiles"
                     :fn left-dock-reserves-width-from-tiles})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud-layout"
                       :tests tests})))

{:name "hud-layout"
 :tests tests
 :main main}
