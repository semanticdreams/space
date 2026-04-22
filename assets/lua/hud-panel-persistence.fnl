(local PanelUtils (require :target-panel-utils))

(fn panel-placement-options [panel target]
  (PanelUtils.panel-placement-options target panel))

(fn assert-string-field [panel field label]
  (local value (. panel field))
  (assert (= (type value) :string) label)
  value)

{:panel-placement-options panel-placement-options
 :assert-string-field assert-string-field}
