(local ValidationUtils (require :graph/terrain-validation-utils))

(fn create-validation []
  (local field-specs
    [{:key :color
      :label "Color"
      :placeholder "r, g, b"}])
  {:field-specs field-specs
   :draft-from-record
   (fn [record]
     {:color (ValidationUtils.join-values (and record record.color))})
   :draft-equals?
   (fn [left right]
     (= (or left.color "") (or right.color "")))
   :validate-field
   (fn [field-key text]
     (if (= field-key :color)
         (ValidationUtils.validate-vector text "Color" 3)
         (ValidationUtils.invalid "Unknown background field")))
   :validate-draft
   (fn [draft]
     (local parsed-values {})
     (local errors {})
     (var error-count 0)
     (each [_ spec (ipairs field-specs)]
       (local key spec.key)
       (local result
         (if (= key :color)
             (ValidationUtils.validate-vector (. draft key) "Color" 3)
             (ValidationUtils.invalid "Unknown background field")))
       (if result.ok?
           (set (. parsed-values key) result.value)
           (do
             (set (. errors key) result.error)
             (set error-count (+ error-count 1)))))
     {:ok? (= error-count 0)
      :values {:color parsed-values.color}
      :errors errors
      :error-count error-count})})

{:create-validation create-validation}
