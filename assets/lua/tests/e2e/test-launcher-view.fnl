(local glm (require :glm))
(local Harness (require :tests.e2e.harness))
(local LauncherView (require :launcher-view))

(fn run [ctx]
  (local hud-target
    (Harness.make-hud-target {:width ctx.width
                              :height ctx.height
                              :scale-factor 1.0
                              :builder (Harness.make-test-hud-builder)}))

  (hud-target:update)
  (local float-layout (and hud-target.float hud-target.float.layout))
  (assert float-layout "launcher-view snapshot requires hud float layout")
  (local float-center
    (+ float-layout.position
       (glm.vec3 (/ float-layout.size.x 2)
                 (/ float-layout.size.y 2)
                 0)))
  (local dialog-size (glm.vec3 18 10 0))
  (local dialog-position
    (- float-center
       (glm.vec3 (/ dialog-size.x 2)
                 (/ dialog-size.y 2)
                 0)))

  (local view
    (hud-target:add-panel-child
      {:builder (LauncherView {:title "Launcher"})
       :location :float
       :position dialog-position
       :size dialog-size}))

  (view:set-query "ch")
  (view:set-items [{:name "Chat" :run (fn [] nil)}
                   {:name "Graph Control" :run (fn [] nil)}
                   {:name "Terminal" :run (fn [] nil)}])

  (Harness.draw-targets ctx.width ctx.height [{:target hud-target}])
  (Harness.capture-snapshot {:name "launcher-view"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target hud-target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E launcher-view snapshot complete"))

{:run run
 :main main}
