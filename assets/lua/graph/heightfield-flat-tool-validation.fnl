(local ValidationUtils (require :graph/validation-utils))
(local TargetValidation (require :graph/heightfield-tool-target-validation))

(local M {})

(local field-specs [])

(table.insert field-specs {:key :height :label "Flat Height" :placeholder "Height"})

(fn M.draft-from-record [record]
  (local options (ValidationUtils.record-options record))
  (local draft (TargetValidation.default-draft))
  (set draft.height (tostring (or options.default-height 0.0)))
  draft)

(fn M.draft-equals? [left right]
  (and (TargetValidation.draft-equals? left right)
       (= (or left.height "") (or right.height ""))))

(fn M.validate-field [field-key text]
  (if (= field-key :height)
      (ValidationUtils.validate-number text "Flat height")
      (ValidationUtils.invalid "Unknown field")))

(fn M.validate-draft [draft]
  (local target-result (TargetValidation.validate-draft draft))
  (local height-result (M.validate-field :height draft.height))
  (if (and target-result.ok? height-result.ok?)
      {:ok? true
       :values {:target target-result.values.target
                :height height-result.value}
       :errors {}
       :error-count 0}
      (do
        (local errors {})
        (var error-count 0)
        (each [key message (pairs (or target-result.errors {}))]
          (set (. errors key) message)
          (set error-count (+ error-count 1)))
        (when (not height-result.ok?)
          (set errors.height height-result.error)
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
