(local glm (require :glm))
(local Positioned (require :positioned))
(local DefaultDialog (require :default-dialog))
(local TabView (require :tab-view))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))
(local LightBallEditorValidation (require :light-ball-editor-validation))
(local SphereVisual (require :sphere-visual))

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

(fn resolve-glm-vec4 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec4 value value value value)
    (= (type value) :table)
      (do
        (local x (or (. value 1) value.x (. value "x") (and fallback fallback.x) 0))
        (local y (or (. value 2) value.y (. value "y") (and fallback fallback.y) 0))
        (local z (or (. value 3) value.z (. value "z") (and fallback fallback.z) 0))
        (local w (or (. value 4) value.w (. value "w") (and fallback fallback.w) 1))
        (glm.vec4 x y z w))
    fallback))

(fn physics-available? []
  (and bt app.engine app.engine.physics))

(fn sync-moved-body [body]
  (when (and body (physics-available?) app.engine.physics.syncMovedRigidBody)
    (app.engine.physics:syncMovedRigidBody body)))

(fn bt-glm-vec3 [value]
  (bt.Vector3 (or value.x 0) (or value.y 0) (or value.z 0)))

(fn glm-from-bt-vec3 [value]
  (if value
      (glm.vec3 (or value.x 0) (or value.y 0) (or value.z 0))
      (glm.vec3 0 0 0)))

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

(fn glm-quat->bt-quat [value]
  (local rotation (or value (glm.quat 1 0 0 0)))
  (bt.Quaternion (or rotation.x 0)
                 (or rotation.y 0)
                 (or rotation.z 0)
                 (or rotation.w 1)))

(fn resolve-menu-position [event]
  (local screen (and event event.screen))
  (if (and screen app.hud app.hud.screen-pos-ray)
      (do
        (local ray (app.hud:screen-pos-ray {:x (or screen.x 0)
                                            :y (or screen.y 0)}))
        (if (and ray ray.origin ray.direction)
            (do
              (local dz (or ray.direction.z 0))
              (local t (if (not (= dz 0))
                           (/ (- 0 ray.origin.z) dz)
                           0))
              (+ ray.origin (* ray.direction t)))
            (or (and event event.point) (glm.vec3 0 0 0))))
      (or (and event event.point) (glm.vec3 0 0 0))))

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
                  (do
                    (local point (+ ray.origin (* ray.direction (glm.vec3 distance))))
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

(fn serialize-angular-factor [value]
  (if (= (type value) :number)
      value
      (and value (vec3->array value))))

(fn deserialize-angular-factor [value]
  (if (= (type value) :number)
      value
      (resolve-glm-vec3 value nil)))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

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
    (set info.m_additionalDamping self.additional-damping))
  (when self.additional-damping-factor
    (set info.m_additionalDampingFactor self.additional-damping-factor))
  (when self.additional-linear-damping-threshold-sqr
    (set info.m_additionalLinearDampingThresholdSqr self.additional-linear-damping-threshold-sqr))
  (when self.additional-angular-damping-threshold-sqr
    (set info.m_additionalAngularDampingThresholdSqr self.additional-angular-damping-threshold-sqr))
  (when self.additional-angular-damping-factor
    (set info.m_additionalAngularDampingFactor self.additional-angular-damping-factor)))

(fn apply-body-runtime-options [body self]
  (when self.gravity
    (body:setGravity self.gravity))
  (when self.linear-factor
    (body:setLinearFactor self.linear-factor))
  (when self.angular-factor
    (body:setAngularFactor self.angular-factor))
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

(var runtime-id-seq 0)

(fn next-runtime-light-id []
  (set runtime-id-seq (+ runtime-id-seq 1))
  (.. "light-ball-runtime-" (tostring runtime-id-seq)))

(fn light-ball-can-allocate-runtime-light? []
  (assert (and app app.lights)
          "LightBall requires app.lights")
  (assert app.lights.get-point-count
          "LightBall requires app.lights.get-point-count")
  (< (app.lights:get-point-count)
     (or app.lights.max-point-lights 8)))

(local default-light-config
  {:enabled? true
   :ambient (glm.vec3 5.0 5.0 4.0)
   :diffuse (glm.vec3 100.0 70.0 0.0)
   :specular (glm.vec3 50.0 50.0 0.0)
   :specular-power 5.0
   :constant 3.0
   :linear 0.001
   :quadratic 0.00132})

(local default-physics-config
  {:mass 0.75
   :friction 0.6
   :restitution 0.82
   :linear-damping 0.08
   :angular-damping 0.16
   :gravity (glm.vec3 0 -4.5 0)
   :body-flags (and bt bt.BT_DISABLE_WORLD_GRAVITY)})

(local LightBall {})

(fn light-ball-physics-record [self]
  {:radius self.radius
   :mass self.mass
   :friction self.friction
   :rolling-friction self.rolling-friction
   :spinning-friction self.spinning-friction
   :restitution self.restitution
   :linear-damping self.linear-damping
   :angular-damping self.angular-damping
   :linear-sleeping-threshold self.linear-sleeping-threshold
   :angular-sleeping-threshold self.angular-sleeping-threshold
   :additional-damping self.additional-damping
   :additional-damping-factor self.additional-damping-factor
   :additional-linear-damping-threshold-sqr self.additional-linear-damping-threshold-sqr
   :additional-angular-damping-threshold-sqr self.additional-angular-damping-threshold-sqr
   :additional-angular-damping-factor self.additional-angular-damping-factor
   :initial-velocity (and self.initial-velocity
                          (glm.vec3 self.initial-velocity.x
                                    self.initial-velocity.y
                                    self.initial-velocity.z))
   :initial-angular-velocity (and self.initial-angular-velocity
                                  (glm.vec3 self.initial-angular-velocity.x
                                            self.initial-angular-velocity.y
                                            self.initial-angular-velocity.z))
   :gravity (and self.gravity
                 (glm.vec3 self.gravity.x self.gravity.y self.gravity.z))
   :linear-factor (and self.linear-factor
                       (glm.vec3 self.linear-factor.x
                                 self.linear-factor.y
                                 self.linear-factor.z))
   :angular-factor (if (= (type self.angular-factor) :number)
                       self.angular-factor
                       (and self.angular-factor
                            (glm.vec3 self.angular-factor.x
                                      self.angular-factor.y
                                      self.angular-factor.z)))
   :anisotropic-friction (and self.anisotropic-friction
                              (glm.vec3 self.anisotropic-friction.x
                                        self.anisotropic-friction.y
                                        self.anisotropic-friction.z))
   :anisotropic-friction-mode self.anisotropic-friction-mode
   :contact-processing-threshold self.contact-processing-threshold
   :contact-stiffness self.contact-stiffness
   :contact-damping self.contact-damping
   :ccd-motion-threshold self.ccd-motion-threshold
   :ccd-swept-sphere-radius self.ccd-swept-sphere-radius
   :collision-flags self.collision-flags
   :body-flags self.body-flags
   :deactivation-time self.deactivation-time
   :activation-state self.activation-state})

(fn capture-light-ball-persistence [self current-size]
  {:kind "light-ball"
   :restorer-module "light-ball"
   :radius self.radius
   :size (vec3->array current-size)
   :mass self.mass
   :friction self.friction
   :rolling-friction self.rolling-friction
   :spinning-friction self.spinning-friction
   :restitution self.restitution
   :linear-damping self.linear-damping
   :angular-damping self.angular-damping
   :linear-sleeping-threshold self.linear-sleeping-threshold
   :angular-sleeping-threshold self.angular-sleeping-threshold
   :additional-damping self.additional-damping
   :additional-damping-factor self.additional-damping-factor
   :additional-linear-damping-threshold-sqr self.additional-linear-damping-threshold-sqr
   :additional-angular-damping-threshold-sqr self.additional-angular-damping-threshold-sqr
   :additional-angular-damping-factor self.additional-angular-damping-factor
   :initial-velocity (and self.initial-velocity
                          (vec3->array self.initial-velocity))
   :initial-angular-velocity (and self.initial-angular-velocity
                                  (vec3->array self.initial-angular-velocity))
   :gravity (and self.gravity
                 (vec3->array self.gravity))
   :linear-factor (and self.linear-factor
                       (vec3->array self.linear-factor))
   :angular-factor (serialize-angular-factor self.angular-factor)
   :anisotropic-friction (and self.anisotropic-friction
                              (vec3->array self.anisotropic-friction))
   :anisotropic-friction-mode self.anisotropic-friction-mode
   :contact-processing-threshold self.contact-processing-threshold
   :contact-stiffness self.contact-stiffness
   :contact-damping self.contact-damping
   :ccd-motion-threshold self.ccd-motion-threshold
   :ccd-swept-sphere-radius self.ccd-swept-sphere-radius
   :collision-flags self.collision-flags
   :body-flags self.body-flags
   :deactivation-time self.deactivation-time
   :activation-state self.activation-state
   :color (vec4->array self.color)
   :enabled? self.light-config.enabled?
   :ambient (vec3->array self.light-config.ambient)
   :diffuse (vec3->array self.light-config.diffuse)
   :specular (vec3->array self.light-config.specular)
   :specular-power self.light-config.specular-power
   :constant self.light-config.constant
   :linear self.light-config.linear
   :quadratic self.light-config.quadratic})

(fn build-light-ball-dialog [self]
  (local light-target
    {:get-record (fn [_self] self.light-config)
     :apply-values (fn [_self form-values]
                     (self:apply-light-values form-values))})
  (local physics-target
    {:get-record (fn [_self]
                   (light-ball-physics-record self))
     :apply-values (fn [_self form-values]
                     (self:apply-physics-values form-values))})
  (DefaultDialog
    {:title "Light Ball"
     :name "light-ball-dialog"
     :child
     (fn [ctx]
       ((TabView
          {:items [{:label "Light"
                    :builder (fn [child-ctx]
                               ((TerrainEditorFormView
                                  light-target
                                  {:validation LightBallEditorValidation.light_validation
                                   :name "light-ball-light-form"
                                   :info-text "Edit the connected point light."
                                   :wrap-scroll? true
                                   :refresh-on-change? false})
                                child-ctx))}
                   {:label "Physics"
                    :builder (fn [child-ctx]
                               ((TerrainEditorFormView
                                  physics-target
                                  {:validation LightBallEditorValidation.physics_validation
                                   :name "light-ball-physics-form"
                                   :info-text "Edit light-ball physics and rebuild the live body on apply."
                                   :wrap-scroll? true
                                   :refresh-on-change? false})
                                child-ctx))}]})
        ctx))}))

(fn light-ball-center-from-layout [self]
  (local layout self.layout)
  (local position (or (and layout layout.position) (glm.vec3 0 0 0)))
  (local rotation (or (and layout layout.rotation) (glm.quat 1 0 0 0)))
  (+ position
     (rotation:rotate (+ self.offset self.half-size))))

(fn light-ball-set-layout-transform-from-body [self center rotation]
  (local layout self.layout)
  (when layout
    (local next-rotation (or rotation layout.rotation (glm.quat 1 0 0 0)))
    (local layout-position
      (- center (next-rotation:rotate (+ self.offset self.half-size))))
    (when (or (not (vec3-equal? layout.position layout-position))
              (not (quat-equal? layout.rotation next-rotation)))
      (set layout.position layout-position)
      (set layout.rotation next-rotation)
      (layout:layouter true)
      true)))

(fn light-ball-sync-runtime-light-transform [self]
  (when self.runtime-light
    (set self.runtime-light.position (self:center-from-layout))))

(fn light-ball-ensure-runtime-light [self]
  (assert (and app app.lights app.lights.add-point)
          "LightBall requires app.lights.add-point")
  (local existing
    (and self.runtime-light-id
         app.lights.find-point-by-id
         (app.lights:find-point-by-id self.runtime-light-id)))
  (if existing
      (do
        (set self.runtime-light existing)
        existing)
      (if (not (light-ball-can-allocate-runtime-light?))
          (do
            (set self.runtime-light nil)
            nil)
          (do
        (local next-id (or self.runtime-light-id (next-runtime-light-id)))
        (local config (clone-table self.light-config))
        (set config.id next-id)
        (set config.position (self:center-from-layout))
        (set config.transient? true)
        (local created (app.lights:add-point config))
        (assert created (.. "LightBall failed to allocate point light " next-id))
        (set self.runtime-light-id next-id)
        (set self.runtime-light created)
        created))))

(fn light-ball-remove-runtime-light [self]
  (if (not self.runtime-light-id)
      true
      (do
        (assert (and app app.lights app.lights.remove-point-by-id)
                "LightBall requires app.lights.remove-point-by-id")
        (local removed (app.lights:remove-point-by-id self.runtime-light-id))
        (local missing?
          (if app.lights.find-point-by-id
              (not (app.lights:find-point-by-id self.runtime-light-id))
              removed))
        (set self.runtime-light nil)
        (set self.runtime-light-id nil)
        (or removed missing?))))

(fn light-ball-apply-light-values [self validated]
  (set self.light-config.enabled? validated.enabled)
  (set self.light-config.ambient (resolve-glm-vec3 validated.ambient self.light-config.ambient))
  (set self.light-config.diffuse (resolve-glm-vec3 validated.diffuse self.light-config.diffuse))
  (set self.light-config.specular (resolve-glm-vec3 validated.specular self.light-config.specular))
  (set self.light-config.specular-power validated.specular-power)
  (set self.light-config.constant validated.constant)
  (set self.light-config.linear validated.linear)
  (set self.light-config.quadratic validated.quadratic)
  (when self.runtime-light
    (set self.runtime-light.enabled? self.light-config.enabled?)
    (set self.runtime-light.ambient self.light-config.ambient)
    (set self.runtime-light.diffuse self.light-config.diffuse)
    (set self.runtime-light.specular self.light-config.specular)
    (set self.runtime-light.specular-power self.light-config.specular-power)
    (set self.runtime-light.constant self.light-config.constant)
    (set self.runtime-light.linear self.light-config.linear)
    (set self.runtime-light.quadratic self.light-config.quadratic))
  true)

(fn light-ball-apply-layout-to-body [self]
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

(fn light-ball-destroy-body [self]
  (when (and self.body self.body-active? (physics-available?))
    (app.engine.physics:removeRigidBody self.body))
  (set self.body-active? false)
  (set self.last-physics-active? false)
  (set self.body nil)
  (set self.motion-state nil)
  (set self.shape nil))

(fn light-ball-ensure-body [self]
  (when (and (physics-available?) (not self.body))
    (local center (self:center-from-layout))
    (local shape (bt.SphereShape self.radius))
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
    (set self.last-physics-active? true)
    (set self.body-active? true)))

(fn light-ball-rebuild-body [self]
  (local center (self:center-from-layout))
  (local rotation (or (and self.layout self.layout.rotation) (glm.quat 1 0 0 0)))
  (local body-active? self.body-active?)
  (self:destroy-body)
  (when body-active?
    (self:ensure-body)
    (self:set-layout-transform-from-body center rotation)
    (self:apply-layout-to-body)
    (when self.body
      (sync-moved-body self.body))))

(fn light-ball-apply-physics-values [self validated]
  (set self.radius validated.radius)
  (local next-size (glm.vec3 (* 2 validated.radius)
                             (* 2 validated.radius)
                             (* 2 validated.radius)))
  (set self.state.current-size next-size)
  (set self.half-size (glm.vec3 validated.radius validated.radius validated.radius))
  (set self.mass validated.mass)
  (set self.friction validated.friction)
  (set self.rolling-friction validated.rolling-friction)
  (set self.spinning-friction validated.spinning-friction)
  (set self.restitution validated.restitution)
  (set self.linear-damping validated.linear-damping)
  (set self.angular-damping validated.angular-damping)
  (set self.linear-sleeping-threshold validated.linear-sleeping-threshold)
  (set self.angular-sleeping-threshold validated.angular-sleeping-threshold)
  (set self.additional-damping validated.additional-damping)
  (set self.additional-damping-factor validated.additional-damping-factor)
  (set self.additional-linear-damping-threshold-sqr validated.additional-linear-damping-threshold-sqr)
  (set self.additional-angular-damping-threshold-sqr validated.additional-angular-damping-threshold-sqr)
  (set self.additional-angular-damping-factor validated.additional-angular-damping-factor)
  (set self.initial-velocity (resolve-bt-vec3 validated.initial-velocity nil))
  (set self.initial-angular-velocity (resolve-bt-vec3 validated.initial-angular-velocity nil))
  (set self.gravity (resolve-bt-vec3 validated.gravity nil))
  (set self.linear-factor (resolve-bt-vec3 validated.linear-factor nil))
  (set self.angular-factor
       (if (= (type validated.angular-factor) :number)
           validated.angular-factor
           (resolve-bt-vec3 validated.angular-factor nil)))
  (set self.anisotropic-friction (resolve-bt-vec3 validated.anisotropic-friction nil))
  (set self.anisotropic-friction-mode validated.anisotropic-friction-mode)
  (set self.contact-processing-threshold validated.contact-processing-threshold)
  (set self.contact-stiffness validated.contact-stiffness)
  (set self.contact-damping validated.contact-damping)
  (set self.ccd-motion-threshold validated.ccd-motion-threshold)
  (set self.ccd-swept-sphere-radius validated.ccd-swept-sphere-radius)
  (set self.collision-flags validated.collision-flags)
  (set self.body-flags validated.body-flags)
  (set self.deactivation-time validated.deactivation-time)
  (set self.activation-state (or validated.activation-state self.activation-state))
  (when self.layout
    (set self.layout.size next-size)
    (set self.layout.measure next-size)
    (self.layout:mark-measure-dirty))
  (self:rebuild-body)
  true)

(fn light-ball-teleport-origin-position [self next-position]
  (self:ensure-body)
  (set self.layout.position next-position)
  (self.layout:mark-layout-dirty)
  (when (and self.body self.body-active? (physics-available?))
    (self:apply-layout-to-body)
    (sync-moved-body self.body)
    (when self.body.forceActivationState
      (self.body:forceActivationState self.activation-state))
    (when self.body.activate
      (self.body:activate true)))
  (self:sync-runtime-light-transform))

(fn light-ball-sync [self]
  (self:ensure-runtime-light)
  (when (and self.body self.body-active? (physics-available?))
    (if self.dragging
        (do
          (set self.last-physics-active? true)
          (self:apply-layout-to-body))
        (do
          (local physics-active?
            (if self.body.isActive
                (self.body:isActive)
                true))
          (when (or physics-active? self.last-physics-active?)
            (set self.last-physics-active? physics-active?)
            (local center (glm-from-bt-vec3 (self.body:getCenterOfMassPosition)))
            (local rotation (bt-quat->glm-quat (self.body:getOrientation)))
            (self:set-layout-transform-from-body center rotation)))))
  (self:sync-runtime-light-transform))

(fn light-ball-begin-drag [self]
  (set self.dragging true)
  (self:ensure-body)
  (self:ensure-runtime-light))

(fn light-ball-end-drag [self]
  (set self.dragging false)
  (when (and self.body self.body-active? (physics-available?))
    (self:apply-layout-to-body)
    (sync-moved-body self.body)
    (when self.body.forceActivationState
      (self.body:forceActivationState self.activation-state))
    (when self.body.activate
      (self.body:activate true))
    (self.body:applyForce (bt.Vector3 0 -0.5 0)))
  (self:sync-runtime-light-transform))

(fn light-ball-open-editor [self]
  (assert (and app app.hud app.hud.add-panel-child)
          "LightBall edit requires app.hud.add-panel-child")
  (app.hud:add-panel-child {:builder (build-light-ball-dialog self)
                            :layer :float}))

(fn light-ball-drop [self]
  (when self.unregister-context-menu-target
    (self:unregister-context-menu-target))
  (self:remove-runtime-light)
  (self:destroy-body)
  (when self.positioned
    (self.positioned:drop)))

(fn light-ball-intersect [self ray]
  (ray-sphere-intersection ray (self:center-from-layout) self.radius))

(fn light-ball-capture-persistence [self]
  (capture-light-ball-persistence self self.state.current-size))

(fn attach-light-ball-methods [self]
  (set self.ensure-runtime-light light-ball-ensure-runtime-light)
  (set self.remove-runtime-light light-ball-remove-runtime-light)
  (set self.apply-light-values light-ball-apply-light-values)
  (set self.apply-physics-values light-ball-apply-physics-values)
  (set self.ensure-body light-ball-ensure-body)
  (set self.sync light-ball-sync)
  (set self.begin-drag light-ball-begin-drag)
  (set self.end-drag light-ball-end-drag)
  (set self.apply-layout-to-body light-ball-apply-layout-to-body)
  (set self.teleport-origin-position light-ball-teleport-origin-position)
  (set self.intersect light-ball-intersect)
  (set self.set-layout-transform-from-body light-ball-set-layout-transform-from-body)
  (set self.center-from-layout light-ball-center-from-layout)
  (set self.sync-runtime-light-transform light-ball-sync-runtime-light-transform)
  (set self.open-editor light-ball-open-editor)
  (set self.capture-persistence light-ball-capture-persistence)
  (set self.rebuild-body light-ball-rebuild-body)
  (set self.destroy-body light-ball-destroy-body)
  (set self.drop light-ball-drop)
  self)

(fn light-ball-scene-object-options [_self]
  {:skip-cuboid true
   :skip-physics true
   :persistence {:kind "light-ball"
                 :restorer-module "light-ball"}}) (fn light-ball-clickables [] (assert app.clickables "light-ball scene context requires app.clickables"))

(fn light-ball-scene-on-added [_self scene element]
  (element:ensure-runtime-light)
  (element:sync-runtime-light-transform)
  (when element.intersect (local interaction-clickables (light-ball-clickables))
    (local right-click-target
      {:pointer-target app.scene
       :intersect (fn [_target ray]
                    (element:intersect ray))
       :on-right-click
       (fn [_target event]
         (local manager app.menu-manager)
         (when manager
           (manager:open {:actions [{:name "Edit"
                                     :icon "edit"
                                     :fn (fn [_button _click-event]
                                           (element:open-editor))}
                                    {:name "Remove"
                                     :icon "close"
                                     :fn (fn [_button _click-event]
                                           (element:remove-runtime-light)
                                           (scene:remove-panel-child element))}]
                          :position (resolve-menu-position event)
                          :open-button (and event event.button)}))
         true)})
    (interaction-clickables:register-right-click right-click-target)
    (set element.__context-menu-target right-click-target)
    (set element.unregister-context-menu-target
         (fn [self]
           (when self.__context-menu-target
              (interaction-clickables:unregister-right-click self.__context-menu-target)
              (set self.__context-menu-target nil)))))
  (scene:register-scene-object
   {:owner element
    :element element
    :terrain-binding {:enabled? true
                      :get-origin-position (fn [_entry]
                                             element.layout.position)
                      :get-support-bounds (fn [_entry]
                                            {:position element.layout.position
                                             :rotation element.layout.rotation
                                             :size (or element.layout.size
                                                       element.layout.measure
                                                       (glm.vec3 0 0 0))})
                      :move-origin-position! (fn [_entry next-position]
                                               (element:teleport-origin-position next-position))}
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
              (element:sync entity.layout)))}))

(fn light-ball-scene-on-removed [_self _scene element]
  (when element.unregister-context-menu-target
    (element:unregister-context-menu-target)))

(fn create-light-ball [opts]
  (local options (or opts {}))
  (local radius (or options.radius 9))
  (local default-size (glm.vec3 (* 2 radius) (* 2 radius) (* 2 radius)))
  (local current-size (resolve-glm-vec3 options.size default-size))
  (local half-size (glm.vec3 (* 0.5 current-size.x) (* 0.5 current-size.y) (* 0.5 current-size.z)))
  (local offset (resolve-glm-vec3 options.position (glm.vec3 0 0 0)))
  (local initial-velocity (resolve-bt-vec3 options.initial-velocity nil))
  (local initial-angular-velocity (resolve-bt-vec3 options.initial-angular-velocity nil))
  (local gravity (resolve-bt-vec3 options.gravity default-physics-config.gravity))
  (local linear-factor (resolve-bt-vec3 options.linear-factor nil))
  (local angular-factor
    (if (= (type options.angular-factor) :number)
        options.angular-factor
        (resolve-bt-vec3 options.angular-factor nil)))
  (local anisotropic-friction (resolve-bt-vec3 options.anisotropic-friction nil))
  (local default-activation-state (or (and bt bt.ACTIVE_TAG) 1))
  (local visual-builder
    (or options.visual
        (SphereVisual {:size current-size
                       :color (resolve-glm-vec4 options.color (glm.vec4 1.0 0.85 0.3 1.0))
                       :segments options.segments
                       :rings options.rings})))
  (local light-config
    {:enabled? (if (= options.enabled? nil)
                   default-light-config.enabled?
                   options.enabled?)
     :ambient (resolve-glm-vec3 options.ambient default-light-config.ambient)
     :diffuse (resolve-glm-vec3 options.diffuse default-light-config.diffuse)
     :specular (resolve-glm-vec3 options.specular default-light-config.specular)
     :specular-power (or options.specular-power default-light-config.specular-power)
     :constant (or options.constant default-light-config.constant)
     :linear (or options.linear default-light-config.linear)
     :quadratic (or options.quadratic default-light-config.quadratic)})
  (local persistence-options
    {:radius radius
     :mass (or options.mass default-physics-config.mass)
     :friction (or options.friction default-physics-config.friction)
     :rolling-friction options.rolling-friction
     :spinning-friction options.spinning-friction
     :restitution (or options.restitution default-physics-config.restitution)
     :linear-damping (or options.linear-damping default-physics-config.linear-damping)
     :angular-damping (or options.angular-damping default-physics-config.angular-damping)
     :linear-sleeping-threshold options.linear-sleeping-threshold
     :angular-sleeping-threshold options.angular-sleeping-threshold
     :additional-damping options.additional-damping
     :additional-damping-factor options.additional-damping-factor
     :additional-linear-damping-threshold-sqr options.additional-linear-damping-threshold-sqr
     :additional-angular-damping-threshold-sqr options.additional-angular-damping-threshold-sqr
     :additional-angular-damping-factor options.additional-angular-damping-factor
     :anisotropic-friction-mode options.anisotropic-friction-mode
     :contact-processing-threshold options.contact-processing-threshold
     :contact-stiffness options.contact-stiffness
     :contact-damping options.contact-damping
     :ccd-motion-threshold options.ccd-motion-threshold
     :ccd-swept-sphere-radius options.ccd-swept-sphere-radius
     :collision-flags options.collision-flags
     :body-flags (or options.body-flags default-physics-config.body-flags)
     :deactivation-time options.deactivation-time
     :activation-state (or options.activation-state default-activation-state)
     :color (resolve-glm-vec4 options.color (glm.vec4 1.0 0.85 0.3 1.0))
     :light-config light-config})
  (local object
    {:scene-object-options light-ball-scene-object-options
     :scene-on-added light-ball-scene-on-added
     :scene-on-removed light-ball-scene-on-removed})
  (setmetatable
    object
    {:__call
     (fn [_self ctx]
       (local state {:current-size current-size})
       (local sphere (visual-builder ctx))
       (local positioned
         ((Positioned {:position offset
                       :size (fn [] state.current-size)
                       :child (fn [_] sphere)})
          ctx))
       (attach-light-ball-methods
         {:sphere sphere
          :positioned positioned
          :layout positioned.layout
          :state state
          :offset offset
          :half-size half-size
          :radius radius
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
          :initial-velocity initial-velocity
          :initial-angular-velocity initial-angular-velocity
          :gravity gravity
          :linear-factor linear-factor
          :angular-factor angular-factor
          :anisotropic-friction anisotropic-friction
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
          :color persistence-options.color
          :light-config (clone-table persistence-options.light-config)
          :runtime-light-id nil
          :runtime-light nil
          :body nil
          :motion-state nil
          :shape nil
          :body-active? false
          :last-physics-active? false
          :dragging false
          :is-light-ball true}) )})
  object)

(fn LightBall.restore [payload]
  (local scene payload.scene)
  (local panel payload.panel)
  (assert scene "LightBall.restore requires :scene")
  (assert panel "LightBall.restore requires :panel")
  (assert scene.add-light-ball "LightBall.restore requires scene.add-light-ball")
  (scene:add-light-ball
    {:radius panel.radius
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
     :color (array->vec4 panel.color)
     :enabled? panel.enabled?
     :ambient (array->vec3 panel.ambient)
     :diffuse (array->vec3 panel.diffuse)
     :specular (array->vec3 panel.specular)
     :specular-power panel.specular-power
     :constant panel.constant
     :linear panel.linear
     :quadratic panel.quadratic
     :position (array->vec3 panel.position)
     :rotation (array->quat panel.rotation)}))

(fn LightBall.make [opts]
  (create-light-ball opts))

(setmetatable LightBall {:__call (fn [_ opts] (create-light-ball opts))})

LightBall
