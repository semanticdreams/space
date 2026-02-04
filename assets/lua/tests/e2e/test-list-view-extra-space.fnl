(local Harness (require :tests.e2e.harness))
(local ListView (require :list-view))
(local Sized (require :sized))
(local glm (require :glm))

(fn run [ctx]
  (local items ["Alpha" "Bravo" "Charlie"])
  (local list-builder
    (fn [child-ctx]
      (local list ((ListView {:items items
                              :scroll true
                              :show-head false
                              :fill-width true
                              :items-per-page 6}) child-ctx))
      list))
  (local sized
    (Sized {:size (glm.vec3 18 12 0)
            :child list-builder}))
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (fn [child-ctx] (sized child-ctx))}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "list-view-extra-space"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 4})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E list-view extra-space snapshot complete"))

{:run run
 :main main}
