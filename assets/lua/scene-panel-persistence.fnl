(local MathUtils (require :math-utils))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn panel-transform-options [panel]
  {:position (array->vec3 (and panel panel.position))
   :rotation (array->quat (and panel panel.rotation))
   :size (array->vec3 (and panel panel.size))})

{:panel-transform-options panel-transform-options}
