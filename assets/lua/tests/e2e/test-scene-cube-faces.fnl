(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local Camera (require :camera))
(local Cuboid (require :cuboid))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Stack (require :stack))
(local Sized (require :sized))
(local Aligned (require :aligned))
(local {: Layout} (require :layout))

(fn make-face-builder [label bg-color]
  (fn [ctx]
    ((Sized {:size (glm.vec3 14 14 0)
             :child (Stack {:children
                            [(Rectangle {:color bg-color})
                             (Aligned {:xalign :center
                                       :yalign :center
                                       :child (Text {:text label
                                                     :style (TextStyle {:scale 2.2
                                                                        :color (glm.vec4 1 1 1 1)})})})]})}) ctx)))

(fn make-cube-builder []
  (local face-builders
    [(make-face-builder "FRONT" (glm.vec4 0.80 0.26 0.26 1))
     (make-face-builder "BACK" (glm.vec4 0.27 0.57 0.83 1))
     (make-face-builder "RIGHT" (glm.vec4 0.92 0.64 0.20 1))
     (make-face-builder "LEFT" (glm.vec4 0.30 0.72 0.47 1))
     (make-face-builder "TOP" (glm.vec4 0.66 0.39 0.78 1))
     (make-face-builder "BOTTOM" (glm.vec4 0.56 0.56 0.56 1))])
  (Cuboid {:children face-builders}))

(fn build-cube-scene [ctx]
  (local cube-builder (make-cube-builder))
  (local cubes
    [{:widget (cube-builder ctx)
      :position (glm.vec3 -28 -10 20)
      :rotation (* (glm.quat (math.rad -24) (glm.vec3 0 1 0))
                   (glm.quat (math.rad 9) (glm.vec3 1 0 0)))}
     {:widget (cube-builder ctx)
      :position (glm.vec3 24 -8 -8)
      :rotation (* (glm.quat (math.rad 18) (glm.vec3 0 1 0))
                   (glm.quat (math.rad -7) (glm.vec3 1 0 0)))}
     {:widget (cube-builder ctx)
      :position (glm.vec3 -6 10 -30)
      :rotation (* (glm.quat (math.rad 42) (glm.vec3 0 1 0))
                   (glm.quat (math.rad 14) (glm.vec3 1 0 0)))}
     {:widget (cube-builder ctx)
      :position (glm.vec3 30 12 -50)
      :rotation (* (glm.quat (math.rad -35) (glm.vec3 0 1 0))
                   (glm.quat (math.rad 11) (glm.vec3 1 0 0)))}
     {:widget (cube-builder ctx)
      :position (glm.vec3 -34 14 -66)
      :rotation (* (glm.quat (math.rad 28) (glm.vec3 0 1 0))
                   (glm.quat (math.rad -12) (glm.vec3 1 0 0)))}])

  (local layout
    (Layout {:name "e2e-scene-cube-field"
             :children (icollect [_ cube (ipairs cubes)]
                                 cube.widget.layout)
             :measurer (fn [self]
                         (each [_ cube (ipairs cubes)]
                           (cube.widget.layout:measurer))
                         (set self.measure (glm.vec3 92 52 0)))
             :layouter (fn [self]
                         (set self.size self.measure)
                         (each [i cube (ipairs cubes)]
                           (local child cube.widget.layout)
                           (local child-size (or child.measure (glm.vec3 0 0 0)))
                           (set child.size child-size)
                           (set child.position (+ self.position cube.position))
                           (set child.rotation (* self.rotation cube.rotation))
                           (set child.depth-offset-index (+ self.depth-offset-index (* i 0.01)))
                           (set child.clip-region self.clip-region)
                           (child:layouter)))}))

  {:layout layout
   :drop (fn [self]
           (self.layout:drop)
           (each [_ cube (ipairs cubes)]
             (cube.widget:drop)))})

(fn run [ctx]
  (local camera (Camera {:position (glm.vec3 0 12 124)}))
  (camera:look-at (glm.vec3 0 0 -34))
  (local scene-target
    (Harness.make-scene-target {:builder (fn [child-ctx]
                                           (build-cube-scene child-ctx))
                                :view-matrix (camera:get-view-matrix)}))
  (Harness.draw-targets ctx.width ctx.height [{:target scene-target}])
  (Harness.capture-snapshot {:name "scene-cube-faces"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target scene-target)
  (camera:drop))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E scene-cube-faces snapshot complete"))

{:run run
 :main main}
