(local glm (require :glm))

(local position-magnitude-threshold 1e6)

(fn assert-valid-position [position context]
  (fn finite-number? [v]
    (and (= (type v) :number)
         (= v v)
         (not (= v math.huge))
         (not (= v (- math.huge)))))
  (when (or (not position)
            (not (finite-number? position.x))
            (not (finite-number? position.y))
            (not (finite-number? position.z)))
    (error (string.format "Points received non-finite position in %s"
                          (or context "points"))))
  (local magnitude (glm.length position))
  (when (> magnitude position-magnitude-threshold)
    (error (string.format "Points position magnitude %.3f exceeds threshold %.0f in %s"
                          magnitude
                          position-magnitude-threshold
                          (or context "points")))))

(fn assert-valid-components [x y z context]
  (fn finite-number? [v]
    (and (= (type v) :number)
         (= v v)
         (not (= v math.huge))
         (not (= v (- math.huge)))))
  (when (or (not (finite-number? x))
            (not (finite-number? y))
            (not (finite-number? z)))
    (error (string.format "Points received non-finite position in %s"
                          (or context "points"))))
  (local magnitude (math.sqrt (+ (* x x) (* y y) (* z z))))
  (when (> magnitude position-magnitude-threshold)
    (error (string.format "Points position magnitude %.3f exceeds threshold %.0f in %s"
                          magnitude
                          position-magnitude-threshold
                          (or context "points")))))

(fn resolve-position [position]
  (if position
      (if (= (type position) :userdata)
          position
          (if (= (type position) :table)
              (glm.vec3 (or position.x (rawget position 1) 0)
                        (or position.y (rawget position 2) 0)
                        (or position.z (rawget position 3) 0))
              (if (= (type position) :number)
                  (glm.vec3 position position position)
                  (glm.vec3 0 0 0))))
      (glm.vec3 0 0 0)))

(fn ensure-position [position]
  (resolve-position position))

(fn ensure-color [color]
  (or color (glm.vec4 1 0.2 0.2 1)))

(fn ensure-size [size]
  (or size 10.0))

(fn normalize-direction [direction]
  (if (and direction (> (glm.length direction) 1e-6))
      (glm.normalize direction)
      direction))

(fn point-radius [size]
  (/ (ensure-size size) 2.0))

(fn apply-point [vector handle params]
  (when params.position
    (vector:set-glm-vec3 handle 0 params.position))
  (when params.color
    (vector:set-glm-vec4 handle 3 params.color))
  (when params.size
    (vector:set-float handle 7 params.size))
  (when (not (= params.depth-offset-index nil))
    (vector:set-float handle 8 params.depth-offset-index)))

(fn Points [opts]
  (local vector opts.point-vector)
  (assert vector "Points requires a point-vector to be provided")
  (local default-pointer-target opts.pointer-target)

  (fn new-point [_self params]
    (local options (or params {}))
    (local position (ensure-position options.position))
    (assert-valid-position position "Points.create-point")
    (local color (ensure-color options.color))
    (local size (ensure-size options.size))
    (local pointer-target (or options.pointer-target default-pointer-target))
    (local depth-offset-index (or options.depth-offset-index 0))
    (local handle (vector:allocate 9))
    (apply-point vector handle {:position position
                                :color color
                                :size size
                                :depth-offset-index depth-offset-index})
    (local point {:handle handle
                  :position position
                  :color color
                  :size size
                  :depth-offset-index depth-offset-index
                  :pointer-target pointer-target})
    (setmetatable point {:__newindex (fn [self key value]
                                       (when (= key :position)
                                         (local resolved (ensure-position value))
                                         (assert-valid-position resolved "Points.__newindex")
                                         (rawset self key resolved)
                                         (lua "return"))
                                       (rawset self key value))})
    (set point.set-position (fn [self value]
                              (local resolved (ensure-position value))
                              (assert-valid-position resolved "Points.set-position")
                              (set self.position resolved)
                              (apply-point vector handle {:position resolved})
                              self))
    (set point.set-position-values (fn [self x y z]
                                     (assert-valid-components x y z "Points.set-position-values")
                                     (when (not self.position)
                                       (set self.position (glm.vec3 0 0 0)))
                                     (set self.position.x x)
                                     (set self.position.y y)
                                     (set self.position.z z)
                                     (apply-point vector handle {:position self.position})
                                     self))
    (set point.set-color (fn [self value]
                           (local color (ensure-color value))
                           (set self.color color)
                           (apply-point vector handle {:color color})
                           self))
    (set point.set-size (fn [self value]
                          (local resolved (ensure-size value))
                          (set self.size resolved)
                           (apply-point vector handle {:size resolved})
                           self))
    (set point.set-depth-offset-index
         (fn [self value]
           (local resolved (or value 0))
           (set self.depth-offset-index resolved)
           (apply-point vector handle {:depth-offset-index resolved})
           self))
    (set point.intersect
         (fn [self ray]
           (local direction (normalize-direction (and ray ray.direction)))
           (if (or (not ray) (not ray.origin) (not direction))
               (values false nil nil)
               (let [radius (point-radius self.size)]
                 (if (<= radius 0)
                     (values false nil nil)
                     (let [offset (- ray.origin self.position)
                           a (glm.dot direction direction)
                           half-b (glm.dot offset direction)
                           c (- (glm.dot offset offset) (* radius radius))
                           discriminant (- (* half-b half-b) (* a c))]
                       (if (< discriminant 0)
                           (values false nil nil)
                           (let [sqrt-disc (math.sqrt discriminant)]
                             (var t (/ (- (- half-b) sqrt-disc) a))
                             (when (< t 0)
                               (set t (/ (+ (- half-b) sqrt-disc) a)))
                             (if (< t 0)
                                 (values false nil nil)
                                 (let [hit (+ ray.origin (* direction (glm.vec3 t)))
                                       distance (glm.length (- hit ray.origin))]
                                   (values true hit distance)))))))))))
    (set point.drop (fn [_self]
                      (vector:delete handle)))
    point)

  {:create-point new-point})

Points
