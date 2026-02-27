(local MathUtils (require :math-utils))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn panel-placement-options [panel]
  (local layer (or (and panel panel.layer) "tiles"))
  (if (= layer "float")
      {:location :float
       :position (array->vec3 (and panel panel.position))
       :rotation (array->quat (and panel panel.rotation))
       :size (array->vec3 (and panel panel.size))}
      {:location :tiles
       :align-x (and panel panel.align-x)
       :align-y (and panel panel.align-y)}))

(fn assert-string-field [panel field label]
  (local value (. panel field))
  (assert (= (type value) :string) label)
  value)

{:panel-placement-options panel-placement-options
 :assert-string-field assert-string-field}
