(local glm (require :glm))
(local Signal (require :signal))

(local scale-vector (fn [v scalar]
                      (* v (glm.vec3 scalar))))

(local quat-from-columns
  (fn [right up forward]
    (local m00 (. right 1))
    (local m01 (. up 1))
    (local m02 (. forward 1))
    (local m10 (. right 2))
    (local m11 (. up 2))
    (local m12 (. forward 2))
    (local m20 (. right 3))
    (local m21 (. up 3))
    (local m22 (. forward 3))
    (local trace (+ m00 m11 m22))
    (var qw 1.0)
    (var qx 0.0)
    (var qy 0.0)
    (var qz 0.0)
    (if (> trace 0)
        (let [s (* 2 (math.sqrt (+ trace 1.0)))]
          (set qw (* 0.25 s))
          (set qx (/ (- m21 m12) s))
          (set qy (/ (- m02 m20) s))
          (set qz (/ (- m10 m01) s)))
        (if (and (> m00 m11) (> m00 m22))
            (let [s (* 2 (math.sqrt (+ 1.0 (- m00 m11) (- m22))))]
              (set qw (/ (+ m21 m12) s))
              (set qx (* 0.25 s))
              (set qy (/ (+ m01 m10) s))
              (set qz (/ (+ m02 m20) s)))
            (if (> m11 m22)
                (let [s (* 2 (math.sqrt (+ 1.0 (- m11 m00) (- m22))))]
                  (set qw (/ (+ m02 m20) s))
                  (set qx (/ (+ m01 m10) s))
                  (set qy (* 0.25 s))
                  (set qz (/ (+ m12 m21) s)))
                (let [s (* 2 (math.sqrt (+ 1.0 (- m22 m00) (- m11))))]
                  (set qw (/ (+ m10 m01) s))
                  (set qx (/ (+ m02 m20) s))
                  (set qy (/ (+ m12 m21) s))
                  (set qz (* 0.25 s)))
                )))
    (local result (glm.quat qw qx qy qz))
    (result:normalize)))

(fn Camera [opts]
  (local options (or opts {}))
  (local debounce-distance (or options.debounce-distance 10.0))
  (local debounce-rotation-epsilon (or options.debounce-rotation-epsilon 1e-4))
  (local debounce-interval (or options.debounce-interval 0.5))
  (var last-debounced-position nil)
  (var last-debounced-rotation nil)
  (var last-debounced-time nil)
  (local self {:position (or options.position (glm.vec3 0 0 0))
               :rotation (or options.rotation (glm.quat 1 0 0 0))
               :view-matrix (glm.mat4 1.0)
               :dirty true
               :changed (Signal)
               :debounced-changed (Signal)})

  (fn quat-dot [a b]
    (+ (* a.w b.w)
       (* a.x b.x)
       (* a.y b.y)
       (* a.z b.z)))

  (fn rotation-changed? [rotation]
    (if (not last-debounced-rotation)
        true
        (> (- 1 (math.abs (quat-dot rotation last-debounced-rotation)))
           debounce-rotation-epsilon)))

  (fn position-changed? [position]
    (if (not last-debounced-position)
        true
        (> (glm.length (- position last-debounced-position)) debounce-distance)))

  (fn emit-debounced [position rotation]
    (set last-debounced-position position)
    (set last-debounced-rotation rotation)
    (set last-debounced-time (os.clock))
    (self.debounced-changed:emit {:position position :rotation rotation}))

  (fn time-elapsed? []
    (if (not last-debounced-time)
        true
        (>= (- (os.clock) last-debounced-time) debounce-interval)))

  (fn maybe-emit-debounced [self]
    (when (or (position-changed? self.position)
              (rotation-changed? self.rotation))
      (when (time-elapsed?)
        (emit-debounced self.position self.rotation))))

  (fn mark-dirty [self]
    (set self.dirty true))

  (fn set-position [self position]
    (set self.position position)
    (self:mark-dirty)
    (maybe-emit-debounced self))

  (fn set-rotation [self rotation]
    (set self.rotation rotation)
    (self:mark-dirty)
    (maybe-emit-debounced self))

  (fn translate [self direction distance]
    (when (not (= distance 0))
      (self:set-position (+ self.position (scale-vector direction distance)))))

  (fn forward [self distance]
    (self:translate (self:get-forward) distance))

  (fn right [self distance]
    (self:translate (self:get-right) distance))

  (fn up [self distance]
    (self:translate (self:get-up) distance))

  (fn yaw [self angle]
    (local q (glm.quat angle (glm.vec3 0 1 0)))
    (local rotation (* q self.rotation))
    (self:set-rotation (rotation:normalize)))

  (fn pitch [self angle]
    (local q (glm.quat angle (glm.vec3 1 0 0)))
    (local rotation (* self.rotation q))
    (self:set-rotation (rotation:normalize)))

  (fn roll [self angle]
    (local q (glm.quat angle (glm.vec3 0 0 1)))
    (local rotation (* self.rotation q))
    (self:set-rotation (rotation:normalize)))

  (fn get-right [self]
    (self.rotation:rotate (glm.vec3 1 0 0)))

  (fn get-up [self]
    (self.rotation:rotate (glm.vec3 0 1 0)))

  (fn get-forward [self]
    (self.rotation:rotate (glm.vec3 0 0 -1)))

  (fn look-at [self target]
    (assert target "Camera.look-at expects a target glm.vec3")
    (local direction (glm.normalize (- target self.position)))
    (local global-up (glm.vec3 0 1 0))
    (var right (glm.cross direction global-up))
    (if (< (glm.length right) 0.0001)
        (set right (glm.vec3 1 0 0))
        (set right (glm.normalize right)))
    (var up (glm.normalize (glm.cross right direction)))
    (local forward (* direction (glm.vec3 -1)))
    (self:set-rotation (quat-from-columns right up forward)))

  (fn update [self]
    (when self.dirty
      (local forward (self:get-forward))
      (local center (+ self.position forward))
      (local up (self:get-up))
      (set self.view-matrix (glm.lookAt self.position center up))
      (set self.dirty false)
      (self.changed:emit {:type :view-matrix :matrix self.view-matrix})))

  (fn get-view-matrix [self]
    (self:update)
    self.view-matrix)

  (fn drop [self]
    (self.changed:clear)
    (self.debounced-changed:clear))

  (set self.mark-dirty mark-dirty)
  (set self.set-position set-position)
  (set self.set-rotation set-rotation)
  (set self.translate translate)
  (set self.forward forward)
  (set self.right right)
  (set self.up up)
  (set self.yaw yaw)
  (set self.pitch pitch)
  (set self.roll roll)
  (set self.get-right get-right)
  (set self.get-up get-up)
  (set self.get-forward get-forward)
  (set self.look-at look-at)
  (set self.update update)
  (set self.get-view-matrix get-view-matrix)
  (set self.drop drop)
  self)

Camera
