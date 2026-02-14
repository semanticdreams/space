(local glm (require :glm))

(local mat4-mul glm.mat4-mul)
(local mat4-clip-from-render glm.mat4-clip-from-render)

(fn zero-matrix! [_out]
  (glm.mat4 0))

(fn alloc-matrix []
  (glm.mat4 0))

(fn update-from-render-matrix! [_out render-matrix]
  (if render-matrix
      (mat4-clip-from-render render-matrix)
      (glm.mat4 0)))

(fn compose! [_out parent child]
  (if (and parent child)
      (mat4-mul parent child)
      (or parent child (glm.mat4 0))))

{:alloc-matrix alloc-matrix
 :zero-matrix! zero-matrix!
 :update-from-render-matrix! update-from-render-matrix!
 :compose! compose!}
