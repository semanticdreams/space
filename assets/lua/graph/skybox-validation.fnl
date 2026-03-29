(local ValidationUtils (require :graph/terrain-validation-utils))

(local bool-items
  [["true" "Enabled"]
   ["false" "Disabled"]])

(fn bool-text [value]
  (if (= value false) "false" "true"))

(fn validate-bool [text]
  (if (= text "true")
      (ValidationUtils.valid true)
      (if (= text "false")
          (ValidationUtils.valid false)
          (ValidationUtils.invalid "Value must be true or false"))))

(fn skybox-name-items [items]
  (icollect [_ item (ipairs (or items []))]
    [(tostring (. item 1)) (tostring (. item 2))]))

(fn skybox-name-known? [items value]
  (var found? false)
  (each [_ item (ipairs (or items []))]
    (when (= (. item 1) value)
      (set found? true)))
  found?)

(fn create-validation [skybox-items]
  (local field-specs
    [{:key :enabled
      :label "Enabled"
      :placeholder "Enabled"
      :items bool-items}
     {:key :name
      :label "Skybox"
      :placeholder "Skybox"
      :items (skybox-name-items skybox-items)}
     {:key :brightness
      :label "Brightness"
      :placeholder "Brightness"}])
  {:field-specs field-specs
   :draft-from-record
   (fn [record]
     (local target (or record {}))
     {:enabled (bool-text target.enabled?)
      :name (or target.name "")
      :brightness (tostring (or target.brightness ""))})
   :draft-equals?
   (fn [left right]
     (var equal? true)
     (each [_ spec (ipairs field-specs)]
       (local key spec.key)
       (when (and equal? (not (= (or (. left key) "")
                                 (or (. right key) ""))))
         (set equal? false)))
     equal?)
   :validate-field
   (fn [field-key text]
     (if (= field-key :enabled)
         (validate-bool text)
         (= field-key :name)
         (if (skybox-name-known? skybox-items text)
             (ValidationUtils.valid text)
             (ValidationUtils.invalid "Skybox must be one of the discovered choices"))
         (= field-key :brightness)
         (ValidationUtils.validate-number text "Brightness")
         (ValidationUtils.invalid "Unknown skybox field")))
   :validate-draft
   (fn [draft]
     (local parsed-values {})
     (local errors {})
     (var error-count 0)
     (each [_ spec (ipairs field-specs)]
       (local key spec.key)
       (local result
         (if (= key :enabled)
             (validate-bool (. draft key))
             (if (= key :name)
                 (if (skybox-name-known? skybox-items (. draft key))
                     (ValidationUtils.valid (. draft key))
                     (ValidationUtils.invalid "Skybox must be one of the discovered choices"))
                 (ValidationUtils.validate-number (. draft key) "Brightness"))))
       (if result.ok?
           (set (. parsed-values key) result.value)
           (do
             (set (. errors key) result.error)
             (set error-count (+ error-count 1)))))
     {:ok? (= error-count 0)
      :values {:enabled? parsed-values.enabled
               :name parsed-values.name
               :brightness parsed-values.brightness}
      :errors errors
      :error-count error-count})})

{:create-validation create-validation}
