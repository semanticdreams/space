(local glm (require :glm))

(fn resolve-glm-vec3 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (do
        (local x (or (. value 1) value.x (. value "x") (and fallback fallback.x) 0))
        (local y (or (. value 2) value.y (. value "y") (and fallback fallback.y) 0))
        (local z (or (. value 3) value.z (. value "z") (and fallback fallback.z) 0))
        (glm.vec3 x y z))
    fallback))

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(fn axis-angle-from-quat [rotation]
  (local safe-rotation (or rotation (glm.quat 1 0 0 0)))
  (local normalized (safe-rotation:normalize))
  (local w (clamp normalized.w -1 1))
  (local angle (* 2 (math.acos w)))
  (local s (math.sqrt (math.max 0 (- 1 (* w w)))))
  (if (< s 1e-6)
      (values angle (glm.vec3 1 0 0))
      (values angle (glm.vec3 (/ normalized.x s)
                              (/ normalized.y s)
                              (/ normalized.z s)))))

(fn model-matrix [position scale rotation]
  (local translate (glm.translate (glm.mat4 1) (or position (glm.vec3 0 0 0))))
  (local (angle axis) (axis-angle-from-quat rotation))
  (local rotate (glm.rotate (glm.mat4 1) angle axis))
  (local scale-mat (glm.scale (glm.mat4 1) (or scale (glm.vec3 1 1 1))))
  (local offset (glm.translate (glm.mat4 1) (or scale (glm.vec3 1 1 1))))
  (* translate (* rotate (* offset scale-mat))))

(fn RawPolyhedron [opts]
  (local options (or opts {}))
  (local triangles (or options.triangles []))
  (local default-color (or options.color (glm.vec4 1 1 1 1)))
  (local default-position (resolve-glm-vec3 options.position (glm.vec3 0 0 0)))
  (local default-scale (resolve-glm-vec3 options.scale (glm.vec3 1 1 1)))
  (local default-rotation (or options.rotation (glm.quat 1 0 0 0)))

  (fn build [ctx]
    (assert ctx "RawPolyhedron requires a build context")
    (assert ctx.triangle-vector "RawPolyhedron requires a triangle-vector in the context")

    (local vertex-count (* (length triangles) 3))
    (local handle-size (* vertex-count 8))
    (var handle (ctx.triangle-vector:allocate handle-size))
    (var geometry-state nil)

    (fn ensure-handle []
      (when (not handle)
        (set handle (ctx.triangle-vector:allocate handle-size))
        (set geometry-state nil)))

    (fn release-handle []
      (when handle
        (when (and ctx ctx.untrack-triangle-handle)
          (ctx:untrack-triangle-handle handle))
        (ctx.triangle-vector:delete handle)
        (set handle nil)
        (set geometry-state nil)))

    (fn write-vertex [_self vertex-index position color depth-index]
      (local offset (* vertex-index 8))
      (ctx.triangle-vector:set-glm-vec3 handle offset position)
      (ctx.triangle-vector:set-glm-vec4 handle (+ offset 3) color)
      (ctx.triangle-vector:set-float handle (+ offset 7) depth-index))

    (fn write-local-geometry [self]
      (local depth-index (or self.depth-offset-index 0))
      (var vertex-index 0)
      (each [_ triangle (ipairs triangles)]
        (local color (or triangle.color self.color default-color))
        (write-vertex self vertex-index triangle.a color depth-index)
        (write-vertex self (+ vertex-index 1) triangle.b color depth-index)
        (write-vertex self (+ vertex-index 2) triangle.c color depth-index)
        (set vertex-index (+ vertex-index 3))))

    (fn ensure-local-geometry [self]
      (local next-state {:color self.color
                         :depth-index (or self.depth-offset-index 0)})
      (when (or (not geometry-state)
                (not (= geometry-state.color next-state.color))
                (not (= geometry-state.depth-index next-state.depth-index)))
        (write-local-geometry self)
        (set geometry-state next-state)))

    (fn update [self]
      (if (not self.visible?)
          (release-handle)
          (do
            (ensure-handle)
            (ensure-local-geometry self)
            (local model
              (model-matrix (or self.position default-position)
                            (or self.scale default-scale)
                            (or self.rotation default-rotation)))
            (when (and ctx ctx.track-triangle-handle)
              (ctx:track-triangle-handle handle self.clip-region model)))))

    (fn set-visible [self visible?]
      (local desired (not (not visible?)))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (if desired
            (ensure-handle)
            (release-handle))))

    (fn drop [_self]
      (release-handle))

    {:update update
     :position default-position
     :scale default-scale
     :rotation default-rotation
     :color default-color
     :depth-offset-index 0
     :clip-region nil
     :visible? true
     :set-visible set-visible
     :drop drop}))

RawPolyhedron
