(local glm (require :glm))
(local Utils {})

(fn Utils.ensure-glm-vec4 [value fallback]
    (if value
        (if (= (type value) :userdata)
            value
            (glm.vec4 (table.unpack value)))
        (or fallback (glm.vec4 0.5 0.5 0.5 1))))

(fn Utils.ensure-glm-vec3 [value fallback]
    (if value
        (if (= (type value) :userdata)
            value
            (glm.vec3 (table.unpack value)))
        (or fallback (glm.vec3 0 0 0))))

Utils
