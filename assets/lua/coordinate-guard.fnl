(local default-limit 900000.0)

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn safe-components? [x y z opts]
  (local limit (or (and opts opts.limit) default-limit))
  (and (finite-number? x)
       (finite-number? y)
       (finite-number? z)
       (<= (math.abs x) limit)
       (<= (math.abs y) limit)
       (<= (math.abs z) limit)))

(fn safe-vec3? [value opts]
  (and value
       (safe-components? value.x value.y value.z opts)))

(fn sanitize-vec3 [value fallback opts]
  (if (safe-vec3? value opts)
      value
      fallback))

{:default-limit default-limit
 :finite-number? finite-number?
 :safe-components? safe-components?
 :safe-vec3? safe-vec3?
 :sanitize-vec3 sanitize-vec3}
