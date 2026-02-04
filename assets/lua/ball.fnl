(local glm (require :glm))
(local Sphere (require :sphere))
(local Positioned (require :positioned))

(local bt (require :bt))
(local MathUtils (require :math-utils))
(fn resolve-glm-vec3 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (do
        (local x (or (. value 1) value.x (. value "x") (and fallback fallback.x) 0))
        (local y (or (. value 2) value.y (. value "y") (and fallback fallback.y) 0))
        (local z (or (. value 3) value.z (. value "z") (and fallback fallback.z) 0))
        (glm.vec3 x y z))
    fallback))

(fn physics-available? []
  (and bt app.engine app.engine.physics))

(fn ensure-gravity []
  (when (physics-available?)
    (app.engine.physics:setGravity 0 -25 0)))

(fn bt-glm-vec3 [value]
  (bt.Vector3 (or value.x 0) (or value.y 0) (or value.z 0)))

(fn bt-quat->glm-quat [rotation]
  (local w (and rotation (rotation:w)))
  (local x (and rotation (rotation:x)))
  (local y (and rotation (rotation:y)))
  (local z (and rotation (rotation:z)))
  (if (and w x y z)
      (glm.quat w x y z)
      (glm.quat 1 0 0 0)))

(local approx (. MathUtils :approx))

(fn vec3-equal? [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(local Ball {})

(fn create-ball [opts]
  (local options (or opts {}))
  (local radius (or options.radius 9))
  (local default-size (glm.vec3 (* 2 radius) (* 2 radius) (* 2 radius)))
  (local size (resolve-glm-vec3 options.size default-size))
  (local half-size (glm.vec3 (* 0.5 size.x) (* 0.5 size.y) (* 0.5 size.z)))
  (local offset (resolve-glm-vec3 options.position (glm.vec3 24 52 18)))
  (local color (or options.color (glm.vec4 0.55 0.8 1.0 0.9)))
  (local initial-velocity (resolve-glm-vec3 options.initial-velocity nil))
  (local sphere-shape? (and bt bt.SphereShape))

  (local build
    (fn [ctx]
      (local sphere
        ((Sphere {:color color
                  :size size
                  :segments options.segments
                  :rings options.rings})
         ctx))
      (local positioned
        ((Positioned {:position offset
                      :size size
                      :child (fn [_] sphere)})
         ctx))

      (local self {:sphere sphere
                   :positioned positioned
                   :layout positioned.layout
                   :offset offset
                   :half-size half-size
                   :radius radius
                   :mass (or options.mass 1.5)
                   :friction (or options.friction 0.6)
                   :restitution (or options.restitution 0.35)
                   :initial-velocity initial-velocity
                   :body nil
                   :motion-state nil
                   :shape nil
                   :body-active? false
                   :is-physics-ball true})

      (fn parent-transform [_self parent-layout]
        {:position (or (and parent-layout parent-layout.position) (glm.vec3 0 0 0))
         :rotation (or (and parent-layout parent-layout.rotation) (glm.quat 1 0 0 0))})

      (fn center-from-parent [self parent-layout]
        (local transform (parent-transform self parent-layout))
        (+ transform.position
           (transform.rotation:rotate (+ self.offset self.half-size))))

      (fn set-offset-from-center [self center parent-layout]
        (local transform (parent-transform self parent-layout))
        (local inverse (transform.rotation:inverse))
        (local relative (- center transform.position))
        (local local-center (inverse:rotate relative))
        (local local-offset (- local-center self.half-size))
        (when (not (vec3-equal? self.offset local-offset))
          (set self.offset.x local-offset.x)
          (set self.offset.y local-offset.y)
          (set self.offset.z local-offset.z)
          (self.positioned.layout:mark-layout-dirty)))

      (fn ensure-body [self parent-layout]
        (when (and (physics-available?) (not self.body))
          (ensure-gravity)
          (local center (self:center-from-parent parent-layout))
          (local shape
            (if sphere-shape?
                (bt.SphereShape self.radius)
                (bt.BoxShape (bt-glm-vec3 self.half-size))))
          (local transform (bt.Transform))
          (transform:setIdentity)
          (transform:setOrigin (bt-glm-vec3 center))
          (local motion (bt.DefaultMotionState transform))
          (local inertia (bt.Vector3 0 0 0))
          (shape:calculateLocalInertia self.mass inertia)
          (local info (bt.RigidBodyConstructionInfo self.mass motion shape inertia))
          (local body (bt.RigidBody info))
          (when (and body body.setFriction)
            (body:setFriction self.friction))
          (when (and body body.setRestitution)
            (body:setRestitution self.restitution))
          (when self.initial-velocity
            (body:setLinearVelocity (bt-glm-vec3 self.initial-velocity)))
          (app.engine.physics:addRigidBody body)
          (set self.shape shape)
          (set self.motion-state motion)
          (set self.body body)
          (set self.body-active? true)))

      (fn sync [self parent-layout]
        (when (and self.body self.body-active? (physics-available?))
          (local transform (self.body:getCenterOfMassTransform))
          (local origin (transform:getOrigin))
          (local center (glm.vec3 origin.x origin.y origin.z))
          (self:set-offset-from-center center parent-layout)))

      (fn drop [self]
        (when (and self.body self.body-active? (physics-available?))
          (app.engine.physics:removeRigidBody self.body))
        (set self.body-active? false)
        (set self.body nil)
        (set self.motion-state nil)
        (set self.shape nil)
        (when self.positioned
          (self.positioned:drop)))

      (set self.ensure-body ensure-body)
      (set self.sync sync)
      (set self.set-offset-from-center set-offset-from-center)
      (set self.center-from-parent center-from-parent)
      (set self.drop drop)
      self))
  build)

(fn Ball.attach-all [entity]
  (when (and entity entity.balls)
    (each [_ ball (ipairs entity.balls)]
      (when (and ball.ensure-body entity.layout)
        (ball:ensure-body entity.layout)))))

(fn Ball.sync-all [entity]
  (when (and entity entity.balls)
    (each [_ ball (ipairs entity.balls)]
      (when (and ball.sync entity.layout)
        (ball:sync entity.layout)))))

(set Ball.create create-ball)
(setmetatable Ball {:__call (fn [_ opts] (create-ball opts))})

Ball
