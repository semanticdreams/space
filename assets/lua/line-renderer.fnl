(local ClipUtils (require :clip-utils))

(local gl (require :gl))
(local shaders (require :shaders))
(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(fn LineRenderer []
  (local shader
    (shaders.load-shader-from-files
      "lines"
      (app.engine.get-asset-path "shaders/line.vert")
      (app.engine.get-asset-path "shaders/line.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local vbo (gl.glGenBuffers 1))

  (gl.glBindVertexArray vao)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
  (gl.glEnableVertexAttribArray 0)
  (gl.glEnableVertexAttribArray 1)
  (local stride (* 6 4))
  (gl.glVertexAttribPointer 0 3 gl.GL_FLOAT gl.GL_FALSE stride 0)
  (gl.glVertexAttribPointer 1 3 gl.GL_FLOAT gl.GL_FALSE stride (* 4 3))

  (fn draw-buffer [_self vector mode projection view]
    (when (and vector (> (vector:length) 0))
      (gl.glBindVertexArray vao)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
      (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setMatrix4 "uClipMatrix" (ClipUtils.no-clip-matrix))
      (gl.glDrawArrays mode 0 (/ (vector:length) 6))))

  (fn render-lines [self vector projection view]
    (self:draw-buffer vector gl.GL_LINES projection view))

  (fn render-line-strips [self vectors projection view]
    (when vectors
      (each [_ vector (ipairs vectors)]
        (self:draw-buffer vector gl.GL_LINE_STRIP projection view))))

  {:shader shader
   :draw-buffer draw-buffer
   :render-lines render-lines
   :render-line-strips render-line-strips})

LineRenderer
