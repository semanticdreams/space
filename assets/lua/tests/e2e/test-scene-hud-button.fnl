(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local WidgetCuboid (require :widget-cuboid))
(local Camera (require :camera))

(fn run [ctx]
  (var scene-button nil)
  (local camera (Camera {:position (glm.vec3 0 0 30)}))
  (camera:look-at (glm.vec3 0 0 0))
  (local scene-builder
    (Harness.make-button-builder {:variant :secondary
                                  :text-scale 3
                                  :on-built (fn [button]
                                              (set scene-button button))}))
  (local scene-target
    (Harness.make-scene-target {:builder (fn [ctx]
                                           ((WidgetCuboid {:child scene-builder
                                                           :depth-scale 0.5
                                                           :min-depth 2}) ctx))
                                :view-matrix (camera:get-view-matrix)
                                :child-position (glm.vec3 0 0 0)
                                :child-rotation (glm.quat (math.rad -10) (glm.vec3 0 1 0))}))
  (local scene-hud-target
    (Harness.make-hud-target {:width ctx.width
                              :height ctx.height
                              :scale-factor 1.0
                              :builder (Harness.make-test-hud-builder)}))
  (local scene-hud-button
    (Harness.add-centered-overlay-button scene-hud-target
                                         {:text "HUD"
                                          :text-scale 2
                                          :padding [0.6 0.4]}))
  (Harness.draw-targets ctx.width ctx.height [{:target scene-target}
                                              {:target scene-hud-target :clear-depth? true}])
  (Harness.assert-button-label scene-hud-button ctx.font)
  (Harness.capture-snapshot {:name "scene-hud-button"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target scene-target)
  (Harness.cleanup-target scene-hud-target)
  (camera:drop))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E scene-hud-button snapshot complete"))

{:run run
 :main main}
