(local Harness (require :tests.e2e.harness))
(local XdgIconBrowser (require :xdg-icon-browser))
(local Sized (require :sized))
(local glm (require :glm))
(local Padding (require :padding))
(local DefaultDialog (require :default-dialog))

(fn run [ctx]
    (local width ctx.width)
    (local height ctx.height)
    (local browser-builder
        (fn [child-ctx]
            (local dlg
                (DefaultDialog
                    {:title "Icon Browser"
                     :name "test-dialog"
                     :resizeable true
                     :child (XdgIconBrowser.XdgIconBrowser {:initial-context "actions"})}))
            (dlg child-ctx)))

    (local sized
        (Sized {:size (glm.vec3 32 24 0)
                :child browser-builder}))

    (local target
        (Harness.make-screen-target {:width width
                                     :height height
                                     :world-units-per-pixel ctx.units-per-pixel
                                     :projection (glm.ortho 0 32 0 24 -100 100)
                                     :builder (fn [child-ctx] (sized child-ctx))}))

    (Harness.draw-targets width height [{:target target}])
    (Harness.capture-snapshot {:name "xdg-icon-browser"
                               :width width
                               :height height
                               :tolerance 2})
    (Harness.cleanup-target target))

(fn main []
    (Harness.with-app {:width 640 :height 480}
                     (fn [ctx]
                         (run ctx)))
    (print "E2E xdg-icon-browser snapshot complete"))

{:run run
 :main main}
