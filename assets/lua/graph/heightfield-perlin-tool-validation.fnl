(local ValidationUtils (require :graph/validation-utils))
(local TargetValidation (require :graph/heightfield-tool-target-validation))
(local M {})

(local field-specs [])

(table.insert field-specs {:key :seed :label "Seed" :placeholder "Seed"})
(table.insert field-specs {:key :n1div :label "Noise 1 Div" :placeholder "Noise 1 div"})
(table.insert field-specs {:key :n2div :label "Noise 2 Div" :placeholder "Noise 2 div"})
(table.insert field-specs {:key :n3div :label "Noise 3 Div" :placeholder "Noise 3 div"})
(table.insert field-specs {:key :n1scale :label "Noise 1 Scale" :placeholder "Noise 1 scale"})
(table.insert field-specs {:key :n2scale :label "Noise 2 Scale" :placeholder "Noise 2 scale"})
(table.insert field-specs {:key :n3scale :label "Noise 3 Scale" :placeholder "Noise 3 scale"})
(table.insert field-specs {:key :zroot :label "Height Root" :placeholder "Height root"})
(table.insert field-specs {:key :zpower :label "Height Power" :placeholder "Height power"})

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
  (local draft (TargetValidation.default-draft))
  (set draft.seed (tostring options.seed))
  (set draft.n1div (tostring options.n1div))
  (set draft.n2div (tostring options.n2div))
  (set draft.n3div (tostring options.n3div))
  (set draft.n1scale (tostring options.n1scale))
  (set draft.n2scale (tostring options.n2scale))
  (set draft.n3scale (tostring options.n3scale))
  (set draft.zroot (tostring options.zroot))
  (set draft.zpower (tostring options.zpower))
  draft)

(fn M.draft-equals? [left right]
  (var equal? (TargetValidation.draft-equals? left right))
  (when equal?
    (each [_ spec (ipairs field-specs)]
      (local key spec.key)
      (when (and equal?
                 (not (= (or (. left key) "") (or (. right key) ""))))
        (set equal? false))))
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
  (local target-result (TargetValidation.validate-draft draft))
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
  (each [key message (pairs (or target-result.errors {}))]
    (set (. errors key) message)
    (set error-count (+ error-count 1)))
  (if target-result.ok?
      (set parsed-values.target target-result.values.target))
  {:ok? (and target-result.ok? (= error-count 0))
   :values parsed-values
   :errors errors
   :error-count error-count})

{:field-specs field-specs
 :draft-from-record M.draft-from-record
 :draft-equals? M.draft-equals?
 :validate-field M.validate-field
 :validate-draft M.validate-draft}
