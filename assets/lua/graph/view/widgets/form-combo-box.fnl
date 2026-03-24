(local ComboBox (require :combo-box))

(fn FormComboBox [ctx opts]
  (local options (or opts {}))
  (local combo
    ((ComboBox {:name (or options.name "form-combo-box")
                :items (or options.items [])
                :value options.value
                :placeholder (or options.placeholder "Select")
                :max-menu-height 8})
     ctx))

  (set combo.set-text
       (fn [self value]
         (self:set-value value)))
  (set combo.get-text
       (fn [self]
         (self:get-value)))
  (when options.on-change
    (combo.changed:connect
      (fn [value]
        (options.on-change combo value))))
  combo)

FormComboBox
