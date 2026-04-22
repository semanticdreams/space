(global app (or app {}))

(local glm (require :glm))
(local Hud (require :hud))
(local {: Layout} (require :layout))
(local HudLayout (require :hud-layout))
(local PanelUtils (require :target-panel-utils))

(local tests [])

(fn approx [a b eps]
  (<= (math.abs (- a b)) (or eps 1e-6)))

(fn adaptive-hud-keeps-reference-scale-at-1080p []
  (local hud (Hud {}))
  (hud:update-projection {:width 1920 :height 1080})
  (assert (approx hud.effective-scale-factor (/ 5 3))
          "1920x1080 should keep the baseline HUD scale factor")
  (assert (approx hud.world-units-per-pixel (/ 1 12))
          "1920x1080 should keep the baseline HUD world-units-per-pixel")
  (hud:drop))

(fn adaptive-hud-grows-at-1200p []
  (local hud (Hud {}))
  (hud:update-projection {:width 1920 :height 1200})
  (assert (approx hud.effective-scale-factor 1.5)
          "1920x1200 should reduce effective scale factor so HUD renders larger")
  (assert (approx hud.world-units-per-pixel 0.075)
          "1920x1200 should reduce world-units-per-pixel so HUD renders larger")
  (hud:drop))

(fn adaptive-hud-keeps-baseline-at-smaller-heights []
  (local hud (Hud {}))
  (hud:update-projection {:width 1600 :height 900})
  (assert (approx hud.effective-scale-factor (/ 5 3))
          "viewports shorter than 1080p should keep baseline readability")
  (assert (approx hud.world-units-per-pixel (/ 1 12))
          "viewports shorter than 1080p should keep baseline world-units-per-pixel")
  (hud:drop))

(fn adaptive-hud-ignores-placeholder-viewport []
  (local hud (Hud {}))
  (hud:update-projection {:width 1 :height 1})
  (assert (approx hud.effective-scale-factor (/ 5 3))
          "placeholder viewport should keep the requested scale factor")
  (assert (approx hud.world-units-per-pixel (/ 1 12))
          "placeholder viewport should keep baseline world-units-per-pixel")
  (hud:drop))

(fn vec-approx [left right eps]
  (and (approx left.x right.x eps)
       (approx left.y right.y eps)
       (approx left.z right.z eps)))

(fn array->vec3 [items]
  (glm.vec3 (. items 1)
            (. items 2)
            (. items 3)))

(fn fixed-widget [name measure]
  (fn [_ctx]
    (local layout
      (Layout {:name name
               :measurer (fn [self]
                           (set self.measure measure))
               :layouter (fn [self]
                           (set self.size (or self.size self.measure)))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))}))

(fn build-test-hud [width height]
  (local hud (Hud {}))
  (hud:build
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))}))
  (hud:update-projection {:width width :height height})
  (hud:update)
  hud)

(fn hud-float-persistence-stays-resolution-independent []
  (local kind "hud-test-panel")
  (local dialog-builder (fixed-widget "dialog" (glm.vec3 4 3 0)))
  (local original-hud (build-test-hud 1920 1080))
  (original-hud:register-panel-restorer
    kind
    (fn [panel]
      (local placement (PanelUtils.panel-placement-options original-hud panel))
      (original-hud:add-panel-child {:builder dialog-builder
                                     :location placement.location
                                     :position placement.position
                                     :rotation placement.rotation
                                     :size placement.size
                                     :align-x placement.align-x
                                     :align-y placement.align-y
                                     :persistence {:kind kind}})))
  (original-hud:add-panel-child {:builder dialog-builder
                                 :location :float
                                 :position (glm.vec3 3 4 0)
                                 :rotation (glm.quat 1 0 0 0)
                                 :size (glm.vec3 10 6 0)
                                 :persistence {:kind kind}})
  (original-hud:update)
  (local captured (original-hud:capture-state))
  (local original-panel (. captured.panels 1))
  (assert (= (type original-panel.relative-position) :table)
          "HUD float persistence should store relative position")
  (assert (= (type original-panel.relative-size) :table)
          "HUD float persistence should store relative size")
  (original-hud:drop)

  (local restored-hud (build-test-hud 1920 1200))
  (restored-hud:register-panel-restorer
    kind
    (fn [panel]
      (local placement (PanelUtils.panel-placement-options restored-hud panel))
      (restored-hud:add-panel-child {:builder dialog-builder
                                     :location placement.location
                                     :position placement.position
                                     :rotation placement.rotation
                                     :size placement.size
                                     :align-x placement.align-x
                                     :align-y placement.align-y
                                     :persistence {:kind kind}})))
  (restored-hud:restore-state captured)
  (restored-hud:update)
  (local restored (restored-hud:capture-state))
  (local restored-panel (. restored.panels 1))
  (assert (vec-approx (array->vec3 restored-panel.relative-position)
                      (array->vec3 original-panel.relative-position)
                      1e-6)
          "HUD float persistence should preserve relative position across resolutions")
  (assert (vec-approx (array->vec3 restored-panel.relative-size)
                      (array->vec3 original-panel.relative-size)
                      1e-6)
          "HUD float persistence should preserve relative size across resolutions")
  (restored-hud:drop))

(fn hud-screen-pos-ray-converts-logical-input-to-viewport-space []
  (local original-engine app.engine)
  (local original-viewport app.viewport)
  (var hud nil)
  (set app.engine {:width 100 :height 50})
  (set app.viewport {:x 0 :y 0 :width 200 :height 100})
  (set hud (Hud {}))
  (hud:update-projection app.viewport)
  (local logical-ray (hud:screen-pos-ray {:x 50 :y 25}))
  (assert (approx logical-ray.origin.x 0 1e-6)
          "HUD logical input conversion should keep the viewport center on the HUD origin")
  (assert (approx logical-ray.origin.y 0 1e-6)
          "HUD logical input conversion should keep the viewport center on the HUD origin")
  (assert (approx logical-ray.direction.x 0 1e-6)
          "HUD logical input conversion should keep the center ray aligned on the Z axis")
  (assert (approx logical-ray.direction.y 0 1e-6)
          "HUD logical input conversion should keep the center ray aligned on the Z axis")
  (hud:drop)
  (set app.viewport original-viewport)
  (set app.engine original-engine))

(table.insert tests {:name "Hud adaptive scaling keeps reference scale at 1080p"
                     :fn adaptive-hud-keeps-reference-scale-at-1080p})
(table.insert tests {:name "Hud adaptive scaling grows at 1200p"
                     :fn adaptive-hud-grows-at-1200p})
(table.insert tests {:name "Hud adaptive scaling keeps baseline at smaller heights"
                     :fn adaptive-hud-keeps-baseline-at-smaller-heights})
(table.insert tests {:name "Hud adaptive scaling ignores placeholder viewport"
                     :fn adaptive-hud-ignores-placeholder-viewport})
(table.insert tests {:name "Hud float persistence stays resolution independent"
                     :fn hud-float-persistence-stays-resolution-independent})
(table.insert tests {:name "Hud screen-pos-ray converts logical input to viewport space"
                     :fn hud-screen-pos-ray-converts-logical-input-to-viewport-space})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud"
                       :tests tests})))

{:name "hud"
 :tests tests
 :main main}
