(local glm (require :glm))
(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(fn ensure-points [points]
  (if (and points (>= (length points) 2))
      points
      [(glm.vec3 0 0 0) (glm.vec3 1 0 0)]))

(fn ensure-color [color]
  (or color (glm.vec3 1 1 1)))

(fn Lines [opts]
  (local line-vector opts.line-vector)
  (local register-line-strip opts.register-line-strip)
  (local unregister-line-strip opts.unregister-line-strip)
  (assert line-vector "Lines requires a line-vector to be provided")

  (fn apply-line [handle params]
    (when params.start
      (line-vector:set-glm-vec3 handle 0 params.start))
    (when params.color
      (line-vector:set-glm-vec3 handle 3 params.color)
      (line-vector:set-glm-vec3 handle 9 params.color))
    (when params.end
      (line-vector:set-glm-vec3 handle 6 params.end)))

  (fn new-line [_self params]
    (local defaults {:start (or params.start (glm.vec3 0 0 0))
                     :end (or params.end (glm.vec3 0 1 0))
                     :color (ensure-color params.color)})
    (local handle (line-vector:allocate 12))
    (apply-line handle defaults)
    (local line {:handle handle
                 :start defaults.start
                 :end defaults.end
                 :color defaults.color})
    (set line.set-start (fn [self value]
                          (set self.start value)
                          (apply-line handle {:start value})
                          self))
    (set line.set-end (fn [self value]
                        (set self.end value)
                        (apply-line handle {:end value})
                        self))
    (set line.set-color (fn [self value]
                          (local color (ensure-color value))
                          (set self.color color)
                          (apply-line handle {:color color})
                          self))
    (set line.drop (fn [_self]
                     (line-vector:delete handle)))
    line)

  (assert register-line-strip "Lines.create-line-strip requires register-line-strip support")
  (assert unregister-line-strip "Lines.create-line-strip requires unregister-line-strip support")

  (fn write-strip-points [vector handle points color]
    (local count (length points))
    (vector:reallocate handle (* count 6))
    (for [i 1 count]
      (local offset (* (- i 1) 6))
      (vector:set-glm-vec3 handle offset (. points i))
      (vector:set-glm-vec3 handle (+ offset 3) color)))

  (fn rewrite-strip-color [vector handle count color]
    (for [i 0 (- count 1)]
      (vector:set-glm-vec3 handle (+ 3 (* i 6)) color)))

  (fn new-line-strip [_self params]
    (local vector (VectorBuffer))
    (local handle (vector:allocate 12))
    (local initial-color (ensure-color params.color))
    (local initial-points (ensure-points params.points))
    (register-line-strip vector)
    (write-strip-points vector handle initial-points initial-color)
    (local strip {:vector vector
                  :handle handle
                  :color initial-color
                  :points initial-points
                  :count (length initial-points)})
    (set strip.set-points (fn [self points]
                            (local resolved (ensure-points points))
                            (write-strip-points vector handle resolved self.color)
                            (set self.points resolved)
                            (set self.count (length resolved))
                            self))
    (set strip.set-color (fn [self color]
                           (local resolved (ensure-color color))
                           (set self.color resolved)
                           (rewrite-strip-color vector handle self.count resolved)
                           self))
    (set strip.drop (fn [self]
                      (vector:delete handle)
                      (unregister-line-strip vector)))
    strip)

  {:create-line new-line
   :create-line-strip new-line-strip})

Lines
