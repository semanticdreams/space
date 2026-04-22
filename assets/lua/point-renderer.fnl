(local ClipUtils (require :clip-utils))

(local gl (require :gl))
(local shaders (require :shaders))
(local VectorUploadCache (require :vector-upload-cache))
(fn PointRenderer []
  (local shader
    (shaders.load-shader-from-files
      "points"
      (app.engine.get-asset-path "shaders/point.vert")
      (app.engine.get-asset-path "shaders/point.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local quad-buffer (gl.glGenBuffers 1))
  (local upload-cache (VectorUploadCache {:usage gl.GL_STREAM_DRAW
                                          :max-entries 64
                                          :evict-per-upload 1}))

  (gl.glBindVertexArray vao)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER quad-buffer)
  (gl.glBufferData gl.GL_ARRAY_BUFFER
                   [-0.5 -0.5
                    0.5 -0.5
                    -0.5 0.5
                    0.5 0.5]
                   gl.GL_STATIC_DRAW)
  (gl.glEnableVertexAttribArray 0)
  (gl.glVertexAttribPointer 0 2 gl.GL_FLOAT gl.GL_FALSE (* 2 4) 0)

  (local stride (* 9 4))
  (gl.glEnableVertexAttribArray 1)
  (gl.glVertexAttribDivisor 1 1)
  (gl.glEnableVertexAttribArray 2)
  (gl.glVertexAttribDivisor 2 1)
  (gl.glEnableVertexAttribArray 3)
  (gl.glVertexAttribDivisor 3 1)
  (gl.glEnableVertexAttribArray 4)
  (gl.glVertexAttribDivisor 4 1)

  (gl.glBindVertexArray 0)

  (fn configure-instance-attributes []
    (gl.glVertexAttribPointer 1 3 gl.GL_FLOAT gl.GL_FALSE stride 0)
    (gl.glVertexAttribPointer 2 4 gl.GL_FLOAT gl.GL_FALSE stride (* 4 3))
    (gl.glVertexAttribPointer 3 1 gl.GL_FLOAT gl.GL_FALSE stride (* 4 7))
    (gl.glVertexAttribPointer 4 1 gl.GL_FLOAT gl.GL_FALSE stride (* 4 8)))

  (fn render [_self vector projection view]
    (when (and vector (> (vector:length) 0))
      (gl.glBindVertexArray vao)
      (upload-cache:upload vector configure-instance-attributes)
      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setMatrix4 "uClipMatrix" (ClipUtils.no-clip-matrix))
      (gl.glDrawArraysInstanced gl.GL_TRIANGLE_STRIP 0 4 (/ (vector:length) 9))))

  (fn drop [_self]
    (upload-cache:drop)
    (gl.glDeleteBuffers quad-buffer)
    (gl.glDeleteVertexArrays vao))

  {:render render
   :drop drop})

PointRenderer
