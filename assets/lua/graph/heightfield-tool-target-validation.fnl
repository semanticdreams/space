(local ValidationUtils (require :graph/terrain-validation-utils))

(local M {})

(local target-mode-items
  [{:value "whole" :label "Whole Terrain"}
   {:value "rect" :label "Rectangle"}])

(local field-specs
  [{:key :target-mode
    :label "Target"
    :placeholder "Target mode"
    :items target-mode-items}
   {:key :rect-min-x
    :label "Rect Min X"
    :placeholder "Min sample X"}
   {:key :rect-min-z
    :label "Rect Min Z"
    :placeholder "Min sample Z"}
   {:key :rect-max-x
    :label "Rect Max X"
    :placeholder "Max sample X"}
   {:key :rect-max-z
    :label "Rect Max Z"
    :placeholder "Max sample Z"}])

(fn M.target-mode-items []
  target-mode-items)

(fn M.field-specs []
  field-specs)

(fn M.default-draft []
  {:target-mode "whole"
   :rect-min-x "0"
   :rect-min-z "0"
   :rect-max-x "0"
   :rect-max-z "0"})

(fn M.draft-equals? [left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "") (or (. right key) ""))))
      (set equal? false)))
  equal?)

(fn M.validate-field [field-key value]
  (if (= field-key :target-mode)
      (if (or (= value "whole") (= value "rect"))
          (ValidationUtils.valid value)
          (ValidationUtils.invalid "Target must be whole or rectangle"))
      (= field-key :rect-min-x)
      (ValidationUtils.validate-integer-range value "Rect min X" -1048576 1048576)
      (= field-key :rect-min-z)
      (ValidationUtils.validate-integer-range value "Rect min Z" -1048576 1048576)
      (= field-key :rect-max-x)
      (ValidationUtils.validate-integer-range value "Rect max X" -1048576 1048576)
      (= field-key :rect-max-z)
      (ValidationUtils.validate-integer-range value "Rect max Z" -1048576 1048576)
      (ValidationUtils.invalid "Unknown field")))

(fn M.validate-draft [draft]
  (local errors {})
  (local target-mode-result (M.validate-field :target-mode draft.target-mode))
  (if (not target-mode-result.ok?)
      {:ok? false
       :values {}
       :errors {:target-mode target-mode-result.error}
       :error-count 1}
      (if (= target-mode-result.value "whole")
          {:ok? true
           :values {:target {:mode :whole}}
           :errors {}
           :error-count 0}
          (do
            (local parsed-values {})
            (var error-count 0)
            (each [_ spec (ipairs field-specs)]
              (when (not (= spec.key :target-mode))
                (local result (M.validate-field spec.key (. draft spec.key)))
                (if result.ok?
                    (set (. parsed-values spec.key) result.value)
                    (do
                      (set (. errors spec.key) result.error)
                      (set error-count (+ error-count 1))))))
            (if (= error-count 0)
                (do
                  (local x0 (math.min parsed-values.rect-min-x parsed-values.rect-max-x))
                  (local x1 (math.max parsed-values.rect-min-x parsed-values.rect-max-x))
                  (local z0 (math.min parsed-values.rect-min-z parsed-values.rect-max-z))
                  (local z1 (math.max parsed-values.rect-min-z parsed-values.rect-max-z))
                  {:ok? true
                   :values {:target {:mode :rect
                                     :x0 x0
                                     :z0 z0
                                     :x1 x1
                                     :z1 z1}}
                   :errors {}
                   :error-count 0})
                {:ok? false
                 :values {}
                 :errors errors
                 :error-count error-count})))))

{:target-mode-items M.target-mode-items
 :field-specs M.field-specs
 :default-draft M.default-draft
 :draft-equals? M.draft-equals?
 :validate-field M.validate-field
 :validate-draft M.validate-draft}
