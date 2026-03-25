(local glm (require :glm))
(local LightUtils (require :light-utils))

(local gl (require :gl))
(local shaders (require :shaders))

(local vertex-stride 10)
(local instance-stride 16)

(fn InstancedColorMeshRenderer []
  (local shader
    (shaders.load-shader-from-files
      "instanced-color-mesh"
      (app.engine.get-asset-path "shaders/instanced-color-mesh.vert")
      (app.engine.get-asset-path "shaders/instanced-color-mesh.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local vertex-buffer (gl.glGenBuffers 1))
  (local index-buffer (gl.glGenBuffers 1))
  (local instance-buffer (gl.glGenBuffers 1))

  (gl.glBindVertexArray vao)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER vertex-buffer)
  (gl.glBindBuffer gl.GL_ELEMENT_ARRAY_BUFFER index-buffer)
  (local vertex-stride-bytes (* vertex-stride 4))
  (gl.glEnableVertexAttribArray 0)
  (gl.glVertexAttribPointer 0 4 gl.GL_FLOAT gl.GL_FALSE vertex-stride-bytes 0)
  (gl.glEnableVertexAttribArray 1)
  (gl.glVertexAttribPointer 1 3 gl.GL_FLOAT gl.GL_FALSE vertex-stride-bytes (* 4 4))
  (gl.glEnableVertexAttribArray 2)
  (gl.glVertexAttribPointer 2 3 gl.GL_FLOAT gl.GL_FALSE vertex-stride-bytes (* 7 4))

  (gl.glBindBuffer gl.GL_ARRAY_BUFFER instance-buffer)
  (local instance-stride-bytes (* instance-stride 4))
  (for [attrib 0 3]
    (local location (+ 3 attrib))
    (gl.glEnableVertexAttribArray location)
    (gl.glVertexAttribPointer location
                              4
                              gl.GL_FLOAT
                              gl.GL_FALSE
                              instance-stride-bytes
                              (* attrib 16))
    (gl.glVertexAttribDivisor location 1))
  (gl.glBindVertexArray 0)

  (var uploaded-vertex-vector nil)
  (var uploaded-vertex-count nil)
  (var uploaded-index-data nil)
  (var uploaded-index-count nil)
  (var uploaded-instance-vector nil)
  (var uploaded-instance-count nil)
  (var active-instance-first nil)

  (fn upload-vertex-vector [_self vector]
    (local float-count (and vector (vector:length)))
    (when (and float-count (> float-count 0))
      (local needs-full?
        (or (not (= vector uploaded-vertex-vector))
            (not (= float-count uploaded-vertex-count))))
      (if needs-full?
          (do
            (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STATIC_DRAW)
            (set uploaded-vertex-vector vector)
            (set uploaded-vertex-count float-count)
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

  (fn upload-instance-vector [_self vector]
    (local float-count (and vector (vector:length)))
    (when (and float-count (> float-count 0))
      (local needs-full?
        (or (not (= vector uploaded-instance-vector))
            (not (= float-count uploaded-instance-count))))
      (if needs-full?
          (do
            (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
            (set uploaded-instance-vector vector)
            (set uploaded-instance-count float-count)
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

  (fn upload-index-data [_self indices]
    (local count (and indices (length indices)))
    (when (and count (> count 0))
      (when (or (not (= indices uploaded-index-data))
                (not (= count uploaded-index-count)))
        (gl.glBufferDataUInt gl.GL_ELEMENT_ARRAY_BUFFER indices gl.GL_STATIC_DRAW)
        (set uploaded-index-data indices)
        (set uploaded-index-count count))))

  (fn bind-instance-window [_self first]
    (when (not (= first active-instance-first))
      (set active-instance-first first)
      (local base-bytes (* first instance-stride-bytes))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER instance-buffer)
      (for [attrib 0 3]
        (gl.glVertexAttribPointer (+ 3 attrib)
                                  4
                                  gl.GL_FLOAT
                                  gl.GL_FALSE
                                  instance-stride-bytes
                                  (+ base-bytes (* attrib 16))))))

  (fn resolve-batches [_self batch]
    (if (and batch batch.get-instance-batches)
        (batch:get-instance-batches)
        []))

  (fn render-batch [self batch]
    (when (and batch
               (not (= batch.visible? false))
               batch.vertex-vector
               batch.instance-vector
               (> (batch.vertex-vector:length) 0)
               (> (batch.instance-vector:length) 0))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER vertex-buffer)
      (self:upload-vertex-vector batch.vertex-vector)
      (gl.glBindBuffer gl.GL_ELEMENT_ARRAY_BUFFER index-buffer)
      (self:upload-index-data batch.indices)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER instance-buffer)
      (self:upload-instance-vector batch.instance-vector)
      (shader:setInteger "unlit" (if batch.unlit 1 0))
      (local index-count (or batch.index-count (length batch.indices)))
      (each [_ draw-batch (ipairs (self:resolve-batches batch))]
        (for [idx 1 (length draw-batch.firsts)]
          (local first (or (. draw-batch.firsts idx) 0))
          (local count (or (. draw-batch.counts idx) 0))
          (when (> count 0)
            (self:bind-instance-window first)
            (gl.glDrawElementsInstanced gl.GL_TRIANGLES index-count gl.GL_UNSIGNED_INT 0 count))))))

  (fn render [_self batches projection view]
    (when (and batches (> (length batches) 0))
      (gl.glBindVertexArray vao)
      (shader:use)
      (local lights (assert (and app app.lights)
                            "InstancedColorMeshRenderer requires app.lights; call AppBootstrap.init-lights"))
      (LightUtils.apply-lights shader lights)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setVector3f "viewPos" (or (and app app.camera app.camera.position) (glm.vec3 0.0)))
      (each [_ batch (ipairs batches)]
        (render-batch _self batch))))

  {:shader shader
   :render render
   :render-batch render-batch
   :bind-instance-window bind-instance-window
   :resolve-batches resolve-batches
   :upload-vertex-vector upload-vertex-vector
   :upload-index-data upload-index-data
   :upload-instance-vector upload-instance-vector})

InstancedColorMeshRenderer
