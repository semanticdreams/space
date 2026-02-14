(local Harness (require :tests.e2e.harness))
(local DefaultDialog (require :default-dialog))
(local Sized (require :sized))
(local SubAppView (require :sub-app-view))
(local NextAppSubApp (require :next-app/sub-app))
(local glm (require :glm))

(fn assert-stable-submit [name sub-app]
  (assert sub-app (.. "next-app snapshot requires sub-app for " name))
  (app.renderers:prerender-sub-apps)
  (local cold (sub-app:get-submit-stats))
  (app.renderers:prerender-sub-apps)
  (local hot (sub-app:get-submit-stats))
  (assert cold (.. "missing cold submit stats for " name))
  (assert hot (.. "missing hot submit stats for " name))
  (assert (= hot.write-count 0)
          (.. "expected zero write-count on steady frame for " name
               ", got " hot.write-count))
  (assert (= hot.upsert-count 0)
          (.. "expected zero upsert-count on steady frame for " name
               ", got " hot.upsert-count)))

(fn capture-scenario [ctx scenario]
  (var scenario-sub-app nil)
  (local dialog-builder
    (DefaultDialog
      {:title "Next App Snapshot"
       :child (SubAppView {:name (.. "next-app-snapshot-" scenario.name)
                           :size (glm.vec3 20 13 0)
                           :units-per-pixel ctx.units-per-pixel
                           :on-sub-app (fn [sub-app]
                                         (set scenario-sub-app sub-app))
                           :sub-app-builder NextAppSubApp
                           :sub-app-options
                           {:renderer-options
                            {:title scenario.title
                             :subtitle scenario.subtitle
                             :note scenario.note
                             :footer scenario.footer
                             :scenario scenario.scenario
                             :enable-focus true
                             :root-width 1.82
                             :root-height 1.66
                             :root-position {:x -0.91 :y -0.83 :z 0 :rotation-z 0}}}})}))
  (local sized
    (Sized {:size (glm.vec3 33 23 0)
            :child (fn [child-ctx]
                     (dialog-builder child-ctx))}))
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (fn [child-ctx]
                                            (sized child-ctx))}))
  (assert-stable-submit scenario.name scenario-sub-app)
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (app.renderers:draw-sub-apps target)
  (Harness.capture-snapshot {:name scenario.name
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (Harness.cleanup-target target))

(fn run [ctx]
  (local (ok err)
    (xpcall
      (fn []
        (local scenarios
          [{:name "next-app"
            :scenario :default
            :title "Next App UI Snapshot"
            :subtitle "Default interaction state"
            :note "Panel + Flex + Button + Input + Scroll + VirtualList + SSBO text"
            :footer "Default"}
           {:name "next-app-focused"
            :scenario :focused
            :title "Next App Focused Snapshot"
            :subtitle "Focused input + pressed/hovered controls"
            :note "Interaction state: focused"
            :footer "Focused"}
           {:name "next-app-scrolled"
            :scenario :scrolled
            :title "Next App Scrolled Snapshot"
            :subtitle "Virtual list deep scroll"
            :note "Interaction state: scrolled"
            :footer "Scrolled"}])
        (each [_ scenario (ipairs scenarios)]
          (capture-scenario ctx scenario)))
      debug.traceback))
  (when (not ok)
    (error err)))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E next-app snapshot complete"))

{:run run
 :main main}
