(local glm (require :glm))
(local number-or
  (fn [value fallback]
    (if (not (= value nil)) value fallback)))

(fn to-table [data]
  (if (not data)
      {:x 0 :y 0 :width 0 :height 0}
      (if (= (type data) "userdata")
          {:x data.x
           :y data.y
           :width data.z
           :height data.w}
          {:x (number-or (or data.x data.x) 0)
           :y (number-or (or data.y data.y) 0)
           :width (number-or (or data.width data.w data.width data.w) 0)
           :height (number-or (or data.height data.h data.height data.h) 0)})))

(fn to-glm-vec4 [viewport]
  (glm.vec4 viewport.x viewport.y viewport.width viewport.height))

{:to-table to-table
 :to-glm-vec4 to-glm-vec4}
