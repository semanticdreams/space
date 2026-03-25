(local glm (require :glm))
(local SoccerBallVisual (require :soccer-ball-visual))
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

(fn sync-moved-body [body]
  (when (and body (physics-available?) app.engine.physics.syncMovedRigidBody)
    (app.engine.physics:syncMovedRigidBody body)))

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

(fn ray-sphere-intersection [ray center radius]
  (if (and ray center radius)
      (do
        (local oc (- ray.origin center))
        (local a (glm.dot ray.direction ray.direction))
        (local b (* 2 (glm.dot oc ray.direction)))
        (local c (- (glm.dot oc oc) (* radius radius)))
        (local discriminant (- (* b b) (* 4 a c)))
        (if (>= discriminant 0)
            (do
              (local root (math.sqrt discriminant))
              (local denom (* 2 a))
              (local t0 (/ (- (- b) root) denom))
              (local t1 (/ (+ (- b) root) denom))
              (local distance
                (if (>= t0 0)
                    t0
                    (if (>= t1 0)
                        t1
                        nil)))
              (if distance
                  (let [point (+ ray.origin (* ray.direction (glm.vec3 distance)))]
                    (values true point distance))
                  (values false nil nil)))
            (values false nil nil)))
      (values false nil nil)))

(local approx (. MathUtils :approx))

(fn vec3-equal? [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn quat-equal? [a b]
  (if (and a b)
      (do
        (local dot (+ (* a.w b.w)
                      (* a.x b.x)
                      (* a.y b.y)
                      (* a.z b.z)))
        (approx (math.abs dot) 1.0))
      false))

(fn glm-quat->bt-quat [value]
  (local rotation (or value (glm.quat 1 0 0 0)))
  (bt.Quaternion (or rotation.x 0)
                 (or rotation.y 0)
                 (or rotation.z 0)
                 (or rotation.w 1)))

(local Ball {})

(fn create-ball [opts]
  (local options (or opts {}))
  (local radius (or options.radius 9))
  (local default-size (glm.vec3 (* 2 radius) (* 2 radius) (* 2 radius)))
  (local size (resolve-glm-vec3 options.size default-size))
  (local half-size (glm.vec3 (* 0.5 size.x) (* 0.5 size.y) (* 0.5 size.z)))
  (local offset (resolve-glm-vec3 options.position (glm.vec3 24 52 18)))
  (local initial-velocity (resolve-glm-vec3 options.initial-velocity nil))
  (local sphere-shape? (and bt bt.SphereShape))
  (local visual-builder
    (or options.visual
        (SoccerBallVisual {:size size
                           :hexagon-color options.hexagon-color
                           :pentagon-color options.pentagon-color})))

  (local build
    (fn [ctx]
      (local sphere
        (visual-builder
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
                   :dragging false
                   :is-physics-ball true})

      (fn center-from-layout [self]
        (local layout self.layout)
        (local position (or (and layout layout.position) (glm.vec3 0 0 0)))
        (local rotation (or (and layout layout.rotation) (glm.quat 1 0 0 0)))
        (+ position
           (rotation:rotate (+ self.offset self.half-size))))

      (fn set-layout-transform-from-body [self center rotation]
        (local layout self.layout)
        (when layout
          (local next-rotation (or rotation layout.rotation (glm.quat 1 0 0 0)))
          (local layout-position
            (- center (next-rotation:rotate (+ self.offset self.half-size))))
          (when (or (not (vec3-equal? layout.position layout-position))
                    (not (quat-equal? layout.rotation next-rotation)))
            (set layout.position layout-position)
            (set layout.rotation next-rotation)
            (layout:mark-layout-dirty))))

      (fn apply-layout-to-body [self]
        (when (and self.body self.body-active? (physics-available?))
          (local layout (or self.layout {}))
          (local transform (bt.Transform))
          (transform:setIdentity)
          (transform:setOrigin (bt-glm-vec3 (self:center-from-layout)))
          (transform:setRotation (glm-quat->bt-quat layout.rotation))
          (self.body:setWorldTransform transform)
          (when self.motion-state
            (self.motion-state:setWorldTransform transform))
          (self.body:setLinearVelocity (bt.Vector3 0 0 0))
          (when self.body.setAngularVelocity
            (self.body:setAngularVelocity (bt.Vector3 0 0 0)))))

      (fn ensure-body [self]
        (when (and (physics-available?) (not self.body))
          (local center (self:center-from-layout))
          (local shape
            (if sphere-shape?
                (bt.SphereShape self.radius)
                (bt.BoxShape (bt-glm-vec3 self.half-size))))
          (local transform (bt.Transform))
          (transform:setIdentity)
          (transform:setOrigin (bt-glm-vec3 center))
          (transform:setRotation (glm-quat->bt-quat (and self.layout self.layout.rotation)))
          (local motion (bt.DefaultMotionState transform))
          (local inertia (bt.Vector3 0 0 0))
          (shape:calculateLocalInertia self.mass inertia)
          (local info (bt.RigidBodyConstructionInfo self.mass motion shape inertia))
          (local body (bt.RigidBody info))
          (when (and body body.setFriction)
            (body:setFriction self.friction))
          (when (and body body.setRestitution)
            (body:setRestitution self.restitution))
          (if self.initial-velocity
              (body:setLinearVelocity (bt-glm-vec3 self.initial-velocity))
              (body:setLinearVelocity (bt.Vector3 0 -0.01 0)))
          (when body.forceActivationState
            (body:forceActivationState 1))
          (when body.activate
            (body:activate true))
          (app.engine.physics:addRigidBody body)
          (set self.shape shape)
          (set self.motion-state motion)
          (set self.body body)
          (set self.body-active? true)))

      (fn sync [self]
        (when (and self.body self.body-active? (physics-available?))
          (if self.dragging
              (self:apply-layout-to-body)
              (do
                (local transform (self.body:getCenterOfMassTransform))
                (local origin (transform:getOrigin))
                (local rotation (bt-quat->glm-quat (transform:getRotation)))
                (local center (glm.vec3 origin.x origin.y origin.z))
                (self:set-layout-transform-from-body center rotation)))))

      (fn begin-drag [self]
        (set self.dragging true)
        (self:ensure-body))

      (fn end-drag [self]
        (set self.dragging false)
        (when (and self.body self.body-active? (physics-available?))
          (self:apply-layout-to-body)
          (sync-moved-body self.body)
          (when self.body.forceActivationState
            (self.body:forceActivationState 1))
          (when self.body.activate
            (self.body:activate true))
          (self.body:applyForce (bt.Vector3 0 -0.5 0))))

      (fn drop [self]
        (when (and self.body self.body-active? (physics-available?))
          (app.engine.physics:removeRigidBody self.body))
        (set self.body-active? false)
        (set self.body nil)
        (set self.motion-state nil)
        (set self.shape nil)
        (when self.positioned
          (self.positioned:drop)))

      (fn intersect [self ray]
        (ray-sphere-intersection ray (self:center-from-layout) self.radius))

      (set self.ensure-body ensure-body)
      (set self.sync sync)
      (set self.begin-drag begin-drag)
      (set self.end-drag end-drag)
      (set self.apply-layout-to-body apply-layout-to-body)
      (set self.intersect intersect)
      (set self.set-layout-transform-from-body set-layout-transform-from-body)
      (set self.center-from-layout center-from-layout)
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
