(local glm (require :glm))
(local SoccerBallVisual (require :soccer-ball-visual))
(local Positioned (require :positioned))

(local bt (require :bt))
(local MathUtils (require :math-utils))
(local vec3->array (. MathUtils :vec3->array))

(fn vec4->array [value]
  (if value
      [value.x value.y value.z value.w]
      nil))

(fn array->vec3 [arr]
  (and arr (glm.vec3 (. arr 1) (. arr 2) (. arr 3))))

(fn array->vec4 [arr]
  (and arr (glm.vec4 (. arr 1) (. arr 2) (. arr 3) (. arr 4))))

(fn array->quat [arr]
  (and arr (glm.quat (. arr 1) (. arr 2) (. arr 3) (. arr 4))))
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

(fn resolve-bt-vec3 [value fallback]
  (local resolved (resolve-glm-vec3 value fallback))
  (if resolved
      (bt-glm-vec3 resolved)
      nil))

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

(fn serialize-angular-factor [value]
  (if (= (type value) :number)
      value
      (and value (vec3->array value))))

(fn deserialize-angular-factor [value]
  (if (= (type value) :number)
      value
      (resolve-glm-vec3 value nil)))

(fn apply-body-construction-options [info self]
  (when self.linear-damping
    (set info.m-linearDamping self.linear-damping))
  (when self.angular-damping
    (set info.m-angularDamping self.angular-damping))
  (when self.friction
    (set info.m-friction self.friction))
  (when self.rolling-friction
    (set info.m-rollingFriction self.rolling-friction))
  (when self.spinning-friction
    (set info.m-spinningFriction self.spinning-friction))
  (when self.restitution
    (set info.m-restitution self.restitution))
  (when self.linear-sleeping-threshold
    (set info.m-linearSleepingThreshold self.linear-sleeping-threshold))
  (when self.angular-sleeping-threshold
    (set info.m-angularSleepingThreshold self.angular-sleeping-threshold))
  (when (not (= self.additional-damping nil))
    (set info.m-additionalDamping self.additional-damping))
  (when self.additional-damping-factor
    (set info.m-additionalDampingFactor self.additional-damping-factor))
  (when self.additional-linear-damping-threshold-sqr
    (set info.m-additionalLinearDampingThresholdSqr self.additional-linear-damping-threshold-sqr))
  (when self.additional-angular-damping-threshold-sqr
    (set info.m-additionalAngularDampingThresholdSqr self.additional-angular-damping-threshold-sqr))
  (when self.additional-angular-damping-factor
    (set info.m-additionalAngularDampingFactor self.additional-angular-damping-factor)))

(fn apply-body-runtime-options [body self]
  (when self.gravity
    (body:setGravity self.gravity))
  (when self.linear-factor
    (body:setLinearFactor self.linear-factor))
  (when self.angular-factor
    (if (= (type self.angular-factor) :number)
        (body:setAngularFactor self.angular-factor)
        (body:setAngularFactor self.angular-factor)))
  (when self.anisotropic-friction
    (if self.anisotropic-friction-mode
        (body:setAnisotropicFriction self.anisotropic-friction self.anisotropic-friction-mode)
        (body:setAnisotropicFriction self.anisotropic-friction)))
  (when self.contact-processing-threshold
    (body:setContactProcessingThreshold self.contact-processing-threshold))
  (when (and self.contact-stiffness self.contact-damping)
    (body:setContactStiffnessAndDamping self.contact-stiffness self.contact-damping))
  (when self.ccd-motion-threshold
    (body:setCcdMotionThreshold self.ccd-motion-threshold))
  (when self.ccd-swept-sphere-radius
    (body:setCcdSweptSphereRadius self.ccd-swept-sphere-radius))
  (when self.collision-flags
    (body:setCollisionFlags self.collision-flags))
  (when self.body-flags
    (body:setFlags self.body-flags))
  (if self.initial-velocity
      (body:setLinearVelocity self.initial-velocity)
      (body:setLinearVelocity (bt.Vector3 0 -0.01 0)))
  (when self.initial-angular-velocity
    (body:setAngularVelocity self.initial-angular-velocity))
  (when body.forceActivationState
    (body:forceActivationState self.activation-state))
  (when body.activate
    (body:activate true))
  (when self.deactivation-time
    (body:setDeactivationTime self.deactivation-time)))

(local Ball {})

(fn create-ball [opts]
  (local options (or opts {}))
  (local radius (or options.radius 18))
  (local default-size (glm.vec3 (* 2 radius) (* 2 radius) (* 2 radius)))
  (local size (resolve-glm-vec3 options.size default-size))
  (local half-size (glm.vec3 (* 0.5 size.x) (* 0.5 size.y) (* 0.5 size.z)))
  (local offset (resolve-glm-vec3 options.position (glm.vec3 0 0 0)))
  (local initial-velocity (resolve-bt-vec3 options.initial-velocity nil))
  (local initial-angular-velocity (resolve-bt-vec3 options.initial-angular-velocity nil))
  (local gravity (resolve-bt-vec3 options.gravity nil))
  (local linear-factor (resolve-bt-vec3 options.linear-factor nil))
  (local angular-factor
    (if (= (type options.angular-factor) :number)
        options.angular-factor
        (resolve-bt-vec3 options.angular-factor nil)))
  (local anisotropic-friction (resolve-bt-vec3 options.anisotropic-friction nil))
  (local sphere-shape? (and bt bt.SphereShape))
  (local default-activation-state (or (and bt bt.ACTIVE_TAG) 1))
  (local visual-builder
    (or options.visual
        (SoccerBallVisual {:size size
                           :hexagon-color options.hexagon-color
                           :pentagon-color options.pentagon-color})))

  (local persistence-options
    {:radius radius
     :size size
     :mass (or options.mass 1.5)
     :friction (or options.friction 0.6)
     :rolling-friction options.rolling-friction
     :spinning-friction options.spinning-friction
     :restitution (or options.restitution 0.5)
     :linear-damping options.linear-damping
     :angular-damping options.angular-damping
     :linear-sleeping-threshold options.linear-sleeping-threshold
     :angular-sleeping-threshold options.angular-sleeping-threshold
     :additional-damping options.additional-damping
     :additional-damping-factor options.additional-damping-factor
     :additional-linear-damping-threshold-sqr options.additional-linear-damping-threshold-sqr
     :additional-angular-damping-threshold-sqr options.additional-angular-damping-threshold-sqr
     :additional-angular-damping-factor options.additional-angular-damping-factor
     :initial-velocity options.initial-velocity
     :initial-angular-velocity options.initial-angular-velocity
     :gravity options.gravity
     :linear-factor options.linear-factor
     :angular-factor options.angular-factor
     :anisotropic-friction options.anisotropic-friction
     :anisotropic-friction-mode options.anisotropic-friction-mode
     :contact-processing-threshold options.contact-processing-threshold
     :contact-stiffness options.contact-stiffness
     :contact-damping options.contact-damping
     :ccd-motion-threshold options.ccd-motion-threshold
     :ccd-swept-sphere-radius options.ccd-swept-sphere-radius
     :collision-flags options.collision-flags
     :body-flags options.body-flags
     :deactivation-time options.deactivation-time
     :activation-state (or options.activation-state default-activation-state)
     :hexagon-color options.hexagon-color
     :pentagon-color options.pentagon-color})

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
                   :rolling-friction options.rolling-friction
                   :spinning-friction options.spinning-friction
                   :restitution (or options.restitution 0.5)
                   :linear-damping options.linear-damping
                   :angular-damping options.angular-damping
                   :linear-sleeping-threshold options.linear-sleeping-threshold
                   :angular-sleeping-threshold options.angular-sleeping-threshold
                   :additional-damping options.additional-damping
                   :additional-damping-factor options.additional-damping-factor
                   :additional-linear-damping-threshold-sqr options.additional-linear-damping-threshold-sqr
                   :additional-angular-damping-threshold-sqr options.additional-angular-damping-threshold-sqr
                   :additional-angular-damping-factor options.additional-angular-damping-factor
                   :initial-velocity initial-velocity
                   :initial-angular-velocity initial-angular-velocity
                   :gravity gravity
                   :linear-factor linear-factor
                   :angular-factor angular-factor
                   :anisotropic-friction anisotropic-friction
                   :anisotropic-friction-mode options.anisotropic-friction-mode
                   :contact-processing-threshold options.contact-processing-threshold
                   :contact-stiffness options.contact-stiffness
                   :contact-damping options.contact-damping
                   :ccd-motion-threshold options.ccd-motion-threshold
                   :ccd-swept-sphere-radius options.ccd-swept-sphere-radius
                   :collision-flags options.collision-flags
                   :body-flags options.body-flags
                   :deactivation-time options.deactivation-time
                   :activation-state (or options.activation-state default-activation-state)
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
          (apply-body-construction-options info self)
          (local body (bt.RigidBody info))
          (apply-body-runtime-options body self)
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
            (self.body:forceActivationState self.activation-state))
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
  (local object
    {:scene-object-options
     (fn [_self]
       {:skip-cuboid true
        :skip-physics true
        :persistence {:kind "physics-ball"
                      :restorer-module "ball"
                      :radius persistence-options.radius
                      :size (vec3->array persistence-options.size)
                      :mass persistence-options.mass
                      :friction persistence-options.friction
                      :rolling-friction persistence-options.rolling-friction
                      :spinning-friction persistence-options.spinning-friction
                      :restitution persistence-options.restitution
                      :linear-damping persistence-options.linear-damping
                      :angular-damping persistence-options.angular-damping
                      :linear-sleeping-threshold persistence-options.linear-sleeping-threshold
                      :angular-sleeping-threshold persistence-options.angular-sleeping-threshold
                      :additional-damping persistence-options.additional-damping
                      :additional-damping-factor persistence-options.additional-damping-factor
                      :additional-linear-damping-threshold-sqr persistence-options.additional-linear-damping-threshold-sqr
                      :additional-angular-damping-threshold-sqr persistence-options.additional-angular-damping-threshold-sqr
                      :additional-angular-damping-factor persistence-options.additional-angular-damping-factor
                      :initial-velocity (and persistence-options.initial-velocity
                                             (vec3->array persistence-options.initial-velocity))
                      :initial-angular-velocity (and persistence-options.initial-angular-velocity
                                                     (vec3->array persistence-options.initial-angular-velocity))
                      :gravity (and persistence-options.gravity
                                    (vec3->array persistence-options.gravity))
                      :linear-factor (and persistence-options.linear-factor
                                          (vec3->array persistence-options.linear-factor))
                      :angular-factor (serialize-angular-factor persistence-options.angular-factor)
                      :anisotropic-friction (and persistence-options.anisotropic-friction
                                                 (vec3->array persistence-options.anisotropic-friction))
                      :anisotropic-friction-mode persistence-options.anisotropic-friction-mode
                      :contact-processing-threshold persistence-options.contact-processing-threshold
                      :contact-stiffness persistence-options.contact-stiffness
                      :contact-damping persistence-options.contact-damping
                      :ccd-motion-threshold persistence-options.ccd-motion-threshold
                      :ccd-swept-sphere-radius persistence-options.ccd-swept-sphere-radius
                      :collision-flags persistence-options.collision-flags
                      :body-flags persistence-options.body-flags
                      :deactivation-time persistence-options.deactivation-time
                      :activation-state persistence-options.activation-state
                      :hexagon-color (vec4->array persistence-options.hexagon-color)
                      :pentagon-color (vec4->array persistence-options.pentagon-color)}})
     :scene-on-added
     (fn [_self scene element]
       (scene:register-scene-object
         {:owner element
          :element element
          :movable {:handle element
                    :key element
                    :owner element
                    :on-drag-start (fn [_entry]
                                     (element:begin-drag))
                    :on-drag-end (fn [_entry]
                                   (element:end-drag))}
          :ensure-body (fn [_entry entity]
                         (when (and element.ensure-body entity.layout)
                           (element:ensure-body entity.layout)))
          :sync (fn [_entry entity]
                  (when (and element.sync entity.layout)
                    (element:sync entity.layout)))}) )})
  (setmetatable object {:__call (fn [_self ctx] (build ctx))})
  object)

(fn Ball.restore [payload]
  (local scene payload.scene)
  (local panel payload.panel)
  (assert scene "Ball.restore requires :scene")
  (assert panel "Ball.restore requires :panel")
  (scene:add-object
    (create-ball {:radius panel.radius
                  :size (array->vec3 panel.size)
                  :mass panel.mass
                  :friction panel.friction
                  :rolling-friction panel.rolling-friction
                  :spinning-friction panel.spinning-friction
                  :restitution panel.restitution
                  :linear-damping panel.linear-damping
                  :angular-damping panel.angular-damping
                  :linear-sleeping-threshold panel.linear-sleeping-threshold
                  :angular-sleeping-threshold panel.angular-sleeping-threshold
                  :additional-damping panel.additional-damping
                  :additional-damping-factor panel.additional-damping-factor
                  :additional-linear-damping-threshold-sqr panel.additional-linear-damping-threshold-sqr
                  :additional-angular-damping-threshold-sqr panel.additional-angular-damping-threshold-sqr
                  :additional-angular-damping-factor panel.additional-angular-damping-factor
                  :initial-velocity (array->vec3 panel.initial-velocity)
                  :initial-angular-velocity (array->vec3 panel.initial-angular-velocity)
                  :gravity (array->vec3 panel.gravity)
                  :linear-factor (array->vec3 panel.linear-factor)
                  :angular-factor (deserialize-angular-factor panel.angular-factor)
                  :anisotropic-friction (array->vec3 panel.anisotropic-friction)
                  :anisotropic-friction-mode panel.anisotropic-friction-mode
                  :contact-processing-threshold panel.contact-processing-threshold
                  :contact-stiffness panel.contact-stiffness
                  :contact-damping panel.contact-damping
                  :ccd-motion-threshold panel.ccd-motion-threshold
                  :ccd-swept-sphere-radius panel.ccd-swept-sphere-radius
                  :collision-flags panel.collision-flags
                  :body-flags panel.body-flags
                  :deactivation-time panel.deactivation-time
                  :activation-state panel.activation-state
                  :hexagon-color (array->vec4 panel.hexagon-color)
                  :pentagon-color (array->vec4 panel.pentagon-color)})
    {:position (array->vec3 panel.position)
     :rotation (array->quat panel.rotation)}))

(set Ball.create create-ball)
(setmetatable Ball {:__call (fn [_ opts] (create-ball opts))})

Ball
