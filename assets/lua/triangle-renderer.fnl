(fn TriangleRenderer []
  (local shader (shaders.load_shader "triangles"
                                     (read-file (space.get_asset_path "shaders/triangle.vert"))
                                     (read-file (space.get_asset_path "shaders/triangle.frag"))))

  (local vao (gl.glGenVertexArrays 1))
  (local vbo (gl.glGenBuffers 1))

  (gl.glBindVertexArray vao)
  (shader:use)
  (shader:setVector3f "dirLight.direction" 0.5 0.2 1.0)
  (shader:setVector3f "dirLight.ambient" 0.4 0.4 0.4)
  (shader:setVector3f "dirLight.diffuse" 0.6 0.6 0.6)
  (shader:setVector3f "dirLight.specular" 1.0 1.0 1.0)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
  (gl.glEnableVertexAttribArray 0)
  (gl.glEnableVertexAttribArray 1)
  (gl.glEnableVertexAttribArray 2)
  (local stride (* 8 4))
  (gl.glVertexAttribPointer 0 3 gl.GL_FLOAT gl.GL_FALSE stride 0)
  (gl.glVertexAttribPointer 1 4 gl.GL_FLOAT gl.GL_FALSE stride (* 4 3))
  (gl.glVertexAttribIPointer 2 1 gl.GL_INT stride (* 4 7))

  (fn render [self vector projection view]
   (gl.glBindVertexArray vao)
   (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
   (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
   (shader:use)
   (shader:setMatrix4 "projection" projection)
   (shader:setMatrix4 "view" view)
   (shader:setVector3f "viewPos" (glm.vec3:new 0.0))
   (gl.glDrawArrays gl.GL_TRIANGLES 0 (/ (vector:length) 8))
    )

 {: shader
  : render})

