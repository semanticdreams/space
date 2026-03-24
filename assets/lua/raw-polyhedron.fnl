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

(fn transform-local-position [position scale rotation local-position]
  (+ position
     (rotation:rotate (+ (* local-position scale)
                         scale))))

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

    (fn ensure-handle []
      (when (not handle)
        (set handle (ctx.triangle-vector:allocate handle-size))))

    (fn release-handle []
      (when handle
        (when (and ctx ctx.untrack-triangle-handle)
          (ctx:untrack-triangle-handle handle))
        (ctx.triangle-vector:delete handle)
        (set handle nil)))

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
            (local position (or self.position default-position))
            (local scale (or self.scale default-scale))
            (local rotation (or self.rotation default-rotation))
            (local depth-index (or self.depth-offset-index 0))
            (var vertex-index 0)
            (each [_ triangle (ipairs triangles)]
              (local color (or triangle.color self.color default-color))
              (write-vertex self vertex-index
                            (transform-local-position position scale rotation triangle.a)
                            color
                            depth-index)
              (write-vertex self (+ vertex-index 1)
                            (transform-local-position position scale rotation triangle.b)
                            color
                            depth-index)
              (write-vertex self (+ vertex-index 2)
                            (transform-local-position position scale rotation triangle.c)
                            color
                            depth-index)
              (set vertex-index (+ vertex-index 3)))
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
