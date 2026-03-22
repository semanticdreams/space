(local M {})

(local field-specs
  [{:key :width :label "Width" :placeholder "Width"}
   {:key :length :label "Length" :placeholder "Length"}
   {:key :scale :label "Scale" :placeholder "x, y, z"}
   {:key :position :label "Position" :placeholder "x, y, z"}
   {:key :rotation :label "Rotation" :placeholder "w, x, y, z"}
   {:key :opacity :label "Opacity" :placeholder "Opacity"}
   {:key :physics-thickness :label "Physics Thickness" :placeholder "Physics thickness"}])

(fn join-values [items]
  (if (= (type items) :table)
      (table.concat (icollect [_ value (ipairs items)] (tostring value)) ", ")
      ""))

(fn record-options [record]
  (or (and record record.options) {}))

(fn parse-number [text]
  (local value (tonumber text))
  (if (and value (= value value) (not (= value math.huge)) (not (= value (- math.huge))))
      value
      nil))

(fn parse-number-list [text expected]
  (var parsed-items [])
  (each [part (string.gmatch (or text "") "[^,%s]+")]
    (when parsed-items
      (local value (parse-number part))
      (if value
          (table.insert parsed-items value)
          (set parsed-items nil))))
  (if (and parsed-items (= (length parsed-items) expected))
      parsed-items
      nil))

(fn valid [value]
  {:ok? true :value value})

(fn invalid [message]
  {:ok? false :error message})

(fn validate-positive-integer [text label]
  (local value (parse-number text))
  (if (not value)
      (invalid (.. label " must be a number"))
      (if (not (= value (math.floor value)))
          (invalid (.. label " must be an integer"))
          (if (< value 1)
              (invalid (.. label " must be at least 1"))
              (valid value)))))

(fn validate-positive-number [text label minimum]
  (local value (parse-number text))
  (if (not value)
      (invalid (.. label " must be a number"))
      (if (< value minimum)
          (invalid (.. label " must be at least " (tostring minimum)))
          (valid value))))

(fn validate-number-range [text label min-value max-value]
  (local value (parse-number text))
  (if (not value)
      (invalid (.. label " must be a number"))
      (if (or (< value min-value) (> value max-value))
          (invalid (.. label " must be between " (tostring min-value) " and " (tostring max-value)))
          (valid value))))

(fn validate-vector [text label count]
  (local value (parse-number-list text count))
  (if value
      (valid value)
      (invalid (.. label " must have exactly " (tostring count) " numbers"))))

(fn M.draft-from-record [record]
  (local options (record-options record))
  {:width (tostring (or options.width ""))
   :length (tostring (or options.length ""))
   :scale (join-values options.scale)
   :position (join-values options.position)
   :rotation (join-values options.rotation)
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
      (validate-positive-integer text "Width")
      (= field-key :length)
      (validate-positive-integer text "Length")
      (= field-key :scale)
      (validate-vector text "Scale" 3)
      (= field-key :position)
      (validate-vector text "Position" 3)
      (= field-key :rotation)
      (validate-vector text "Rotation" 4)
      (= field-key :opacity)
      (validate-number-range text "Opacity" 0 1)
      (= field-key :physics-thickness)
      (validate-positive-number text "Physics thickness" 0.01)
      (invalid "Unknown field")))

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
