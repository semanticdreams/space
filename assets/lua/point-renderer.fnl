(local ClipUtils (require :clip-utils))

(local gl (require :gl))
(local shaders (require :shaders))
(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(fn PointRenderer []
  (local shader
    (shaders.load-shader-from-files
      "points"
      (app.engine.get-asset-path "shaders/point.vert")
      (app.engine.get-asset-path "shaders/point.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local quad-buffer (gl.glGenBuffers 1))
  (local instance-buffer (gl.glGenBuffers 1))

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

  (gl.glBindBuffer gl.GL_ARRAY_BUFFER instance-buffer)
  (local stride (* 9 4))
  (gl.glEnableVertexAttribArray 1)
  (gl.glVertexAttribPointer 1 3 gl.GL_FLOAT gl.GL_FALSE stride 0)
  (gl.glVertexAttribDivisor 1 1)
  (gl.glEnableVertexAttribArray 2)
  (gl.glVertexAttribPointer 2 4 gl.GL_FLOAT gl.GL_FALSE stride (* 4 3))
  (gl.glVertexAttribDivisor 2 1)
  (gl.glEnableVertexAttribArray 3)
  (gl.glVertexAttribPointer 3 1 gl.GL_FLOAT gl.GL_FALSE stride (* 4 7))
  (gl.glVertexAttribDivisor 3 1)
  (gl.glEnableVertexAttribArray 4)
  (gl.glVertexAttribPointer 4 1 gl.GL_FLOAT gl.GL_FALSE stride (* 4 8))
  (gl.glVertexAttribDivisor 4 1)

  (gl.glBindVertexArray 0)

  (fn render [_self vector projection view]
    (when (and vector (> (vector:length) 0))
      (gl.glBindVertexArray vao)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER instance-buffer)
      (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setMatrix4 "uClipMatrix" (ClipUtils.no-clip-matrix))
      (gl.glDrawArraysInstanced gl.GL_TRIANGLE_STRIP 0 4 (/ (vector:length) 9))))

  {:render render})

PointRenderer
