(local Harness (require :tests.e2e.harness))

(fn run [ctx]
  (var button-only nil)
  (local button-builder
    (Harness.make-button-builder {:variant :secondary
                                  :text-scale 4
                                  :on-built (fn [button]
                                              (set button-only button))}))
  (local button-target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder button-builder}))
  (Harness.draw-targets ctx.width ctx.height [{:target button-target}])
  (Harness.assert-button-label button-only ctx.font)
  (Harness.capture-snapshot {:name "button"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target button-target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E button snapshot complete"))

{:run run
 :main main}
