(local ValidationUtils (require :graph/validation-utils))

(local bool-items
  [["true" "Enabled"]
   ["false" "Disabled"]])

(fn valid [value]
  (ValidationUtils.valid value))

(fn invalid [message]
  (ValidationUtils.invalid message))

(fn join-values [items]
  (ValidationUtils.join-values items))

(fn join-vec-values [value]
  (if (= (type value) :userdata)
      (table.concat [(tostring value.x) (tostring value.y) (tostring value.z)] ", ")
      (join-values value)))

(fn bool-text [value]
  (if (= value false) "false" "true"))

(fn validate-bool [text]
  (if (= text "true")
      (valid true)
      (if (= text "false")
          (valid false)
          (invalid "Value must be true or false"))))

(fn validate-optional-number [text label]
  (if (= (or text "") "")
      (valid nil)
      (ValidationUtils.validate-number text label)))

(fn validate-optional-positive-number [text label minimum]
  (if (= (or text "") "")
      (valid nil)
      (ValidationUtils.validate-positive-number text label minimum)))

(fn validate-optional-integer [text label]
  (if (= (or text "") "")
      (valid nil)
      (do
        (local value (tonumber text))
        (if (not value)
            (invalid (.. label " must be a number"))
            (if (not (= value (math.floor value)))
                (invalid (.. label " must be an integer"))
                (valid value))))))

(fn validate-optional-vector [text label count]
  (if (= (or text "") "")
      (valid nil)
      (ValidationUtils.validate-vector text label count)))

(fn validate-optional-number-or-vector3 [text label]
  (if (= (or text "") "")
      (valid nil)
      (do
        (local number-value (tonumber text))
        (if number-value
            (valid number-value)
            (ValidationUtils.validate-vector text label 3)))))

(local light-field-specs
  [{:key :enabled
    :label "Enabled"
    :placeholder "Enabled"
    :items bool-items}
   {:key :ambient
    :label "Ambient"
    :placeholder "r, g, b"}
   {:key :diffuse
    :label "Diffuse"
    :placeholder "r, g, b"}
   {:key :specular
    :label "Specular"
    :placeholder "r, g, b"}
   {:key :specular-power
    :label "Specular Power"
    :placeholder "Specular power"}
   {:key :constant
    :label "Constant"
    :placeholder "Constant attenuation"}
   {:key :linear
    :label "Linear"
    :placeholder "Linear attenuation"}
   {:key :quadratic
    :label "Quadratic"
    :placeholder "Quadratic attenuation"}])

(local physics-field-specs
  [{:key :radius :label "Radius" :placeholder "Radius"}
   {:key :mass :label "Mass" :placeholder "Mass"}
   {:key :friction :label "Friction" :placeholder "Friction"}
   {:key :rolling-friction :label "Rolling Friction" :placeholder "Rolling friction"}
   {:key :spinning-friction :label "Spinning Friction" :placeholder "Spinning friction"}
   {:key :restitution :label "Restitution" :placeholder "Restitution"}
   {:key :linear-damping :label "Linear Damping" :placeholder "Linear damping"}
   {:key :angular-damping :label "Angular Damping" :placeholder "Angular damping"}
   {:key :linear-sleeping-threshold :label "Linear Sleep" :placeholder "Linear sleeping threshold"}
   {:key :angular-sleeping-threshold :label "Angular Sleep" :placeholder "Angular sleeping threshold"}
   {:key :additional-damping
    :label "Additional Damping"
    :placeholder "Enabled"
    :items bool-items}
   {:key :additional-damping-factor :label "Additional Damping Factor" :placeholder "Additional damping factor"}
   {:key :additional-linear-damping-threshold-sqr
    :label "Additional Linear Damp Threshold"
    :placeholder "Additional linear damping threshold sqr"}
   {:key :additional-angular-damping-threshold-sqr
    :label "Additional Angular Damp Threshold"
    :placeholder "Additional angular damping threshold sqr"}
   {:key :additional-angular-damping-factor
    :label "Additional Angular Damp Factor"
    :placeholder "Additional angular damping factor"}
   {:key :initial-velocity :label "Initial Velocity" :placeholder "x, y, z"}
   {:key :initial-angular-velocity :label "Initial Angular Velocity" :placeholder "x, y, z"}
   {:key :gravity :label "Gravity" :placeholder "x, y, z"}
   {:key :linear-factor :label "Linear Factor" :placeholder "x, y, z"}
   {:key :angular-factor :label "Angular Factor" :placeholder "number or x, y, z"}
   {:key :anisotropic-friction :label "Anisotropic Friction" :placeholder "x, y, z"}
   {:key :anisotropic-friction-mode :label "Anisotropic Friction Mode" :placeholder "Integer mode"}
   {:key :contact-processing-threshold :label "Contact Processing Threshold" :placeholder "Threshold"}
   {:key :contact-stiffness :label "Contact Stiffness" :placeholder "Stiffness"}
   {:key :contact-damping :label "Contact Damping" :placeholder "Damping"}
   {:key :ccd-motion-threshold :label "CCD Motion Threshold" :placeholder "CCD motion threshold"}
   {:key :ccd-swept-sphere-radius :label "CCD Swept Radius" :placeholder "CCD swept sphere radius"}
   {:key :collision-flags :label "Collision Flags" :placeholder "Integer flags"}
   {:key :body-flags :label "Body Flags" :placeholder "Integer flags"}
   {:key :deactivation-time :label "Deactivation Time" :placeholder "Deactivation time"}
   {:key :activation-state :label "Activation State" :placeholder "Integer activation state"}])

(fn light-draft-from-record [record]
  (local target (or record {}))
  {:enabled (bool-text target.enabled?)
   :ambient (join-vec-values target.ambient)
   :diffuse (join-vec-values target.diffuse)
   :specular (join-vec-values target.specular)
   :specular-power (tostring (or target.specular-power ""))
   :constant (tostring (or target.constant ""))
   :linear (tostring (or target.linear ""))
   :quadratic (tostring (or target.quadratic ""))})

(fn physics-draft-from-record [record]
  (local target (or record {}))
  {:radius (tostring (or target.radius ""))
   :mass (tostring (or target.mass ""))
   :friction (tostring (or target.friction ""))
   :rolling-friction (tostring (or target.rolling-friction ""))
   :spinning-friction (tostring (or target.spinning-friction ""))
   :restitution (tostring (or target.restitution ""))
   :linear-damping (tostring (or target.linear-damping ""))
   :angular-damping (tostring (or target.angular-damping ""))
   :linear-sleeping-threshold (tostring (or target.linear-sleeping-threshold ""))
   :angular-sleeping-threshold (tostring (or target.angular-sleeping-threshold ""))
   :additional-damping (bool-text (not (not target.additional-damping)))
   :additional-damping-factor (tostring (or target.additional-damping-factor ""))
   :additional-linear-damping-threshold-sqr (tostring (or target.additional-linear-damping-threshold-sqr ""))
   :additional-angular-damping-threshold-sqr (tostring (or target.additional-angular-damping-threshold-sqr ""))
   :additional-angular-damping-factor (tostring (or target.additional-angular-damping-factor ""))
   :initial-velocity (join-vec-values target.initial-velocity)
   :initial-angular-velocity (join-vec-values target.initial-angular-velocity)
   :gravity (join-vec-values target.gravity)
   :linear-factor (join-vec-values target.linear-factor)
   :angular-factor (if (= (type target.angular-factor) :number)
                       (tostring target.angular-factor)
                       (join-vec-values target.angular-factor))
   :anisotropic-friction (join-vec-values target.anisotropic-friction)
   :anisotropic-friction-mode (tostring (or target.anisotropic-friction-mode ""))
   :contact-processing-threshold (tostring (or target.contact-processing-threshold ""))
   :contact-stiffness (tostring (or target.contact-stiffness ""))
   :contact-damping (tostring (or target.contact-damping ""))
   :ccd-motion-threshold (tostring (or target.ccd-motion-threshold ""))
   :ccd-swept-sphere-radius (tostring (or target.ccd-swept-sphere-radius ""))
   :collision-flags (tostring (or target.collision-flags ""))
   :body-flags (tostring (or target.body-flags ""))
   :deactivation-time (tostring (or target.deactivation-time ""))
   :activation-state (tostring (or target.activation-state ""))})

(fn draft-equals? [field-specs left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "")
                              (or (. right key) ""))))
      (set equal? false)))
  equal?)

(fn make-validation [field-specs draft-from-record validate-field]
  {:field-specs field-specs
   :draft-from-record draft-from-record
   :draft-equals? (fn [left right]
                    (draft-equals? field-specs left right))
   :validate-field validate-field
   :validate-draft
   (fn [draft]
     (local parsed-values {})
     (local errors {})
     (var error-count 0)
     (each [_ spec (ipairs field-specs)]
       (local key spec.key)
       (local result (validate-field key (. draft key)))
       (if result.ok?
           (set (. parsed-values key) result.value)
           (do
             (set (. errors key) result.error)
             (set error-count (+ error-count 1)))))
     {:ok? (= error-count 0)
      :values parsed-values
      :errors errors
      :error-count error-count})})

(fn validate-light-field [field-key text]
  (if (= field-key :enabled)
      (validate-bool text)
      (= field-key :ambient)
      (ValidationUtils.validate-vector text "Ambient" 3)
      (= field-key :diffuse)
      (ValidationUtils.validate-vector text "Diffuse" 3)
      (= field-key :specular)
      (ValidationUtils.validate-vector text "Specular" 3)
      (= field-key :specular-power)
      (ValidationUtils.validate-positive-number text "Specular power" 0)
      (= field-key :constant)
      (ValidationUtils.validate-positive-number text "Constant attenuation" 0)
      (= field-key :linear)
      (ValidationUtils.validate-positive-number text "Linear attenuation" 0)
      (= field-key :quadratic)
      (ValidationUtils.validate-positive-number text "Quadratic attenuation" 0)
      (invalid "Unknown light-ball light field")))

(fn validate-physics-field [field-key text]
  (if (= field-key :radius)
      (ValidationUtils.validate-positive-number text "Radius" 0.001)
      (= field-key :mass)
      (ValidationUtils.validate-positive-number text "Mass" 0)
      (= field-key :friction)
      (ValidationUtils.validate-positive-number text "Friction" 0)
      (= field-key :rolling-friction)
      (validate-optional-positive-number text "Rolling friction" 0)
      (= field-key :spinning-friction)
      (validate-optional-positive-number text "Spinning friction" 0)
      (= field-key :restitution)
      (ValidationUtils.validate-positive-number text "Restitution" 0)
      (= field-key :linear-damping)
      (validate-optional-positive-number text "Linear damping" 0)
      (= field-key :angular-damping)
      (validate-optional-positive-number text "Angular damping" 0)
      (= field-key :linear-sleeping-threshold)
      (validate-optional-positive-number text "Linear sleeping threshold" 0)
      (= field-key :angular-sleeping-threshold)
      (validate-optional-positive-number text "Angular sleeping threshold" 0)
      (= field-key :additional-damping)
      (validate-bool text)
      (= field-key :additional-damping-factor)
      (validate-optional-positive-number text "Additional damping factor" 0)
      (= field-key :additional-linear-damping-threshold-sqr)
      (validate-optional-positive-number text "Additional linear damping threshold sqr" 0)
      (= field-key :additional-angular-damping-threshold-sqr)
      (validate-optional-positive-number text "Additional angular damping threshold sqr" 0)
      (= field-key :additional-angular-damping-factor)
      (validate-optional-positive-number text "Additional angular damping factor" 0)
      (= field-key :initial-velocity)
      (validate-optional-vector text "Initial velocity" 3)
      (= field-key :initial-angular-velocity)
      (validate-optional-vector text "Initial angular velocity" 3)
      (= field-key :gravity)
      (validate-optional-vector text "Gravity" 3)
      (= field-key :linear-factor)
      (validate-optional-vector text "Linear factor" 3)
      (= field-key :angular-factor)
      (validate-optional-number-or-vector3 text "Angular factor")
      (= field-key :anisotropic-friction)
      (validate-optional-vector text "Anisotropic friction" 3)
      (= field-key :anisotropic-friction-mode)
      (validate-optional-integer text "Anisotropic friction mode")
      (= field-key :contact-processing-threshold)
      (validate-optional-number text "Contact processing threshold")
      (= field-key :contact-stiffness)
      (validate-optional-number text "Contact stiffness")
      (= field-key :contact-damping)
      (validate-optional-number text "Contact damping")
      (= field-key :ccd-motion-threshold)
      (validate-optional-positive-number text "CCD motion threshold" 0)
      (= field-key :ccd-swept-sphere-radius)
      (validate-optional-positive-number text "CCD swept sphere radius" 0)
      (= field-key :collision-flags)
      (validate-optional-integer text "Collision flags")
      (= field-key :body-flags)
      (validate-optional-integer text "Body flags")
      (= field-key :deactivation-time)
      (validate-optional-number text "Deactivation time")
      (= field-key :activation-state)
      (validate-optional-integer text "Activation state")
      (invalid "Unknown light-ball physics field")))

{:light_validation (make-validation light-field-specs light-draft-from-record validate-light-field)
 :physics_validation (make-validation physics-field-specs physics-draft-from-record validate-physics-field)}
