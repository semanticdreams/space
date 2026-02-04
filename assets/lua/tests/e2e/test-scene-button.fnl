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
  (Harness.draw-targets ctx.width ctx.height [{:target scene-target}])
  (Harness.assert-button-label scene-button ctx.font)
  (Harness.capture-snapshot {:name "scene-button"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target scene-target)
  (camera:drop))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E scene-button snapshot complete"))

{:run run
 :main main}
