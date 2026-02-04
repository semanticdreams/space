(local gl (require :gl))
(local glm (require :glm))
(local shaders (require :shaders))

(local terrain-center (glm.vec3 0 -100 0))
(local light-position (glm.vec3 200 200 200))
(local light-direction (glm.normalize (- light-position terrain-center)))

(fn MeshRenderer []
  (local shader
    (shaders.load-shader-from-files
      "mesh"
      (app.engine.get-asset-path "shaders/mesh.vert")
      (app.engine.get-asset-path "shaders/mesh.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local vbo (gl.glGenBuffers 1))

  (gl.glBindVertexArray vao)
  (shader:use)
  (shader:setInteger "myTexture" 0)
  (shader:setVector3f "dirLight.direction" light-direction)
  (shader:setVector3f "dirLight.ambient" 0.4 0.4 0.4)
  (shader:setVector3f "dirLight.diffuse" 0.6 0.6 0.6)
  (shader:setVector3f "dirLight.specular" 1.0 1.0 1.0)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
  (gl.glEnableVertexAttribArray 0)
  (gl.glEnableVertexAttribArray 1)
  (gl.glEnableVertexAttribArray 2)
  (local stride (* 8 4))
  (gl.glVertexAttribPointer 0 2 gl.GL_FLOAT gl.GL_FALSE stride 0)
  (gl.glVertexAttribPointer 1 3 gl.GL_FLOAT gl.GL_FALSE stride (* 4 2))
  (gl.glVertexAttribPointer 2 3 gl.GL_FLOAT gl.GL_FALSE stride (* 4 5))

  (fn render [_self batches projection view]
    (when (and batches (> (length batches) 0))
      (gl.glBindVertexArray vao)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setVector3f "viewPos" (glm.vec3 0.0))
      (each [_ batch (ipairs batches)]
        (when (not (= batch.visible? false))
          (local vector batch.vector)
          (when (and vector (> (vector:length) 0))
            (local texture batch.texture)
            (assert (and texture texture.id)
                    "Mesh renderer requires a texture with an id")
            (when (or (= texture.ready nil) texture.ready)
              (shader:setMatrix4 "model" (or batch.model (glm.mat4 1)))
              (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
              (gl.glActiveTexture gl.GL_TEXTURE0)
              (gl.glBindTexture gl.GL_TEXTURE_2D texture.id)
              (gl.glDrawArrays gl.GL_TRIANGLES 0 (/ (vector:length) 8))))))))

  {:shader shader
   :render render})

MeshRenderer
