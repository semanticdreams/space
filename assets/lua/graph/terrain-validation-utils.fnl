(local M {})

(fn M.join-values [items]
  (if (= (type items) :table)
      (table.concat (icollect [_ value (ipairs items)] (tostring value)) ", ")
      ""))

(fn M.record-options [record]
  (or (and record record.options) {}))

(fn M.parse-number [text]
  (local value (tonumber text))
  (if (and value (= value value) (not (= value math.huge)) (not (= value (- math.huge))))
      value
      nil))

(fn M.parse-number-list [text expected]
  (var parsed-items [])
  (each [part (string.gmatch (or text "") "[^,%s]+")]
    (when parsed-items
      (local value (M.parse-number part))
      (if value
          (table.insert parsed-items value)
          (set parsed-items nil))))
  (if (and parsed-items (= (length parsed-items) expected))
      parsed-items
      nil))

(fn M.valid [value]
  {:ok? true :value value})

(fn M.invalid [message]
  {:ok? false :error message})

(fn M.validate-integer-at-least [text label minimum]
  (local value (M.parse-number text))
  (if (not value)
      (M.invalid (.. label " must be a number"))
      (if (not (= value (math.floor value)))
          (M.invalid (.. label " must be an integer"))
          (if (< value minimum)
              (M.invalid (.. label " must be at least " (tostring minimum)))
              (M.valid value)))))

(fn M.validate-integer-range [text label min-value max-value]
  (local value (M.parse-number text))
  (if (not value)
      (M.invalid (.. label " must be a number"))
      (if (not (= value (math.floor value)))
          (M.invalid (.. label " must be an integer"))
          (if (or (< value min-value) (> value max-value))
              (M.invalid (.. label " must be between " (tostring min-value) " and " (tostring max-value)))
              (M.valid value)))))

(fn M.validate-positive-number [text label minimum]
  (local value (M.parse-number text))
  (if (not value)
      (M.invalid (.. label " must be a number"))
      (if (< value minimum)
          (M.invalid (.. label " must be at least " (tostring minimum)))
          (M.valid value))))

(fn M.validate-number [text label]
  (local value (M.parse-number text))
  (if value
      (M.valid value)
      (M.invalid (.. label " must be a number"))))

(fn M.validate-number-range [text label min-value max-value]
  (local value (M.parse-number text))
  (if (not value)
      (M.invalid (.. label " must be a number"))
      (if (or (< value min-value) (> value max-value))
          (M.invalid (.. label " must be between " (tostring min-value) " and " (tostring max-value)))
          (M.valid value))))

(fn M.validate-vector [text label count]
  (local value (M.parse-number-list text count))
  (if value
      (M.valid value)
      (M.invalid (.. label " must have exactly " (tostring count) " numbers"))))

M
