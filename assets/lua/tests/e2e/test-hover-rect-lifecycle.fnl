(local Harness (require :tests.e2e.harness))
(local Button (require :button))
(local Sized (require :sized))
(local glm (require :glm))

(fn run [ctx]
  (var button nil)
  (local target
    (Harness.make-screen-target
      {:width ctx.width
       :height ctx.height
       :world-units-per-pixel ctx.units-per-pixel
       :builder
       (fn [child-ctx]
         (local built
           ((Button {:text "Hover me"
                     :variant :ghost
                     :padding [0.9 0.7]}) child-ctx))
         (set button built)
         ((Sized {:size (glm.vec3 15 5 0)
                  :child (fn [_] built)}) child-ctx))}))

  (assert button "hover lifecycle snapshot missing button")

  (Harness.draw-targets ctx.width ctx.height [{:target target}])

  ;; Simulate hover background on, move container, then clear hover.
  (button:on-hovered true)
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (target.root-layout:set-position (glm.vec3 2.5 0 0))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (button:on-hovered false)
  (Harness.draw-targets ctx.width ctx.height [{:target target}])

  ;; Simulate dialog close: drop widget subtree while target continues rendering.
  (button:drop)
  (target.root-layout:clear-children)
  (target.root-layout:mark-measure-dirty)
  (Harness.draw-targets ctx.width ctx.height [{:target target}])

  (Harness.capture-snapshot {:name "hover-rect-lifecycle"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E hover rect lifecycle snapshot complete"))

{:run run
 :main main}
