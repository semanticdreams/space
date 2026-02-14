(local glm (require :glm))
(local gl (require :gl))

(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local NextAppRenderers (require :next-app/renderers))

(fn clamp-size [value]
  (math.max 1 (math.floor (or value 1))))

(fn NextAppSubApp [opts]
  (local options (or opts {}))
  (local sub-app-options (or options.sub-app-options {}))
  (local size (or options.size (glm.vec2 300 200)))
  (var width (clamp-size (or options.width size.x)))
  (var height (clamp-size (or options.height size.y)))

  (local quad-vector (VectorBuffer))
  (local quad-handle (quad-vector:allocate (* 10 6)))
  (local renderers (NextAppRenderers {:size (glm.vec2 width height)
                                      :renderer-options sub-app-options.renderer-options}))

  (var fbo nil)
  (var rbo nil)
  (var texture nil)
  (var clip-region nil)
  (var depth-offset-index 0)

  (fn delete-framebuffer []
    (when fbo
      (gl.glDeleteFramebuffers fbo)
      (set fbo nil))
    (when rbo
      (gl.glDeleteRenderbuffers rbo)
      (set rbo nil))
    (when (and texture texture.id)
      (gl.glDeleteTextures texture.id))
    (set texture nil))

  (fn create-framebuffer [w h]
    (delete-framebuffer)
    (set fbo (gl.glGenFramebuffers 1))
    (gl.glBindFramebuffer gl.GL_FRAMEBUFFER fbo)
    (local tex (gl.glGenTextures 1))
    (gl.glBindTexture gl.GL_TEXTURE_2D tex)
    (gl.glTexImage2D gl.GL_TEXTURE_2D 0 gl.GL_RGBA w h 0 gl.GL_RGBA gl.GL_UNSIGNED_BYTE nil)
    (gl.glTexParameteri gl.GL_TEXTURE_2D gl.GL_TEXTURE_MIN_FILTER gl.GL_LINEAR)
    (gl.glTexParameteri gl.GL_TEXTURE_2D gl.GL_TEXTURE_MAG_FILTER gl.GL_LINEAR)
    (gl.glFramebufferTexture2D gl.GL_FRAMEBUFFER gl.GL_COLOR_ATTACHMENT0 gl.GL_TEXTURE_2D tex 0)
    (set rbo (gl.glGenRenderbuffers 1))
    (gl.glBindRenderbuffer gl.GL_RENDERBUFFER rbo)
    (gl.glRenderbufferStorage gl.GL_RENDERBUFFER gl.GL_DEPTH_COMPONENT w h)
    (gl.glFramebufferRenderbuffer gl.GL_FRAMEBUFFER
                                  gl.GL_DEPTH_ATTACHMENT
                                  gl.GL_RENDERBUFFER
                                  rbo)
    (gl.checkFramebuffer)
    (gl.glBindFramebuffer gl.GL_FRAMEBUFFER 0)
    (set texture {:id tex
                  :width w
                  :height h
                  :ready true}))

  (fn ensure-framebuffer []
    (when (or (not fbo) (not texture))
      (create-framebuffer width height)))

  (fn set-size [_self w h]
    (local next-width (clamp-size w))
    (local next-height (clamp-size h))
    (when (or (not (= next-width width))
              (not (= next-height height)))
      (set width next-width)
      (set height next-height)
      (create-framebuffer width height))
    (renderers:set-size width height))

  (fn update-quad [_self layout]
    (local position (or layout.position (glm.vec3 0 0 0)))
    (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
    (local size (or layout.size (glm.vec3 width height 0)))
    (set clip-region layout.clip-region)
    (set depth-offset-index (or layout.depth-offset-index 0))
    (local verts
      [[0 0 0] [1 0 0] [1 1 0]
       [0 0 0] [1 1 0] [0 1 0]])
    (local uvs
      [[0 0] [1 0] [1 1]
       [0 0] [1 1] [0 1]])
    (for [i 1 6]
      (local base (glm.vec3 (table.unpack (. verts i))))
      (local scaled (glm.vec3 (* size.x base.x)
                              (* size.y base.y)
                              (* size.z base.z)))
      (local rotated (rotation:rotate scaled))
      (quad-vector.set-glm-vec3
       quad-vector
       quad-handle
       (* (- i 1) 10)
       (+ rotated position))
      (quad-vector.set-glm-vec2
       quad-vector
       quad-handle
       (+ (* (- i 1) 10) 3)
       (glm.vec2 (table.unpack (. uvs i))))
      (quad-vector.set-glm-vec4
       quad-vector
       quad-handle
       (+ (* (- i 1) 10) 5)
       (glm.vec4 1 1 1 1))
      (quad-vector:set-float quad-handle (+ (* (- i 1) 10) 9) depth-offset-index)))

  (fn prerender [_self]
    (ensure-framebuffer)
    (gl.glBindFramebuffer gl.GL_FRAMEBUFFER fbo)
    (gl.glViewport 0 0 width height)
    (gl.glEnable gl.GL_DEPTH_TEST)
    (gl.glDepthFunc gl.GL_LESS)
    (gl.glClearColor 0.03 0.04 0.08 1.0)
    (gl.glClear (bor gl.GL_COLOR_BUFFER_BIT gl.GL_DEPTH_BUFFER_BIT))
    (renderers:prerender)
    (gl.glBindFramebuffer gl.GL_FRAMEBUFFER 0))

  (fn render [_self image-renderer projection-matrix view-matrix]
    (when (and texture texture.ready)
      (image-renderer:render-texture-batch
        {:texture texture
         :vector quad-vector}
        projection-matrix
        view-matrix
        [{:clip clip-region
          :model nil
          :firsts [0]
          :counts [6]}])))

  (fn set-root-transform [_self x y z rotation-z]
    (when renderers.set-root-transform
      (renderers:set-root-transform x y z rotation-z)))

  (fn get-submit-stats [_self]
    (if renderers.get-last-submit-stats
        (renderers:get-last-submit-stats)
        nil))

  (fn drop [_self]
    (delete-framebuffer)
    (quad-vector:delete quad-handle)
    (renderers:drop))

  {:name (or options.name "next-app-sub-app")
   :texture (fn [_self] texture)
   :set-size set-size
   :set-root-transform set-root-transform
   :update-quad update-quad
   :prerender prerender
   :render render
   :get-submit-stats get-submit-stats
   :drop drop})

NextAppSubApp
