(local ValidationUtils (require :graph/validation-utils))

(local bool-items
  [["true" "Enabled"]
   ["false" "Disabled"]])

(local type-field-specs
  {"ambient" [{:key :enabled
               :label "Enabled"
               :placeholder "Enabled"
               :items bool-items}
              {:key :color
               :label "Color"
               :placeholder "r, g, b"}]
   "directional" [{:key :enabled
                   :label "Enabled"
                   :placeholder "Enabled"
                   :items bool-items}
                  {:key :direction
                   :label "Direction"
                   :placeholder "x, y, z"}
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
                   :placeholder "Specular power"}]
   "point" [{:key :enabled
             :label "Enabled"
             :placeholder "Enabled"
             :items bool-items}
            {:key :position
             :label "Position"
             :placeholder "x, y, z"}
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
             :placeholder "Quadratic attenuation"}]
   "spot" [{:key :enabled
            :label "Enabled"
            :placeholder "Enabled"
            :items bool-items}
           {:key :position
            :label "Position"
            :placeholder "x, y, z"}
           {:key :direction
            :label "Direction"
            :placeholder "x, y, z"}
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
           {:key :cutoff
            :label "Cutoff"
            :placeholder "Cutoff"}
           {:key :outer-cutoff
            :label "Outer Cutoff"
            :placeholder "Outer cutoff"}
           {:key :constant
            :label "Constant"
            :placeholder "Constant attenuation"}
           {:key :linear
            :label "Linear"
            :placeholder "Linear attenuation"}
           {:key :quadratic
            :label "Quadratic"
            :placeholder "Quadratic attenuation"}]})

(fn join-values [items]
  (ValidationUtils.join-values items))

(fn bool-text [value]
  (if (= value false) "false" "true"))

(fn validate-bool [text]
  (if (= text "true")
      (ValidationUtils.valid true)
      (if (= text "false")
          (ValidationUtils.valid false)
          (ValidationUtils.invalid "Value must be true or false"))))

(fn make-record-draft [type-key record]
  (local target (or record {}))
  (if (= type-key "ambient")
      {:enabled (bool-text target.enabled?)
       :color (join-values (or target.color target.ambient))}
      (= type-key "directional")
      {:enabled (bool-text target.enabled?)
       :direction (join-values target.direction)
       :ambient (join-values target.ambient)
       :diffuse (join-values target.diffuse)
       :specular (join-values target.specular)
       :specular-power (tostring (or target.specular-power ""))}
      (= type-key "point")
      {:enabled (bool-text target.enabled?)
       :position (join-values target.position)
       :ambient (join-values target.ambient)
       :diffuse (join-values target.diffuse)
       :specular (join-values target.specular)
       :specular-power (tostring (or target.specular-power ""))
       :constant (tostring (or target.constant ""))
       :linear (tostring (or target.linear ""))
       :quadratic (tostring (or target.quadratic ""))}
      (= type-key "spot")
      {:enabled (bool-text target.enabled?)
       :position (join-values target.position)
       :direction (join-values target.direction)
       :ambient (join-values target.ambient)
       :diffuse (join-values target.diffuse)
       :specular (join-values target.specular)
       :specular-power (tostring (or target.specular-power ""))
       :cutoff (tostring (or target.cutoff ""))
       :outer-cutoff (tostring (or target.outer-cutoff ""))
       :constant (tostring (or target.constant ""))
       :linear (tostring (or target.linear ""))
       :quadratic (tostring (or target.quadratic ""))}
      {}))

(fn validate-field [type-key field-key text]
  (if (= field-key :enabled)
      (validate-bool text)
      (= field-key :color)
      (ValidationUtils.validate-vector text "Color" 3)
      (= field-key :direction)
      (ValidationUtils.validate-vector text "Direction" 3)
      (= field-key :position)
      (ValidationUtils.validate-vector text "Position" 3)
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
      (= field-key :cutoff)
      (ValidationUtils.validate-number text "Cutoff")
      (= field-key :outer-cutoff)
      (ValidationUtils.validate-number text "Outer cutoff")
      (ValidationUtils.invalid (.. "Unknown " type-key " light field"))))

(fn validation-for-type [type-key]
  (local field-specs
    (assert (. type-field-specs type-key)
            (.. "Unknown light validation type " (tostring type-key))))
  {:field-specs field-specs
   :draft-from-record (fn [record]
                        (make-record-draft type-key record))
   :draft-equals? (fn [left right]
                    (var equal? true)
                    (each [_ spec (ipairs field-specs)]
                      (local key spec.key)
                      (when (and equal? (not (= (or (. left key) "")
                                                (or (. right key) ""))))
                        (set equal? false)))
                    equal?)
   :validate-field (fn [field-key text]
                     (validate-field type-key field-key text))
   :validate-draft
   (fn [draft]
     (local parsed-values {})
     (local errors {})
     (var error-count 0)
     (each [_ spec (ipairs field-specs)]
       (local key spec.key)
       (local result (validate-field type-key key (. draft key)))
       (if result.ok?
           (set (. parsed-values key) result.value)
           (do
             (set (. errors key) result.error)
             (set error-count (+ error-count 1)))))
     (when (and (= type-key "spot")
                (not errors.cutoff)
                (not (. errors :outer-cutoff))
                (<= parsed-values.cutoff (. parsed-values :outer-cutoff)))
       (set (. errors :cutoff) "Cutoff must be greater than outer cutoff")
       (set error-count (+ error-count 1)))
     {:ok? (= error-count 0)
      :values parsed-values
      :errors errors
      :error-count error-count})})

{:validation-for-type validation-for-type}
