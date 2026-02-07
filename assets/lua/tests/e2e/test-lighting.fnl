(local Harness (require :tests.e2e.harness))
(local LightSystem (require :light-system))
(local Camera (require :camera))
(local glm (require :glm))
(local textures (require :textures))
(local {: Layout} (require :layout))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(fn make-test-texture []
  (assert textures.load-texture-from-pixels
          "Lighting e2e requires textures.load-texture-from-pixels")
  (local width 2)
  (local height 2)
  (local channels 4)
  (local bytes
    (string.char
      220 220 220 255  240 240 240 255
      200 200 200 255  230 230 230 255))
  (textures.load-texture-from-pixels "lighting-quad"
                                     width
                                     height
                                     channels
                                     bytes
                                     true))

(fn write-vertex [vector handle offset vertex]
  (vector:set-float handle (+ offset 0) (. vertex 1))
  (vector:set-float handle (+ offset 1) (. vertex 2))
  (vector:set-float handle (+ offset 2) (. vertex 3))
  (vector:set-float handle (+ offset 3) (. vertex 4))
  (vector:set-float handle (+ offset 4) (. vertex 5))
  (vector:set-float handle (+ offset 5) (. vertex 6))
  (vector:set-float handle (+ offset 6) (. vertex 7))
  (vector:set-float handle (+ offset 7) (. vertex 8)))

(fn plane-vertices [half-x half-z y]
  (local hx half-x)
  (local hz half-z)
  (local yy (or y 0))
  [;; +Y plane
   [0 0 0 1 0 (- hx) yy (- hz)]
   [1 0 0 1 0 hx yy (- hz)]
   [1 1 0 1 0 hx yy hz]
   [0 0 0 1 0 (- hx) yy (- hz)]
   [1 1 0 1 0 hx yy hz]
   [0 1 0 1 0 (- hx) yy hz]])

(fn cube-vertices [half]
  (local h half)
  [;; +Z
   [0 0 0 0 1 (- h) (- h) h]
   [1 0 0 0 1 h (- h) h]
   [1 1 0 0 1 h h h]
   [0 0 0 0 1 (- h) (- h) h]
   [1 1 0 0 1 h h h]
   [0 1 0 0 1 (- h) h h]
   ;; -Z
   [1 0 0 0 -1 (- h) (- h) (- h)]
   [1 1 0 0 -1 (- h) h (- h)]
   [0 1 0 0 -1 h h (- h)]
   [1 0 0 0 -1 (- h) (- h) (- h)]
   [0 1 0 0 -1 h h (- h)]
   [0 0 0 0 -1 h (- h) (- h)]
   ;; +X
   [0 0 1 0 0 h (- h) (- h)]
   [1 0 1 0 0 h (- h) h]
   [1 1 1 0 0 h h h]
   [0 0 1 0 0 h (- h) (- h)]
   [1 1 1 0 0 h h h]
   [0 1 1 0 0 h h (- h)]
   ;; -X
   [0 0 -1 0 0 (- h) (- h) h]
   [1 0 -1 0 0 (- h) (- h) (- h)]
   [1 1 -1 0 0 (- h) h (- h)]
   [0 0 -1 0 0 (- h) (- h) h]
   [1 1 -1 0 0 (- h) h (- h)]
   [0 1 -1 0 0 (- h) h h]
   ;; +Y
   [0 0 0 1 0 (- h) h h]
   [1 0 0 1 0 h h h]
   [1 1 0 1 0 h h (- h)]
   [0 0 0 1 0 (- h) h h]
   [1 1 0 1 0 h h (- h)]
   [0 1 0 1 0 (- h) h (- h)]
   ;; -Y
   [0 0 0 -1 0 (- h) (- h) (- h)]
   [1 0 0 -1 0 h (- h) (- h)]
   [1 1 0 -1 0 h (- h) h]
   [0 0 0 -1 0 (- h) (- h) (- h)]
   [1 1 0 -1 0 h (- h) h]
   [0 1 0 -1 0 (- h) (- h) h]])

(fn build-mesh [ctx opts]
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 10 10 10)))
  (local vertices (or options.vertices []))
  (local vector (VectorBuffer))
  (local handle (vector:allocate (* (length vertices) 8)))
  (for [i 1 (length vertices)]
    (local offset (* (- i 1) 8))
    (write-vertex vector handle offset (. vertices i)))

  (local texture (or options.texture (make-test-texture)))
  (local batch {:vector vector :texture texture :visible? true :model nil})
  (ctx:register-mesh-batch batch)

  (fn measurer [self]
    (set self.measure size))

  (fn layouter [self]
    (set self.size self.measure)
    (local rotation (or options.rotation (glm.quat 1 0 0 0)))
    (local translate (glm.translate (glm.mat4 1) self.position))
    (local (angle axis)
           (if (= (type rotation) :userdata)
               (values (* 2 (math.acos (math.max -1 (math.min 1 rotation.w))))
                       (do
                         (local s (math.sqrt (math.max 0 (- 1 (* rotation.w rotation.w)))))
                         (if (< s 1e-6)
                             (glm.vec3 1 0 0)
                             (glm.vec3 (/ rotation.x s)
                                       (/ rotation.y s)
                                       (/ rotation.z s)))))
               (values 0 (glm.vec3 1 0 0))))
    (local rot (glm.rotate (glm.mat4 1) angle axis))
    (local model (* translate rot))
    (set batch.model model))

  (local layout (Layout {:name (or options.name "lighting-mesh")
                         :measurer measurer
                         :layouter layouter}))
  (layout:set-position (or options.position (glm.vec3 0 0 -14)))

  {:layout layout
   :drop (fn [_self]
           (ctx:unregister-mesh-batch batch)
           (vector:delete handle))})

(fn build-cube [ctx opts]
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 10 10 10)))
  (local half (/ size.x 2))
  (build-mesh ctx {:name (or options.name "lighting-cube")
                   :vertices (cube-vertices half)
                   :texture options.texture
                   :rotation options.rotation
                   :position options.position}))

(fn build-floor [ctx opts]
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 60 0 60)))
  (local vertices (plane-vertices (/ size.x 2) (/ size.z 2) 0))
  (build-mesh ctx {:name (or options.name "lighting-floor")
                   :vertices vertices
                   :texture options.texture
                   :rotation options.rotation
                   :position options.position}))

(fn build-wall [ctx opts]
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 60 0 40)))
  (local vertices (plane-vertices (/ size.x 2) (/ size.z 2) 0))
  (build-mesh ctx {:name (or options.name "lighting-wall")
                   :vertices vertices
                   :texture options.texture
                   :rotation (or options.rotation
                                 (glm.quat (math.rad 90) (glm.vec3 1 0 0)))
                   :position options.position}))

(fn build-ramp [ctx opts]
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 30 0 20)))
  (local vertices (plane-vertices (/ size.x 2) (/ size.z 2) 0))
  (build-mesh ctx {:name (or options.name "lighting-ramp")
                   :vertices vertices
                   :texture options.texture
                   :rotation (or options.rotation
                                 (glm.quat (math.rad -18) (glm.vec3 1 0 0)))
                   :position options.position}))

(fn build-scene-element [child-ctx options]
  (local texture options.texture)
  (local floor (build-floor child-ctx {:texture texture
                                       :position (glm.vec3 0 -10 -22)
                                       :size (glm.vec3 90 0 90)}))
  (local wall (build-wall child-ctx {:texture texture
                                     :position (glm.vec3 0 6 -52)
                                     :size (glm.vec3 90 0 50)}))
  (local ramp (build-ramp child-ctx {:texture texture
                                     :position (glm.vec3 -16 -8 -6)
                                     :size (glm.vec3 38 0 26)}))
  (local cube-a (build-cube child-ctx {:texture texture
                                       :rotation options.rotation
                                       :position (glm.vec3 -12 -1 -20)
                                       :size (glm.vec3 12 12 12)}))
  (local cube-b (build-cube child-ctx {:texture texture
                                       :rotation (glm.quat (math.rad 28) (glm.vec3 0 1 0))
                                       :position (glm.vec3 6 -5 -28)
                                       :size (glm.vec3 10 10 10)}))
  (local cube-c (build-cube child-ctx {:texture texture
                                       :rotation (glm.quat (math.rad -14) (glm.vec3 0 1 0))
                                       :position (glm.vec3 18 -6 -10)
                                       :size (glm.vec3 8 8 8)}))
  (local cube-d (build-cube child-ctx {:texture texture
                                       :rotation (glm.quat (math.rad 12) (glm.vec3 0 1 0))
                                       :position (glm.vec3 -2 4 -34)
                                       :size (glm.vec3 7 16 7)}))
  (local children [floor.layout wall.layout ramp.layout
                   cube-a.layout cube-b.layout cube-c.layout cube-d.layout])
  (local layout
    (Layout {:name "lighting-scene"
             :children children
             :measurer (fn [self]
                         (set self.measure (glm.vec3 1 1 1)))
             :layouter (fn [self]
                         (set self.size self.measure)
                         (set floor.layout.depth-offset-index self.depth-offset-index)
                         (floor.layout:layouter)
                         (set wall.layout.depth-offset-index self.depth-offset-index)
                         (wall.layout:layouter)
                         (set ramp.layout.depth-offset-index self.depth-offset-index)
                         (ramp.layout:layouter)
                         (set cube-a.layout.depth-offset-index self.depth-offset-index)
                         (cube-a.layout:layouter)
                         (set cube-b.layout.depth-offset-index self.depth-offset-index)
                         (cube-b.layout:layouter)
                         (set cube-c.layout.depth-offset-index self.depth-offset-index)
                         (cube-c.layout:layouter)
                         (set cube-d.layout.depth-offset-index self.depth-offset-index)
                         (cube-d.layout:layouter))}))
  (layout:set-position (or options.scene-offset (glm.vec3 0 0 0)))
  {:layout layout
   :drop (fn [_self]
           (when floor.drop (floor:drop))
           (when wall.drop (wall:drop))
           (when ramp.drop (ramp:drop))
           (when cube-a.drop (cube-a:drop))
           (when cube-b.drop (cube-b:drop))
           (when cube-c.drop (cube-c:drop))
           (when cube-d.drop (cube-d:drop)))})

(fn render-light-setup [ctx name lights opts]
  (local options (or opts {}))
  (set app.lights lights)
  (local camera (Camera {:position (glm.vec3 0 14 34)}))
  (local base-center (glm.vec3 0 -6 -26))
  (local center (+ base-center (or options.scene-offset (glm.vec3 0 0 0))))
  (camera:look-at center)
  (local dir-lights (lights:get-directional))
  (when (> (length dir-lights) 0)
    (local dir (glm.normalize (. (. dir-lights 1) :direction)))
    (tset (. dir-lights 1) :direction dir))
  (local target
    (Harness.make-scene-target {:builder (fn [child-ctx]
                                           (build-scene-element
                                             child-ctx
                                             {:texture options.texture
                                              :rotation options.rotation
                                              :scene-offset options.scene-offset}))
                                :view-matrix (camera:get-view-matrix)}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name name
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target)
  (camera:drop))

(fn run [ctx]
  (local ambient-only
    (LightSystem {:active {:ambient (glm.vec3 0.55 0.55 0.55)
                           :directional []
                           :point []
                           :spot []}}))
  (local directional-only
    (LightSystem {:active {:ambient (glm.vec3 0.03 0.03 0.03)
                           :directional [{:direction (glm.normalize (glm.vec3 0.5 1.0 0.2))
                                          :ambient (glm.vec3 0.02 0.02 0.02)
                                          :diffuse (glm.vec3 1.2 1.1 1.0)
                                          :specular (glm.vec3 0.9 0.9 1.0)}
                                         {:direction (glm.normalize (glm.vec3 -0.7 0.6 -0.1))
                                          :ambient (glm.vec3 0.01 0.01 0.015)
                                          :diffuse (glm.vec3 0.45 0.6 0.85)
                                          :specular (glm.vec3 0.45 0.55 0.7)}]
                           :point []
                           :spot []}}))
  (local point-only
    (LightSystem {:active {:ambient (glm.vec3 0.02 0.02 0.02)
                           :directional []
                           :point [{:position (glm.vec3 -8 4 -10)
                                    :ambient (glm.vec3 0.0 0.0 0.0)
                                    :diffuse (glm.vec3 2.6 2.0 1.6)
                                    :specular (glm.vec3 2.2 1.9 1.8)
                                    :constant 1.0
                                    :linear 0.03
                                    :quadratic 0.003}
                                   {:position (glm.vec3 16 12 -36)
                                    :ambient (glm.vec3 0.0 0.0 0.0)
                                    :diffuse (glm.vec3 0.7 1.2 2.4)
                                    :specular (glm.vec3 0.9 1.4 2.0)
                                    :constant 1.0
                                    :linear 0.02
                                    :quadratic 0.002}]
                           :spot []}}))
  (local spot-only
    (LightSystem {:active {:ambient (glm.vec3 0.02 0.02 0.02)
                           :directional []
                           :point []
                           :spot [{:position (glm.vec3 -10 12 -4)
                                   :direction (glm.normalize (glm.vec3 0.2 -1.0 -0.4))
                                   :ambient (glm.vec3 0.0 0.0 0.0)
                                   :diffuse (glm.vec3 2.8 2.2 1.6)
                                   :specular (glm.vec3 2.4 2.1 1.9)
                                   :cutoff (math.cos (math.rad 12.0))
                                   :outer-cutoff (math.cos (math.rad 22.0))
                                   :constant 1.0
                                   :linear 0.03
                                   :quadratic 0.002}
                                  {:position (glm.vec3 14 10 -30)
                                   :direction (glm.normalize (glm.vec3 -0.4 -1.0 0.2))
                                   :ambient (glm.vec3 0.0 0.0 0.0)
                                   :diffuse (glm.vec3 0.7 1.4 2.6)
                                   :specular (glm.vec3 0.9 1.6 2.4)
                                   :cutoff (math.cos (math.rad 14.0))
                                   :outer-cutoff (math.cos (math.rad 26.0))
                                   :constant 1.0
                                   :linear 0.025
                                   :quadratic 0.002}]}}))

  (local texture (make-test-texture))
  (render-light-setup ctx "lighting-ambient" ambient-only
                      {:texture texture
                       :rotation (glm.quat (math.rad -12) (glm.vec3 1 0 0))})
  (render-light-setup ctx "lighting-directional" directional-only
                      {:texture texture
                       :scene-offset (glm.vec3 0 -10 -6)
                       :rotation (glm.quat (math.rad -18) (glm.vec3 1 0 0))})
  (render-light-setup ctx "lighting-point" point-only
                      {:texture texture
                       :rotation (glm.quat (math.rad -16) (glm.vec3 1 0 0))})
  (render-light-setup ctx "lighting-spot" spot-only
                      {:texture texture
                       :rotation (glm.quat (math.rad -16) (glm.vec3 1 0 0))}))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E lighting snapshots complete"))

{:run run
 :main main}
