(local Harness (require :tests.e2e.harness))
(local ComboBox (require :combo-box))
(local Button (require :button))
(local Sized (require :sized))
(local Stack (require :stack))
(local Rectangle (require :rectangle))
(local {: Flex : FlexChild} (require :flex))
(local glm (require :glm))

(fn make-combo-builder []
    (var combo nil)
    {:builder (fn [ctx]
                  (set combo
                       ((ComboBox {:items ["system" "user" "assistant"]
                                   :value "assistant"
                                   :max-visible-items 10})
                        ctx))
                  (combo:open)
                  combo)
     :get (fn [] combo)})

(fn run [ctx]
    (local combo-spec (make-combo-builder))
    (local combo-sized
        (Sized {:size (glm.vec3 18 2.6 0)
                :child combo-spec.builder}))
    (local below-sized
        (Sized {:size (glm.vec3 18 2.6 0)
                :child (Button {:text "Below"
                                :variant :secondary})}))
    (local column
        (Flex {:axis :y
               :reverse true
               :yspacing 0.7
               :xalign :start
               :children [(FlexChild combo-sized 0)
                          (FlexChild below-sized 0)]}))
    (local content
        (Sized {:size (glm.vec3 20 12 0)
                :child column}))
    (local background
        (Rectangle {:color (glm.vec4 0.08 0.09 0.12 1)}))
    (local stack
        (Stack {:children [background content]}))
    (local target
        (Harness.make-screen-target {:width ctx.width
                                     :height ctx.height
                                     :world-units-per-pixel ctx.units-per-pixel
                                     :builder (fn [child-ctx] (stack child-ctx))}))
    (Harness.draw-targets ctx.width ctx.height [{:target target}])
    (Harness.capture-snapshot {:name "combo-box"
                               :width ctx.width
                               :height ctx.height
                               :tolerance 2})
    (Harness.cleanup-target target))

(fn main []
    (Harness.with-app {}
                     (fn [ctx]
                         (run ctx)))
    (print "E2E combo-box snapshot complete"))

{:run run
 :main main}
