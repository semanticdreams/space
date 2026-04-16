(local ValidationUtils (require :graph/validation-utils))

(local M {})

(local field-specs
  [{:key :min-chunk-x :label "Min Chunk X" :placeholder "Leftmost chunk"}
   {:key :min-chunk-z :label "Min Chunk Z" :placeholder "Backmost chunk"}
   {:key :max-chunk-x :label "Max Chunk X" :placeholder "Rightmost chunk"}
   {:key :max-chunk-z :label "Max Chunk Z" :placeholder "Frontmost chunk"}
   {:key :fill-height :label "New Chunk Height" :placeholder "Height for added chunks"}])

(fn chunk-bounds [record]
  (var min-chunk-x 0)
  (var max-chunk-x 0)
  (var min-chunk-z 0)
  (var max-chunk-z 0)
  (var initialized? false)
  (each [_ chunk (ipairs (or (and record record.chunks) []))]
    (local coord (or chunk.coord [0 0]))
    (local chunk-x (or (. coord 1) coord.x 0))
    (local chunk-z (or (. coord 2) coord.y coord.z 0))
    (if initialized?
        (do
          (when (< chunk-x min-chunk-x) (set min-chunk-x chunk-x))
          (when (> chunk-x max-chunk-x) (set max-chunk-x chunk-x))
          (when (< chunk-z min-chunk-z) (set min-chunk-z chunk-z))
          (when (> chunk-z max-chunk-z) (set max-chunk-z chunk-z)))
        (do
          (set initialized? true)
          (set min-chunk-x chunk-x)
          (set max-chunk-x chunk-x)
          (set min-chunk-z chunk-z)
          (set max-chunk-z chunk-z))))
  {:min-chunk-x min-chunk-x
   :max-chunk-x max-chunk-x
   :min-chunk-z min-chunk-z
   :max-chunk-z max-chunk-z})

(fn M.draft-from-record [record]
  (local bounds (chunk-bounds record))
  (local options (ValidationUtils.record-options record))
  {:min-chunk-x (tostring bounds.min-chunk-x)
   :min-chunk-z (tostring bounds.min-chunk-z)
   :max-chunk-x (tostring bounds.max-chunk-x)
   :max-chunk-z (tostring bounds.max-chunk-z)
   :fill-height (tostring (or options.default-height 0.0))})

(fn M.draft-equals? [left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "") (or (. right key) ""))))
      (set equal? false)))
  equal?)

(fn M.validate-field [field-key text]
  (if (= field-key :min-chunk-x)
      (ValidationUtils.validate-integer-range text "Chunk min X" -4096 4096)
      (= field-key :min-chunk-z)
      (ValidationUtils.validate-integer-range text "Chunk min Z" -4096 4096)
      (= field-key :max-chunk-x)
      (ValidationUtils.validate-integer-range text "Chunk max X" -4096 4096)
      (= field-key :max-chunk-z)
      (ValidationUtils.validate-integer-range text "Chunk max Z" -4096 4096)
      (= field-key :fill-height)
      (ValidationUtils.validate-number text "Fill height")
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
