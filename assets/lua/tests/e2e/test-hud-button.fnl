(local Harness (require :tests.e2e.harness))

(fn run [ctx]
  (local hud-target
    (Harness.make-hud-target {:width ctx.width
                              :height ctx.height
                              :scale-factor 1.0
                              :builder (Harness.make-test-hud-builder)}))
  (local hud-overlay-button
    (Harness.add-centered-overlay-button hud-target
                                         {:text "HUD"
                                          :text-scale 2
                                          :padding [0.6 0.4]}))
  (Harness.draw-targets ctx.width ctx.height [{:target hud-target}])
  (Harness.assert-button-label hud-overlay-button ctx.font)
  (Harness.capture-snapshot {:name "hud-button"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target hud-target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E hud-button snapshot complete"))

{:run run
 :main main}
