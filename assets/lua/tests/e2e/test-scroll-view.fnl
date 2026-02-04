(local Harness (require :tests.e2e.harness))
(local StateBase (require :state-base))
(local Fixture (require :tests.e2e.scroll-view-fixture))

(fn run [ctx]
  (local built (Fixture.make-scroll-view-builder {:items ["Alpha" "Bravo" "Charlie" "Delta"
                                                         "Echo" "Foxtrot" "Golf" "Hotel"]}))
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder built.builder}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (local view (built.get-view))
  (assert view "scroll-view snapshot missing view")
  (local pointer (Fixture.scrollbar-center-screen ctx view))
  (app.hoverables:on-mouse-motion pointer)
  (StateBase.dispatch-mouse-wheel {:x pointer.x :y -1})
  (StateBase.dispatch-mouse-wheel {:x pointer.x :y -1})
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "scroll-view"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E scroll-view snapshot complete"))

{:run run
 :main main}
