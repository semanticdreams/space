(local ValidationUtils (require :graph/validation-utils))

(local M {})

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn target-equals? [left right]
  (if (= left right)
      true
      (if (or (= left nil) (= right nil))
          false
          (and (= left.mode right.mode)
               (= left.shape right.shape)
               (= left.x0 right.x0)
               (= left.z0 right.z0)
               (= left.x1 right.x1)
               (= left.z1 right.z1)
               (if (= left.mode :samples)
                   (if (= left.shape :rect)
                       (= left.sample-count right.sample-count)
                       (do
                         (local left-samples (or left.samples []))
                         (local right-samples (or right.samples []))
                         (if (not (= (length left-samples) (length right-samples)))
                             false
                             (do
                               (var equal? true)
                               (each [idx sample (ipairs left-samples)]
                                 (local other (. right-samples idx))
                                 (when (and equal?
                                            (or (not other)
                                                (not (= sample.x other.x))
                                                (not (= sample.z other.z))))
                                   (set equal? false)))
                               equal?))))
                   true)))))

(local field-specs [])

(fn M.field-specs []
  field-specs)

(fn M.default-draft []
  {:picked-target nil})

(fn M.draft-equals? [left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "") (or (. right key) ""))))
      (set equal? false)))
  (when (and equal? (not (target-equals? left.picked-target right.picked-target)))
    (set equal? false))
  equal?)

(fn M.validate-field [field-key value]
  (ValidationUtils.invalid "Unknown field"))

(fn M.validate-draft [draft]
  (if draft.picked-target
      {:ok? true
       :values {:target (clone-table draft.picked-target)}
       :errors {}
       :error-count 0}
      {:ok? false
       :values {}
       :errors {:picked-target "Pick samples from the scene before applying"}
       :error-count 1}))

{:field-specs M.field-specs
 :default-draft M.default-draft
 :draft-equals? M.draft-equals?
 :validate-field M.validate-field
 :validate-draft M.validate-draft}
