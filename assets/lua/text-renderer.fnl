(fn TextRenderer []
  (local shader
    (shaders.load_shader
      "msdf"
      (read-file (space.get_asset_path "shaders/msdf.vert"))
      (read-file (space.get_asset_path "shaders/msdf.frag"))))


  (local vao (gl.glGenVertexArrays 1))
  (local vbo (gl.glGenBuffers 1))

  (gl.glBindVertexArray vao)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)

  (local stride (* 10 4))

  (gl.glEnableVertexAttribArray 0)
  (gl.glVertexAttribPointer 0 3 gl.GL_FLOAT gl.GL_FALSE stride 0)

  (gl.glEnableVertexAttribArray 1)
  (gl.glVertexAttribPointer 1 2 gl.GL_FLOAT gl.GL_FALSE stride (* 3 4))

  (gl.glEnableVertexAttribArray 2)
  (gl.glVertexAttribPointer 2 4 gl.GL_FLOAT gl.GL_FALSE stride (* 5 4))

  (gl.glEnableVertexAttribArray 3)
  (gl.glVertexAttribPointer 3 1 gl.GL_INT gl.GL_FALSE stride (* 9 4))

  (fn render [self vector font projection view]
    (gl.glBindVertexArray vao)
    (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
    (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
    (shader:use)
    (shader:setMatrix4 "projection" projection)
    (shader:setMatrix4 "view" view)
    (shader:setFloat "pxRange" font.meta.atlas.distanceRange) ; TODO check this, json

    (gl.glActiveTexture gl.GL_TEXTURE0)
    (gl.glBindTexture gl.GL_TEXTURE_2D font.texture)

    (gl.glDrawArrays gl.GL_TRIANGLES 0 (/ (vector:length) 10))
    )
  {: shader : render}
  )
