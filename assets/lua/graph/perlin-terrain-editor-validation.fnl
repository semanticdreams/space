(local ValidationUtils (require :graph/terrain-validation-utils))

(local M {})

(local field-specs
  [{:key :width :label "Width" :placeholder "Width"}
   {:key :length :label "Length" :placeholder "Length"}
   {:key :seed :label "Seed" :placeholder "Seed"}
   {:key :scale :label "Scale" :placeholder "x, y, z"}
   {:key :position :label "Position" :placeholder "x, y, z"}
   {:key :rotation :label "Rotation" :placeholder "w, x, y, z"}
   {:key :opacity :label "Opacity" :placeholder "Opacity"}
   {:key :n1div :label "Noise 1 Div" :placeholder "Noise 1 div"}
   {:key :n2div :label "Noise 2 Div" :placeholder "Noise 2 div"}
   {:key :n3div :label "Noise 3 Div" :placeholder "Noise 3 div"}
   {:key :n1scale :label "Noise 1 Scale" :placeholder "Noise 1 scale"}
   {:key :n2scale :label "Noise 2 Scale" :placeholder "Noise 2 scale"}
   {:key :n3scale :label "Noise 3 Scale" :placeholder "Noise 3 scale"}
   {:key :zroot :label "Height Root" :placeholder "Height root"}
   {:key :zpower :label "Height Power" :placeholder "Height power"}])

(fn M.draft-from-record [record]
  (local options (ValidationUtils.record-options record))
  {:width (tostring (or options.width ""))
   :length (tostring (or options.length ""))
   :seed (tostring (or options.seed ""))
   :scale (ValidationUtils.join-values options.scale)
   :position (ValidationUtils.join-values options.position)
   :rotation (ValidationUtils.join-values options.rotation)
   :opacity (tostring (or options.opacity ""))
   :n1div (tostring (or options.n1div ""))
   :n2div (tostring (or options.n2div ""))
   :n3div (tostring (or options.n3div ""))
   :n1scale (tostring (or options.n1scale ""))
   :n2scale (tostring (or options.n2scale ""))
   :n3scale (tostring (or options.n3scale ""))
   :zroot (tostring (or options.zroot ""))
   :zpower (tostring (or options.zpower ""))})

(fn M.draft-equals? [left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "") (or (. right key) ""))))
      (set equal? false)))
  equal?)

(fn M.validate-field [field-key text]
  (if (= field-key :width)
      (ValidationUtils.validate-integer-at-least text "Width" 2)
      (= field-key :length)
      (ValidationUtils.validate-integer-at-least text "Length" 2)
      (= field-key :seed)
      (ValidationUtils.validate-integer-range text "Seed" 0 4294967295)
      (= field-key :scale)
      (ValidationUtils.validate-vector text "Scale" 3)
      (= field-key :position)
      (ValidationUtils.validate-vector text "Position" 3)
      (= field-key :rotation)
      (ValidationUtils.validate-vector text "Rotation" 4)
      (= field-key :opacity)
      (ValidationUtils.validate-number-range text "Opacity" 0 1)
      (= field-key :n1div)
      (ValidationUtils.validate-positive-number text "Noise 1 div" 0.01)
      (= field-key :n2div)
      (ValidationUtils.validate-positive-number text "Noise 2 div" 0.01)
      (= field-key :n3div)
      (ValidationUtils.validate-positive-number text "Noise 3 div" 0.01)
      (= field-key :n1scale)
      (ValidationUtils.validate-positive-number text "Noise 1 scale" 0)
      (= field-key :n2scale)
      (ValidationUtils.validate-positive-number text "Noise 2 scale" 0)
      (= field-key :n3scale)
      (ValidationUtils.validate-positive-number text "Noise 3 scale" 0)
      (= field-key :zroot)
      (ValidationUtils.validate-positive-number text "Height root" 0.01)
      (= field-key :zpower)
      (ValidationUtils.validate-positive-number text "Height power" 0.01)
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
