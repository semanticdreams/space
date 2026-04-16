(local ValidationUtils (require :graph/validation-utils))
(local TargetValidation (require :graph/heightfield-tool-target-validation))

(local M {})

(local field-specs [])

(table.insert field-specs {:key :delta :label "Height Delta" :placeholder "Signed height delta"})

(fn M.draft-from-record [_record]
  (local draft (TargetValidation.default-draft))
  (set draft.delta "1")
  draft)

(fn M.draft-equals? [left right]
  (and (TargetValidation.draft-equals? left right)
       (= (or left.delta "") (or right.delta ""))))

(fn M.validate-field [field-key text]
  (if (= field-key :delta)
      (ValidationUtils.validate-number text "Height delta")
      (ValidationUtils.invalid "Unknown field")))

(fn M.validate-draft [draft]
  (local target-result (TargetValidation.validate-draft draft))
  (local delta-result (M.validate-field :delta draft.delta))
  (if (and target-result.ok? delta-result.ok?)
      {:ok? true
       :values {:target target-result.values.target
                :delta delta-result.value}
       :errors {}
       :error-count 0}
      (do
        (local errors {})
        (var error-count 0)
        (each [key message (pairs (or target-result.errors {}))]
          (set (. errors key) message)
          (set error-count (+ error-count 1)))
        (when (not delta-result.ok?)
          (set errors.delta delta-result.error)
          (set error-count (+ error-count 1)))
        {:ok? false
         :values {}
         :errors errors
         :error-count error-count})))

{:field-specs field-specs
 :draft-from-record M.draft-from-record
 :draft-equals? M.draft-equals?
 :validate-field M.validate-field
 :validate-draft M.validate-draft}
