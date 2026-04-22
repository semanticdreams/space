(local ClipUtils (require :clip-utils))

(local gl (require :gl))
(local shaders (require :shaders))
(local VectorUploadCache (require :vector-upload-cache))
(fn LineRenderer []
  (local shader
    (shaders.load-shader-from-files
      "lines"
      (app.engine.get-asset-path "shaders/line.vert")
      (app.engine.get-asset-path "shaders/line.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local upload-cache (VectorUploadCache {:usage gl.GL_STREAM_DRAW
                                          :max-entries 128
                                          :evict-per-upload 1}))

  (gl.glBindVertexArray vao)
  (gl.glEnableVertexAttribArray 0)
  (gl.glEnableVertexAttribArray 1)
  (local stride (* 7 4))

  (fn configure-attributes []
    (gl.glVertexAttribPointer 0 3 gl.GL_FLOAT gl.GL_FALSE stride 0)
    (gl.glVertexAttribPointer 1 4 gl.GL_FLOAT gl.GL_FALSE stride (* 4 3)))

  (fn upload-vector [_self vector]
    (upload-cache:upload vector configure-attributes))

  (fn draw-buffer [self vector mode projection view]
    (when (and vector (> (vector:length) 0))
      (gl.glBindVertexArray vao)
      (self:upload-vector vector)
      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setMatrix4 "uClipMatrix" (ClipUtils.no-clip-matrix))
      (gl.glDrawArrays mode 0 (/ (vector:length) 7))))

  (fn render-lines [self vector projection view]
    (self:draw-buffer vector gl.GL_LINES projection view))

  (fn render-line-strips [self vectors projection view]
    (when vectors
      (each [_ vector (ipairs vectors)]
        (self:draw-buffer vector gl.GL_LINE_STRIP projection view))))

  (fn drop [_self]
    (upload-cache:drop)
    (gl.glDeleteVertexArrays vao))

  {:shader shader
   :upload-vector upload-vector
   :draw-buffer draw-buffer
   :render-lines render-lines
   :render-line-strips render-line-strips
   :drop drop})

LineRenderer
