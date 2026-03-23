(local ValidationUtils (require :graph/terrain-validation-utils))
(local M {})

(local field-specs
  [{:key :height :label "Flat Height" :placeholder "Height"}])

(fn M.draft-from-record [record]
  (local options (ValidationUtils.record-options record))
  {:height (tostring (or options.default-height 0.0))})

(fn M.draft-equals? [left right]
  (= (or left.height "") (or right.height "")))

(fn M.validate-field [field-key text]
  (if (= field-key :height)
      (ValidationUtils.validate-number text "Flat height")
      (ValidationUtils.invalid "Unknown field")))

(fn M.validate-draft [draft]
  (local result (M.validate-field :height draft.height))
  (if result.ok?
      {:ok? true
       :values {:height result.value}
       :errors {}
       :error-count 0}
      {:ok? false
       :values {}
       :errors {:height result.error}
       :error-count 1}))

{:field-specs field-specs
 :draft-from-record M.draft-from-record
 :draft-equals? M.draft-equals?
 :validate-field M.validate-field
 :validate-draft M.validate-draft}
