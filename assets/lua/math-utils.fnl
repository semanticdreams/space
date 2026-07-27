(local glm (require :glm))

(fn approx [a b opts]
  (local epsilon (or (and opts opts.epsilon) 1e-4))
  (< (math.abs (- a b)) epsilon))

(fn vec3-approx? [a b opts]
  (and (approx a.x b.x opts)
       (approx a.y b.y opts)
       (approx a.z b.z opts)))

(fn quat-approx? [a b opts]
  (and (approx a.w b.w opts)
       (approx a.x b.x opts)
       (approx a.y b.y opts)
       (approx a.z b.z opts)))

(fn vec3->array [value]
  (assert value "camera position must be set")
  [value.x value.y value.z])

(fn quat->array [value]
  (assert value "camera rotation must be set")
  [value.w value.x value.y value.z])

(fn array->vec3 [value]
  (when (not value)
    (lua "return nil"))
  (assert (= (type value) :table) "camera position must be a table")
  (local x (. value 1))
  (local y (. value 2))
  (local z (. value 3))
  (assert (= (type x) :number) "camera position x must be a number")
  (assert (= (type y) :number) "camera position y must be a number")
  (assert (= (type z) :number) "camera position z must be a number")
  ;; Pre-validate magnitude to keep exception inside the Lua stack.
  ;; The C++ glm.vec3 constructor rejects non-finite components and
  ;; magnitudes > 1e6f (1,000,000).  Mirroring that check here avoids
  ;; a C++ sol2 "An exception occurred" noise line on stderr that is
  ;; invisible to the caller but clutters test output.
  (let [sq (+ (* x x) (* y y) (* z z))]
    (when (or (not= sq sq)        ; NaN check
              (= sq math.huge)     ; inf check
              (> sq 1e12))         ; magnitude > 1e6 (1e6^2 = 1e12)
      (error "vec3 magnitude exceeds threshold")))
  (glm.vec3 x y z))

(fn array->quat [value]
  (when (not value)
    (lua "return nil"))
  (assert (= (type value) :table) "camera rotation must be a table")
  (local w (. value 1))
  (local x (. value 2))
  (local y (. value 3))
  (local z (. value 4))
  (assert (= (type w) :number) "camera rotation w must be a number")
  (assert (= (type x) :number) "camera rotation x must be a number")
  (assert (= (type y) :number) "camera rotation y must be a number")
  (assert (= (type z) :number) "camera rotation z must be a number")
  (glm.quat w x y z))

{:approx approx
 :vec3-approx? vec3-approx?
 :quat-approx? quat-approx?
 :vec3->array vec3->array
 :quat->array quat->array
 :array->vec3 array->vec3
 :array->quat array->quat}
