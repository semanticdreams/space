(local glm (require :glm))
(local ClipUtils (require :clip-utils))
(local LightUtils (require :light-utils))
(local LightingViewState (require :lighting-view-state))

(local gl (require :gl))
(local shaders (require :shaders))
(local VectorUploadCache (require :vector-upload-cache))

(fn TriangleRenderer []
  (local shader
    (shaders.load-shader-from-files
      "triangles"
      (app.engine.get-asset-path "shaders/triangle.vert")
      (app.engine.get-asset-path "shaders/triangle.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local upload-cache (VectorUploadCache {:usage gl.GL_STREAM_DRAW
                                          :max-entries 64
                                          :evict-per-upload 1}))

  (gl.glBindVertexArray vao)
  (shader:use)
  (gl.glEnableVertexAttribArray 0)
  (gl.glEnableVertexAttribArray 1)
  (gl.glEnableVertexAttribArray 2)
  (local stride (* 8 4))

  (fn configure-attributes []
    (gl.glVertexAttribPointer 0 3 gl.GL_FLOAT gl.GL_FALSE stride 0)
    (gl.glVertexAttribPointer 1 4 gl.GL_FLOAT gl.GL_FALSE stride (* 4 3))
    (gl.glVertexAttribPointer 2 1 gl.GL_FLOAT gl.GL_FALSE stride (* 4 7)))

  (fn resolve-batches [_self vector batches]
    (if (and batches (> (length batches) 0))
        batches
        (if (> (vector:length) 0)
            [{:clip nil
              :model nil
              :firsts [0]
              :counts [(math.floor (/ (vector:length) 8))]}]
            [])))

  (fn upload-vector [_self vector]
    (upload-cache:upload vector configure-attributes))

  (fn render [self vector projection view lighting-view-state batches]
    (when (and vector (> (vector:length) 0))
      (gl.glBindVertexArray vao)
      (self:upload-vector vector)
      (shader:use)
      (local lights (assert (and app app.lights)
                            "TriangleRenderer requires app.lights; call AppBootstrap.init-lights"))
      (LightUtils.apply-lights shader lights)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (LightingViewState.apply-uniforms shader
                                        (assert lighting-view-state
                                                "TriangleRenderer.render requires lighting-view-state"))
      (each [_ bucket (ipairs (self:resolve-batches vector batches))]
        (shader:setMatrix4 "uClipMatrix"
                           (ClipUtils.resolve-matrix bucket.clip))
        (shader:setMatrix4 "model"
                           (or bucket.model (glm.mat4 1)))
        (gl.glMultiDrawArrays gl.GL_TRIANGLES bucket.firsts bucket.counts))))

  (fn drop [_self]
    (upload-cache:drop)
    (gl.glDeleteVertexArrays vao))

 {:shader shader
  :resolve-batches resolve-batches
  :upload-vector upload-vector
  :render render
  :drop drop})
