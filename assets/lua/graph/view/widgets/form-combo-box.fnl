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
  (var changed-handler nil)
  (fn handle-change [value]
    (options.on-change combo value))
  (local drop-combo combo.drop)
  (fn drop [self]
    (when changed-handler
      (combo.changed:disconnect changed-handler true)
      (set changed-handler nil))
    (drop-combo self))
  (when options.on-change
    (set changed-handler
         (combo.changed:connect handle-change)))
  (set combo.drop drop)
  combo)

FormComboBox
