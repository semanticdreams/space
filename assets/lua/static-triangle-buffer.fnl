(local glm (require :glm))
(local glm-mat4-render-trs (. glm :mat4-render-trs))

(fn model-matrix [position rotation scale offset]
  (local safe-rotation (or rotation (glm.quat 1 0 0 0)))
  (local safe-position (or position (glm.vec3 0 0 0)))
  (local safe-scale (or scale (glm.vec3 1 1 1)))
  (local safe-offset (or offset (glm.vec3 0 0 0)))
  (local translated-position (+ safe-position (safe-rotation:rotate safe-offset)))
  (glm-mat4-render-trs translated-position.x
                       translated-position.y
                       translated-position.z
                       safe-rotation
                       safe-scale.x
                       safe-scale.y
                       safe-scale.z))

(fn StaticTriangleBuffer [ctx opts]
  (assert ctx "StaticTriangleBuffer requires a build context")
  (assert ctx.triangle-vector "StaticTriangleBuffer requires ctx.triangle-vector")
  (local options (or opts {}))
  (local positions (or options.positions []))
  (local colors (or options.colors []))
  (local vertex-count (length positions))
  (local stride (* vertex-count 8))
  (var handle (ctx.triangle-vector:allocate stride))
  (var geometry-state nil)
  (local default-position (or options.position (glm.vec3 0 0 0)))
  (local default-rotation (or options.rotation (glm.quat 1 0 0 0)))
  (local default-scale (or options.scale (glm.vec3 1 1 1)))
  (local default-offset (or options.offset (glm.vec3 0 0 0)))

  (fn ensure-handle []
    (when (not handle)
      (set handle (ctx.triangle-vector:allocate stride))
      (set geometry-state nil)))

  (fn release-handle []
    (when handle
      (when (and ctx ctx.untrack-triangle-handle)
        (ctx:untrack-triangle-handle handle))
      (ctx.triangle-vector:delete handle)
      (set handle nil)
      (set geometry-state nil)))

  (fn write-local-geometry [self]
    (local resolved-opacity (or self.opacity 1.0))
    (local depth-index (or self.depth-offset-index 0))
    (for [i 1 vertex-count]
      (local offset (* (- i 1) 8))
      (ctx.triangle-vector:set-glm-vec3 handle offset (. positions i))
      (local base-color (. colors i))
      (local final-color
        (glm.vec4 base-color.x
                  base-color.y
                  base-color.z
                  (* base-color.w resolved-opacity)))
      (ctx.triangle-vector:set-glm-vec4 handle (+ offset 3) final-color)
      (ctx.triangle-vector:set-float handle (+ offset 7) depth-index)))

  (fn ensure-local-geometry [self]
    (local next-state {:opacity (or self.opacity 1.0)
                       :depth-index (or self.depth-offset-index 0)})
    (when (or (not geometry-state)
              (not (= geometry-state.opacity next-state.opacity))
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
                          (or self.rotation default-rotation)
                          (or self.scale default-scale)
                          (or self.offset default-offset)))
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
   :drop drop
   :set-visible set-visible
   :visible? true
   :position default-position
   :rotation default-rotation
   :scale default-scale
   :offset default-offset
   :opacity (or options.opacity 1.0)
   :depth-offset-index 0
   :clip-region nil})

{:StaticTriangleBuffer StaticTriangleBuffer
 :model-matrix model-matrix}
