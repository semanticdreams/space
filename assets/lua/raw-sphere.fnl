(local glm (require :glm))
(fn resolve-glm-vec3 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (let [x (or (. value 1) value.x (. value "x") (and fallback fallback.x) 0)
            y (or (. value 2) value.y (. value "y") (and fallback fallback.y) 0)
            z (or (. value 3) value.z (. value "z") (and fallback fallback.z) 0)]
        (glm.vec3 x y z))
    fallback))

(fn RawSphere [opts]
  (local options (or opts {}))
  (set options.color (or options.color (glm.vec4 0.5 0.75 1.0 1.0)))
  (set options.position (resolve-glm-vec3 options.position (glm.vec3 0 0 0)))
  (set options.scale
       (resolve-glm-vec3 options.scale (glm.vec3 (or options.radius 5))))
  (set options.rotation (or options.rotation (glm.quat 1 0 0 0)))
  (local segments (math.max 3 (math.floor (or options.segments 24))))
  (local rings (math.max 2 (math.floor (or options.rings 16))))

  (fn build [ctx]
    (assert ctx "RawSphere requires a build context")
    (assert ctx.triangle-vector "RawSphere requires a triangle-vector in the context")

    (local triangle-count (* segments rings 2))
    (local vertex-count (* triangle-count 3))
    (local handle-size (* vertex-count 8))
    (var handle (ctx.triangle-vector:allocate handle-size))

    (fn ensure-handle []
      (when (not handle)
        (set handle (ctx.triangle-vector:allocate handle-size))))

    (fn release-handle []
      (when handle
        (when (and ctx ctx.untrack-triangle-handle)
          (ctx:untrack-triangle-handle handle))
        (ctx.triangle-vector:delete handle)
        (set handle nil)))

    (fn point-on-sphere [theta phi scale]
      (local sin-theta (math.sin theta))
      (local cos-theta (math.cos theta))
      (local sin-phi (math.sin phi))
      (local cos-phi (math.cos phi))
      (local base (glm.vec3 (* sin-theta cos-phi)
                        cos-theta
                        (* sin-theta sin-phi)))
      (glm.vec3 (* base.x scale.x)
            (* base.y scale.y)
            (* base.z scale.z)))

    (fn to-world [self theta phi scale]
      (local local-pos (point-on-sphere theta phi scale))
      (local shifted (+ local-pos scale))
      (local rotation (or self.rotation (glm.quat 1 0 0 0)))
      (+ self.position (rotation:rotate shifted)))

    (fn write-vertex [_self vertex-index position color depth-index]
      (local offset (* vertex-index 8))
      (ctx.triangle-vector:set-glm-vec3 handle offset position)
      (ctx.triangle-vector:set-glm-vec4 handle (+ offset 3) color)
      (ctx.triangle-vector:set-float handle (+ offset 7) depth-index))

    (fn update [self]
      (if (not self.visible?)
          (release-handle)
          (do
            (ensure-handle)
            (local depth-index (or self.depth-offset-index 0))
            (local color (or self.color options.color))
            (local scale (or self.scale options.scale))
            (local theta-step (/ math.pi rings))
            (local phi-step (/ (* 2 math.pi) segments))
            (var vertex-index 0)
            (for [ring 0 (- rings 1)]
              (local theta-1 (* ring theta-step))
              (local theta-2 (* (+ ring 1) theta-step))
              (for [segment 0 (- segments 1)]
                (local phi-1 (* segment phi-step))
                (local phi-2 (* (+ segment 1) phi-step))
                (local p1 (to-world self theta-1 phi-1 scale))
                (local p2 (to-world self theta-2 phi-1 scale))
                (local p3 (to-world self theta-2 phi-2 scale))
                (local p4 (to-world self theta-1 phi-2 scale))
                (write-vertex self vertex-index p1 color depth-index)
                (write-vertex self (+ vertex-index 1) p2 color depth-index)
                (write-vertex self (+ vertex-index 2) p3 color depth-index)
                (write-vertex self (+ vertex-index 3) p1 color depth-index)
                (write-vertex self (+ vertex-index 4) p3 color depth-index)
                (write-vertex self (+ vertex-index 5) p4 color depth-index)
                (set vertex-index (+ vertex-index 6))))
            (when (and ctx ctx.track-triangle-handle)
              (ctx:track-triangle-handle handle self.clip-region)))))

    (fn set-visible [self visible?]
      (local desired (not (not visible?)))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (if desired
            (ensure-handle)
            (release-handle))))

    (fn drop [_self]
      (release-handle))

    {: update
     :position options.position
     :color options.color
     :scale options.scale
     :rotation options.rotation
     :depth-offset-index 0
     :clip-region nil
     :visible? true
     :set-visible set-visible
     : drop}))

RawSphere
