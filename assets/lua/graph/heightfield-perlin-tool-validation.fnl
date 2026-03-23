(local ValidationUtils (require :graph/terrain-validation-utils))
(local M {})

(local field-specs
  [{:key :seed :label "Seed" :placeholder "Seed"}
   {:key :n1div :label "Noise 1 Div" :placeholder "Noise 1 div"}
   {:key :n2div :label "Noise 2 Div" :placeholder "Noise 2 div"}
   {:key :n3div :label "Noise 3 Div" :placeholder "Noise 3 div"}
   {:key :n1scale :label "Noise 1 Scale" :placeholder "Noise 1 scale"}
   {:key :n2scale :label "Noise 2 Scale" :placeholder "Noise 2 scale"}
   {:key :n3scale :label "Noise 3 Scale" :placeholder "Noise 3 scale"}
   {:key :zroot :label "Height Root" :placeholder "Height root"}
   {:key :zpower :label "Height Power" :placeholder "Height power"}])

(fn default-options []
  {:seed 1337
   :n1div 30
   :n2div 4
   :n3div 1
   :n1scale 20
   :n2scale 2
   :n3scale 1
   :zroot 2
   :zpower 2.5})

(fn M.draft-from-record [_record]
  (local options (default-options))
  {:seed (tostring options.seed)
   :n1div (tostring options.n1div)
   :n2div (tostring options.n2div)
   :n3div (tostring options.n3div)
   :n1scale (tostring options.n1scale)
   :n2scale (tostring options.n2scale)
   :n3scale (tostring options.n3scale)
   :zroot (tostring options.zroot)
   :zpower (tostring options.zpower)})

(fn M.draft-equals? [left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "") (or (. right key) ""))))
      (set equal? false)))
  equal?)

(fn M.validate-field [field-key text]
  (if (= field-key :seed)
      (ValidationUtils.validate-integer-range text "Seed" 0 4294967295)
      (= field-key :n1div)
      (ValidationUtils.validate-positive-number text "Noise 1 div" 0.0001)
      (= field-key :n2div)
      (ValidationUtils.validate-positive-number text "Noise 2 div" 0.0001)
      (= field-key :n3div)
      (ValidationUtils.validate-positive-number text "Noise 3 div" 0.0001)
      (= field-key :n1scale)
      (ValidationUtils.validate-number text "Noise 1 scale")
      (= field-key :n2scale)
      (ValidationUtils.validate-number text "Noise 2 scale")
      (= field-key :n3scale)
      (ValidationUtils.validate-number text "Noise 3 scale")
      (= field-key :zroot)
      (ValidationUtils.validate-positive-number text "Height root" 0.0001)
      (= field-key :zpower)
      (ValidationUtils.validate-positive-number text "Height power" 0.0001)
      (ValidationUtils.invalid "Unknown field")))

(fn M.validate-draft [draft]
  (local parsed-values {})
  (local errors {})
  (var error-count 0)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (local result (M.validate-field key (. draft key)))
    (if result.ok?
        (set (. parsed-values key) result.value)
        (do
          (set (. errors key) result.error)
          (set error-count (+ error-count 1)))))
  {:ok? (= error-count 0)
   :values parsed-values
   :errors errors
   :error-count error-count})

{:field-specs field-specs
 :draft-from-record M.draft-from-record
 :draft-equals? M.draft-equals?
 :validate-field M.validate-field
 :validate-draft M.validate-draft}
