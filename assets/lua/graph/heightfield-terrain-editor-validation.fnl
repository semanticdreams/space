(local ValidationUtils (require :graph/terrain-validation-utils))

(local M {})

(local field-specs
  [{:key :name :label "Name" :placeholder "Terrain name"}
   {:key :position :label "Position" :placeholder "x, y, z"}
   {:key :rotation :label "Rotation" :placeholder "w, x, y, z"}
   {:key :opacity :label "Opacity" :placeholder "Opacity"}
   {:key :physics :label "Physics" :placeholder "Physics" :items [{:value "enabled" :label "Enabled"}
                                                                  {:value "disabled" :label "Disabled"}]}
   {:key :sample-spacing :label "Sample Spacing" :placeholder "x, z"}])

(fn trim-text [text]
  (string.match (or text "") "^%s*(.-)%s*$"))

(fn text-or-nil [text]
  (local trimmed (trim-text text))
  (if (> (string.len trimmed) 0)
      trimmed
      nil))

(fn validate-positive-vector [text label count]
  (local result (ValidationUtils.validate-vector text label count))
  (if (not result.ok?)
      result
      (do
        (var valid? true)
        (each [_ value (ipairs result.value)]
          (when (and valid? (<= value 0))
            (set valid? false)))
        (if valid?
            result
            (ValidationUtils.invalid (.. label " components must be positive numbers"))))))

(fn M.draft-from-record [record]
  (local name (or (and record record.name) ""))
  (local options (ValidationUtils.record-options record))
  {:name name
   :position (ValidationUtils.join-values (or options.position [0 -100 0]))
   :rotation (ValidationUtils.join-values (or options.rotation [1 0 0 0]))
   :opacity (tostring (or options.opacity 1.0))
   :physics (if (or (= options.physics nil) options.physics) "enabled" "disabled")
   :sample-spacing (ValidationUtils.join-values (or options.sample-spacing [20 20]))})

(fn M.draft-equals? [left right]
  (var equal? true)
  (each [_ spec (ipairs field-specs)]
    (local key spec.key)
    (when (and equal? (not (= (or (. left key) "") (or (. right key) ""))))
      (set equal? false)))
  equal?)

(fn M.validate-field [field-key text]
  (if (= field-key :name)
      (ValidationUtils.valid (text-or-nil text))
      (= field-key :position)
      (ValidationUtils.validate-vector text "Position" 3)
      (= field-key :rotation)
      (ValidationUtils.validate-vector text "Rotation" 4)
      (= field-key :opacity)
      (ValidationUtils.validate-number-range text "Opacity" 0 1)
      (= field-key :physics)
      (if (or (= text "enabled") (= text "disabled"))
          (ValidationUtils.valid (= text "enabled"))
          (ValidationUtils.invalid "Physics must be enabled or disabled"))
      (= field-key :sample-spacing)
      (validate-positive-vector text "Sample spacing" 2)
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
