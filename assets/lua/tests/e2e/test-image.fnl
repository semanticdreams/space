(local Harness (require :tests.e2e.harness))
(local Image (require :image))

(fn run [ctx]
  (var image-node nil)
  (local image-builder
    (fn [child-ctx]
      (local image ((Image {:path "pics/test.png"
                            :base-width 18}) child-ctx))
      (set image-node image)
      image))
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder image-builder}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (assert image-node "image snapshot missing image entity")
  (assert image-node.texture "image snapshot missing texture")
  (assert (> (or image-node.texture.width 0) 0)
          "image snapshot texture width missing")
  (assert (> (or image-node.texture.height 0) 0)
          "image snapshot texture height missing")
  (assert (not (image-node.layout:effective-culled?))
          "image snapshot is culled")
  (Harness.capture-snapshot {:name "image"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E image snapshot complete"))

{:run run
 :main main}
