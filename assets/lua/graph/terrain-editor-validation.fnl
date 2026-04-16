(local ValidationUtils (require :graph/validation-utils))
(local M {})

(local field-specs
  [{:key :width :label "Width" :placeholder "Width"}
   {:key :length :label "Length" :placeholder "Length"}
   {:key :scale :label "Scale" :placeholder "x, y, z"}
   {:key :position :label "Position" :placeholder "x, y, z"}
   {:key :rotation :label "Rotation" :placeholder "w, x, y, z"}
   {:key :opacity :label "Opacity" :placeholder "Opacity"}
   {:key :physics-thickness :label "Physics Thickness" :placeholder "Physics thickness"}])

(fn M.draft-from-record [record]
  (local options (ValidationUtils.record-options record))
  {:width (tostring (or options.width ""))
   :length (tostring (or options.length ""))
   :scale (ValidationUtils.join-values options.scale)
   :position (ValidationUtils.join-values options.position)
   :rotation (ValidationUtils.join-values options.rotation)
   :opacity (tostring (or options.opacity ""))
   :physics-thickness (tostring (or options.physics-thickness ""))})

(fn M.draft-equals? [left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "") (or (. right key) ""))))
      (set equal? false)))
  equal?)

(fn M.validate-field [field-key text]
  (if (= field-key :width)
      (ValidationUtils.validate-integer-at-least text "Width" 1)
      (= field-key :length)
      (ValidationUtils.validate-integer-at-least text "Length" 1)
      (= field-key :scale)
      (ValidationUtils.validate-vector text "Scale" 3)
      (= field-key :position)
      (ValidationUtils.validate-vector text "Position" 3)
      (= field-key :rotation)
      (ValidationUtils.validate-vector text "Rotation" 4)
      (= field-key :opacity)
      (ValidationUtils.validate-number-range text "Opacity" 0 1)
      (= field-key :physics-thickness)
      (ValidationUtils.validate-positive-number text "Physics thickness" 0.01)
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
