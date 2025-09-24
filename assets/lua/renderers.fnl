(local TriangleRenderer (require :triangle-renderer))
(local TextRenderer (require :text-renderer))

(fn Renderers []
  (local scene-triangle-vector (VectorBuffer.new))
  (local triangle-renderer (TriangleRenderer))

  (local scene-text-vectors {})
  (local text-renderer (TextRenderer))

  (local perspective (glm.perspective -5.0 2.0 10 2000.0))
  (local view (glm.translate (mat4 1.0) (vec3 0 0 -10)))

  (fn update [self]
    (gl.glBindFramebuffer gl.GL_FRAMEBUFFER space.fbo)
    (gl.glDisable gl.GL_CULL_FACE)
    (gl.glEnable gl.GL_DEPTH_TEST)
    (gl.glDepthFunc gl.GL_LESS)
    (gl.glClearColor 0.1 0.2 0.3 1.0)
    (gl.glClear (bor gl.GL_COLOR_BUFFER_BIT gl.GL_DEPTH_BUFFER_BIT))
    (triangle-renderer:render scene-triangle-vector perspective view))

  {: scene-triangle-vector
   : update
   })

