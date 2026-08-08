(local glm (require :glm))

(local default-size (glm.vec3 32.0 18.0 0))
(local min-size (glm.vec3 24.0 12.0 0))
(local max-size (glm.vec3 52.0 34.0 0))
(local resize-max-size (glm.vec3 90.0 60.0 0))

(fn copy-vec3 [value]
  (glm.vec3 value.x value.y value.z))

(fn inline-card-bounds []
  {:default-size (copy-vec3 default-size)
   :min-size (copy-vec3 min-size)
   :max-size (copy-vec3 max-size)
   :resize-max-size (copy-vec3 resize-max-size)})

(fn default-panel-size []
  (copy-vec3 default-size))

{:inline-card-bounds inline-card-bounds
 :default-panel-size default-panel-size}
