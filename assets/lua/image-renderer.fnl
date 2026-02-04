(local glm (require :glm))
(local ClipUtils (require :clip-utils))

(local gl (require :gl))
(local shaders (require :shaders))
(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(fn ImageRenderer []
  (local shader
    (shaders.load-shader-from-files
      "images"
      (app.engine.get-asset-path "shaders/image.vert")
      (app.engine.get-asset-path "shaders/image.frag")))

  (shader:use)
  (shader:setInteger "imageTexture" 0)

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

  (fn resolve-draw-batches [_self texture-batch overrides]
    (local batches (or overrides
                       (and texture-batch texture-batch.draw-batcher
                            (texture-batch.draw-batcher:get-batches))))
    (if (and batches (> (length batches) 0))
        batches
        (if (and texture-batch texture-batch.vector (> (texture-batch.vector:length) 0))
            [{:clip nil
              :model nil
              :firsts [0]
              :counts [(math.floor (/ (texture-batch.vector:length) 10))]}]
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

  (fn render-texture-batch [self texture-batch projection view overrides]
    (when (and texture-batch texture-batch.vector (> (texture-batch.vector:length) 0)
               texture-batch.texture texture-batch.texture.ready)
      (gl.glBindVertexArray vao)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
      (self:upload-vector texture-batch.vector)
      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (gl.glActiveTexture gl.GL_TEXTURE0)
      (gl.glBindTexture gl.GL_TEXTURE_2D texture-batch.texture.id)
      (each [_ draw-batch (ipairs (self:resolve-draw-batches texture-batch overrides))]
        (shader:setMatrix4 "uClipMatrix"
                           (ClipUtils.resolve-matrix draw-batch.clip))
        (shader:setMatrix4 "model"
                           (or draw-batch.model (glm.mat4 1)))
        (gl.glMultiDrawArrays gl.GL_TRIANGLES draw-batch.firsts draw-batch.counts))))

  (fn render [self batches projection view]
    (when (and batches projection view)
      (each [_ batch (pairs batches)]
        (self:render-texture-batch batch projection view nil))))

  {:shader shader
   :resolve-draw-batches resolve-draw-batches
   :upload-vector upload-vector
   :render render
   :render-texture-batch render-texture-batch})
