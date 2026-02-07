(fn assert-light-count [count max label]
  (assert (<= count max) (.. label " exceeds max " max))
  count)

(fn apply-vec3 [shader uniform value]
  (shader:setVector3f uniform value.x value.y value.z))

(fn apply-dir-lights [shader lights]
  (local dir-lights (lights:get-directional))
  (local count (assert-light-count (length dir-lights)
                                   lights.max-dir-lights
                                   "Directional light count"))
  (shader:setInteger "dirLightCount" count)
  (for [i 1 count]
    (local light (. dir-lights i))
    (local idx (tostring (- i 1)))
    (apply-vec3 shader (.. "dirLights[" idx "].direction") light.direction)
    (apply-vec3 shader (.. "dirLights[" idx "].ambient") light.ambient)
    (apply-vec3 shader (.. "dirLights[" idx "].diffuse") light.diffuse)
    (apply-vec3 shader (.. "dirLights[" idx "].specular") light.specular)))

(fn apply-point-lights [shader lights]
  (local point-lights (lights:get-point))
  (local count (assert-light-count (length point-lights)
                                   lights.max-point-lights
                                   "Point light count"))
  (shader:setInteger "pointLightCount" count)
  (for [i 1 count]
    (local light (. point-lights i))
    (local idx (tostring (- i 1)))
    (apply-vec3 shader (.. "pointLights[" idx "].position") light.position)
    (apply-vec3 shader (.. "pointLights[" idx "].ambient") light.ambient)
    (apply-vec3 shader (.. "pointLights[" idx "].diffuse") light.diffuse)
    (apply-vec3 shader (.. "pointLights[" idx "].specular") light.specular)
    (shader:setFloat (.. "pointLights[" idx "].constant") light.constant)
    (shader:setFloat (.. "pointLights[" idx "].linear") light.linear)
    (shader:setFloat (.. "pointLights[" idx "].quadratic") light.quadratic)))

(fn apply-spot-lights [shader lights]
  (local spot-lights (lights:get-spot))
  (local count (assert-light-count (length spot-lights)
                                   lights.max-spot-lights
                                   "Spot light count"))
  (shader:setInteger "spotLightCount" count)
  (for [i 1 count]
    (local light (. spot-lights i))
    (local idx (tostring (- i 1)))
    (apply-vec3 shader (.. "spotLights[" idx "].position") light.position)
    (apply-vec3 shader (.. "spotLights[" idx "].direction") light.direction)
    (apply-vec3 shader (.. "spotLights[" idx "].ambient") light.ambient)
    (apply-vec3 shader (.. "spotLights[" idx "].diffuse") light.diffuse)
    (apply-vec3 shader (.. "spotLights[" idx "].specular") light.specular)
    (shader:setFloat (.. "spotLights[" idx "].cutOff") light.cutoff)
    (shader:setFloat (.. "spotLights[" idx "].outerCutOff") (. light :outer-cutoff))
    (shader:setFloat (.. "spotLights[" idx "].constant") light.constant)
    (shader:setFloat (.. "spotLights[" idx "].linear") light.linear)
    (shader:setFloat (.. "spotLights[" idx "].quadratic") light.quadratic)))

(fn apply-lights [shader lights]
  (assert lights "apply-lights requires a light system")
  (apply-vec3 shader "ambientLight" (lights:get-ambient))
  (apply-dir-lights shader lights)
  (apply-point-lights shader lights)
  (apply-spot-lights shader lights))

{:apply-lights apply-lights}
