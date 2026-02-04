(local glm (require :glm))
(local ClipUtils (require :clip-utils))

(local gl (require :gl))
(local shaders (require :shaders))
(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(fn TextRenderer []
  (local shader
    (shaders.load-shader-from-files
      "msdf"
      (app.engine.get-asset-path "shaders/msdf.vert")
      (app.engine.get-asset-path "shaders/msdf.frag")))


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
  (gl.glVertexAttribPointer 3 1 gl.GL_FLOAT gl.GL_FALSE stride (* 9 4))

  (fn resolve-batches [_self vector batches]
    (if (and batches (> (length batches) 0))
        batches
        (if (> (vector:length) 0)
            [{:clip nil
              :model nil
              :firsts [0]
              :counts [(math.floor (/ (vector:length) 10))]}]
            [])))

  (var uploaded-vector nil)
  (var uploaded-floats 0)
  (fn upload-vector [_self vector]
    (local float-count (and vector (vector:length)))
    (when (and float-count (> float-count 0))
      (local needs-full?
        (or (not (= vector uploaded-vector))
            (not (= float-count uploaded-floats))))
      (if needs-full?
          (do
            (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
            (set uploaded-vector vector)
            (set uploaded-floats float-count)
            (when (. vector :clear-dirty)
              (vector:clear-dirty)))
          (do
            (var dirty-from nil)
            (var dirty-to nil)
            (when (. vector :dirty-range)
              (local (from to) (vector:dirty-range))
              (set dirty-from from)
              (set dirty-to to))
            (when (and dirty-from dirty-to (> dirty-to dirty-from))
              (gl.bufferSubDataFromVectorBuffer
                vector
                gl.GL_ARRAY_BUFFER
                (* dirty-from 4)
                (* (- dirty-to dirty-from) 4))
              (when (. vector :clear-dirty)
                (vector:clear-dirty)))))))

  (fn render [self vector font projection view batches]
    (when (and vector (> (vector:length) 0) font font.texture font.texture.ready)
      (gl.glBindVertexArray vao)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
      (self:upload-vector vector)
      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setFloat "pxRange" font.metadata.atlas.distanceRange)

      (gl.glActiveTexture gl.GL_TEXTURE0)
      (gl.glBindTexture gl.GL_TEXTURE_2D font.texture.id)

      (each [_ batch (ipairs (self:resolve-batches vector batches))]
        (shader:setMatrix4 "uClipMatrix"
                           (ClipUtils.resolve-matrix batch.clip))
        (shader:setMatrix4 "model"
                           (or batch.model (glm.mat4 1)))
        (gl.glMultiDrawArrays gl.GL_TRIANGLES batch.firsts batch.counts))))
  {:shader shader
   :resolve-batches resolve-batches
   :upload-vector upload-vector
   :render render})
