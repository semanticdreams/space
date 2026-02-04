(local glm (require :glm))
(local ClipUtils {})
(local no-clip-matrix (glm.mat4 0))
(local negative-one (glm.vec3 -1 -1 -1))

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(fn axis-angle-from-glm-quat [rotation]
  (local normalized (rotation:normalize))
  (local w (clamp normalized.w -1 1))
  (local angle (* 2 (math.acos w)))
  (local s (math.sqrt (math.max 0 (- 1 (* w w)))))
  (if (< s 1e-6)
      (values angle (glm.vec3 1 0 0))
      (values angle (glm.vec3 (/ normalized.x s)
                          (/ normalized.y s)
                          (/ normalized.z s)))))

(fn safe-scale [value]
  (if (> (math.abs value) 1e-6)
      (/ 2.0 value)
      1e6))

(fn clip-matrix-from-bounds [bounds]
  (if (not bounds)
      no-clip-matrix
      (let [position (or bounds.position (glm.vec3 0 0 0))
            rotation (or bounds.rotation (glm.quat 1 0 0 0))
            size (or bounds.size (glm.vec3 1 1 1))
            translate-world (glm.translate (glm.mat4 1)
                                           (* position negative-one))
            inverse-rotation (rotation:inverse)
            (angle axis) (axis-angle-from-glm-quat inverse-rotation)
            rotation-matrix (glm.rotate (glm.mat4 1) angle axis)
            center (* size (glm.vec3 0.5 0.5 0.5))
            translate-center (glm.translate (glm.mat4 1)
                                             (* center negative-one))
            scale (glm.scale (glm.mat4 1)
                             (glm.vec3 (safe-scale size.x)
                                   (safe-scale size.y)
                                   1.0))]
        (* scale (* translate-center (* rotation-matrix translate-world))))))

(fn ClipUtils.resolve-matrix [clip]
  (if (and clip clip.bounds)
      (or clip.matrix
          (do
            (set clip.matrix (clip-matrix-from-bounds clip.bounds))
            clip.matrix))
      no-clip-matrix))

(fn ClipUtils.update-region [clip]
  (when clip
    (set clip.matrix (clip-matrix-from-bounds clip.bounds))
    clip))

(fn ClipUtils.no-clip-matrix []
  no-clip-matrix)

ClipUtils
