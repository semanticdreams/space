(local Harness (require :tests.e2e.harness))
(local DefaultDialog (require :default-dialog))
(local Sized (require :sized))
(local SubAppView (require :sub-app-view))
(local glm (require :glm))

(fn run [ctx]
  (local (ok err)
    (xpcall
      (fn []
        (local dialog-builder
          (DefaultDialog {:title "Sub App One"
                          :child (SubAppView {:name "sub-world-one"
                                              :size (glm.vec3 18 12 0)
                                              :units-per-pixel ctx.units-per-pixel})}))
        (local sized
          (Sized {:size (glm.vec3 32 22 0)
                  :child (fn [child-ctx]
                           (dialog-builder child-ctx))}))
        (local target
          (Harness.make-screen-target {:width ctx.width
                                       :height ctx.height
                                       :world-units-per-pixel ctx.units-per-pixel
                                       :builder (fn [child-ctx]
                                                  (sized child-ctx))}))
        (app.renderers:prerender-sub-apps)
        (Harness.draw-targets ctx.width ctx.height [{:target target}])
        (app.renderers:draw-sub-apps target)
        (Harness.capture-snapshot {:name "sub-app-dialog"
                                   :width ctx.width
                                   :height ctx.height
                                   :tolerance 3})
        (Harness.cleanup-target target))
      debug.traceback))
  (when (not ok)
    (error err)))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E sub app dialog snapshot complete"))

{:run run
 :main main}
