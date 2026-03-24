(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local Camera (require :camera))
(local Ball (require :ball))
 (local {: Layout} (require :layout))

(fn run [ctx]
  (local camera (Camera {:position (glm.vec3 0 0 42)}))
  (camera:look-at (glm.vec3 0 0 0))
  (local scene-target
    (Harness.make-scene-target
      {:builder
       (fn [child-ctx]
         (local left-ball
           ((Ball {:size (glm.vec3 20 20 20)
                   :position (glm.vec3 0 0 0)})
            child-ctx))
         (local right-ball
           ((Ball {:size (glm.vec3 20 20 20)
                   :position (glm.vec3 0 0 0)})
            child-ctx))
         (local root-layout
           (Layout {:name "soccer-ball-preview-root"
                    :children [left-ball.layout right-ball.layout]
                    :measurer (fn [self]
                                (left-ball.layout:measurer)
                                (right-ball.layout:measurer)
                                (set self.measure (glm.vec3 52 24 0)))
                    :layouter (fn [self]
                                (set self.size self.measure)
                                (set left-ball.layout.size (or left-ball.layout.measure (glm.vec3 20 20 20)))
                                (set left-ball.layout.position (+ self.position (glm.vec3 0 2 0)))
                                (set left-ball.layout.rotation (* self.rotation
                                                                  (glm.quat (math.rad -18) (glm.vec3 1 0 0))
                                                                  (glm.quat (math.rad 12) (glm.vec3 0 1 0))))
                                (left-ball.layout:layouter)
                                (set right-ball.layout.size (or right-ball.layout.measure (glm.vec3 20 20 20)))
                                (set right-ball.layout.position (+ self.position (glm.vec3 24 -2 0)))
                                (set right-ball.layout.rotation (* self.rotation
                                                                   (glm.quat (math.rad 22) (glm.vec3 1 1 0))
                                                                   (glm.quat (math.rad 44) (glm.vec3 0 1 0))))
                                (right-ball.layout:layouter))}))
         {:layout root-layout
          :drop (fn [self]
                  (self.layout:drop)
                  (left-ball:drop)
                  (right-ball:drop))})
       :view-matrix (camera:get-view-matrix)
       :child-position (glm.vec3 0 0 0)
       :child-rotation (glm.quat 1 0 0 0)}))
  (Harness.draw-targets ctx.width ctx.height [{:target scene-target}])
  (Harness.capture-snapshot {:name "soccer-ball-preview"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target scene-target)
  (camera:drop))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E soccer ball preview snapshot complete"))

{:run run
 :main main}
