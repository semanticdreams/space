(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local {: QrCodeWidget} (require :qr-code-widget))

(fn run [ctx]
  (local target
    (Harness.make-screen-target
      {:width ctx.width
       :height ctx.height
       :world-units-per-pixel ctx.units-per-pixel
       :builder (fn [child-ctx]
                  ((QrCodeWidget {:name "qr-code-view"
                                  :value "0xabc123abc123abc123abc123abc123abc123abc1"
                                  :module-size 0.6
                                  :quiet-zone 4
                                  :foreground (glm.vec4 0 0 0 1)
                                  :background (glm.vec4 1 1 1 1)})
                   child-ctx))}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "qr-code-view"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {:width 1280
                     :height 720
                     :units-per-pixel 0.05}
                    (fn [ctx]
                      (run ctx)))
  (print "E2E qr code view snapshot complete"))

{:run run
 :main main}
