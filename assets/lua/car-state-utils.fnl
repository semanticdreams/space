(local glm (require :glm))
(local bt (require :bt))

(fn physics-available? []
  (and bt app.engine app.engine.physics app.engine.physics.getWorld))

(fn vec3-zero []
  (glm.vec3 0 0 0))

(fn quat-identity []
  (glm.quat 1 0 0 0))

(fn copy-glm-vec3! [target source]
  (when (and target source)
    (set target.x source.x)
    (set target.y source.y)
    (set target.z source.z)))

(fn copy-glm-quat! [target source]
  (when (and target source)
    (set target.w source.w)
    (set target.x source.x)
    (set target.y source.y)
    (set target.z source.z)))

(fn bt-glm-vec3 [value]
  (bt.Vector3 (or value.x 0) (or value.y 0) (or value.z 0)))

(fn bt-glm-quat [value]
  (bt.Quaternion (or value.x 0) (or value.y 0) (or value.z 0) (or value.w 1)))

(fn quat-from-bt [rotation]
  (local w (and rotation (rotation:w)))
  (local x (and rotation (rotation:x)))
  (local y (and rotation (rotation:y)))
  (local z (and rotation (rotation:z)))
  (glm.quat (or w 1) (or x 0) (or y 0) (or z 0)))

(fn parent-transform [layout]
  {:position (or (and layout layout.position) (vec3-zero))
   :rotation (or (and layout layout.rotation) (quat-identity))})

(fn car-world-transform [parent offset local-rotation half-size]
  (local parent-rot parent.rotation)
  (local rotation (* parent-rot local-rotation))
  (local base (+ parent.position (parent-rot:rotate offset)))
  (local center (+ base (rotation:rotate half-size)))
  {:center center :rotation rotation})

(fn offset-from-physics [parent center local-rotation half-size]
  (local inverse (parent.rotation:inverse))
  (local local-center (inverse:rotate (- center parent.position)))
  (- local-center (local-rotation:rotate half-size)))

(fn wheel-lateral-offset [half-size wheel-width]
  (math.max 0.1 (- half-size.z (* 0.5 wheel-width))))

(fn find-car []
  (local scene (and app.engine app.scene))
  (local entity (and scene scene.entity))
  (if (and entity entity.__demo_car)
      entity
      (if (and entity entity.children)
          (let [matches
                (icollect [_ child (ipairs entity.children)]
                  (and child child.element child.element.__demo_car child.element))]
            (and (> (# matches) 0) (. matches 1)))
          nil)))

{:physics-available? physics-available?
 :vec3-zero vec3-zero
 :quat-identity quat-identity
 :copy-glm-vec3! copy-glm-vec3!
 :copy-glm-quat! copy-glm-quat!
 :bt-glm-vec3 bt-glm-vec3
 :bt-glm-quat bt-glm-quat
 :quat-from-bt quat-from-bt
 :parent-transform parent-transform
 :car-world-transform car-world-transform
 :offset-from-physics offset-from-physics
 :wheel-lateral-offset wheel-lateral-offset
 :find-car find-car}
