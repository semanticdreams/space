(local glm (require :glm))
(local ClipUtils (require :clip-utils))
(local LightUtils (require :light-utils))

(local gl (require :gl))
(local shaders (require :shaders))
(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))

(fn TriangleRenderer []
  (local shader
    (shaders.load-shader-from-files
      "triangles"
      (app.engine.get-asset-path "shaders/triangle.vert")
      (app.engine.get-asset-path "shaders/triangle.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local vbo (gl.glGenBuffers 1))

  (gl.glBindVertexArray vao)
  (shader:use)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
  (gl.glEnableVertexAttribArray 0)
  (gl.glEnableVertexAttribArray 1)
  (gl.glEnableVertexAttribArray 2)
  (local stride (* 8 4))
  (gl.glVertexAttribPointer 0 3 gl.GL_FLOAT gl.GL_FALSE stride 0)
  (gl.glVertexAttribPointer 1 4 gl.GL_FLOAT gl.GL_FALSE stride (* 4 3))
  (gl.glVertexAttribPointer 2 1 gl.GL_FLOAT gl.GL_FALSE stride (* 4 7))

  (fn resolve-batches [_self vector batches]
    (if (and batches (> (length batches) 0))
        batches
        (if (> (vector:length) 0)
            [{:clip nil
              :model nil
              :firsts [0]
              :counts [(math.floor (/ (vector:length) 8))]}]
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

  (fn render [self vector projection view batches]
    (when (and vector (> (vector:length) 0))
      (gl.glBindVertexArray vao)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
      (self:upload-vector vector)
      (shader:use)
      (local lights (assert (and app app.lights)
                            "TriangleRenderer requires app.lights; call AppBootstrap.init-lights"))
      (LightUtils.apply-lights shader lights)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setVector3f "viewPos" (glm.vec3 0.0))
      (each [_ bucket (ipairs (self:resolve-batches vector batches))]
        (shader:setMatrix4 "uClipMatrix"
                           (ClipUtils.resolve-matrix bucket.clip))
        (shader:setMatrix4 "model"
                           (or bucket.model (glm.mat4 1)))
        (gl.glMultiDrawArrays gl.GL_TRIANGLES bucket.firsts bucket.counts))))

 {:shader shader
  :resolve-batches resolve-batches
  :upload-vector upload-vector
  :render render})
