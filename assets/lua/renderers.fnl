(local TriangleRenderer (require :triangle-renderer))

(fn Renderers []
  (local scene-triangle-vector (VectorBuffer.new))
  (local triangle-renderer (TriangleRenderer))
  
  (local perspective (glm.perspective -5.0 2.0 10 2000.0))
  (local view (glm.translate (glm.mat4:new 1.0) (glm.vec3:new 0 0 -10)))

  (fn update [self]
    (triangle-renderer:render scene-triangle-vector perspective view))

  {: scene-triangle-vector
   : update
   })

