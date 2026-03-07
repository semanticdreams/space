(local glm (require :glm))
(local ClipUtils {})
(local no-clip-matrix (glm.mat4 0))

(fn ClipUtils.matrix-key [matrix]
  (assert (glm.is-mat4 matrix)
          "ClipUtils.matrix-key requires glm.mat4")
  (assert glm.mat4-key "ClipUtils.matrix-key requires glm.mat4-key binding")
  (glm.mat4-key matrix))

(fn clip-matrix-from-bounds [bounds]
  (if (not bounds)
      no-clip-matrix
      (glm.mat4-clip-from-bounds (or bounds.position (glm.vec3 0 0 0))
                                 (or bounds.rotation (glm.quat 1 0 0 0))
                                 (or bounds.size (glm.vec3 1 1 1)))))

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
