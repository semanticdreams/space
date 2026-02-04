(local gl (require :gl))
(local shaders (require :shaders))

(local clamp
  (fn [value min-value max-value]
    (math.min max-value (math.max min-value value))))

(fn to-int [value]
  (math.max 0 (math.floor (or value 0))))

(fn Fxaa []
  (local shader
    (shaders.load-shader-from-files
      "fxaa"
      (app.engine.get-asset-path "shaders/fxaa.vert")
      (app.engine.get-asset-path "shaders/fxaa.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (gl.glBindVertexArray vao)
  (gl.glBindVertexArray 0)

  (local state {:enabled true
                :show-edges false
                :luma-threshold 0.5
                :mul-reduce-reciprocal 8.0
                :min-reduce-reciprocal 128.0
                :max-span 8.0
                :width 0
                :height 0
                :fbo nil
                :depth-rbo nil
                :color-texture nil})

  (fn delete-framebuffer []
    (when state.fbo
      (gl.glDeleteFramebuffers state.fbo)
      (set state.fbo nil))
    (when state.depth-rbo
      (gl.glDeleteRenderbuffers state.depth-rbo)
      (set state.depth-rbo nil))
    (when state.color-texture
      (gl.glDeleteTextures state.color-texture)
      (set state.color-texture nil))
    (set state.width 0)
    (set state.height 0))

  (fn create-framebuffer [width height]
    (delete-framebuffer)
    (when (and (> width 0) (> height 0))
      (local fbo (gl.glGenFramebuffers 1))
      (gl.glBindFramebuffer gl.GL_FRAMEBUFFER fbo)

      (local tex (gl.glGenTextures 1))
      (gl.glBindTexture gl.GL_TEXTURE_2D tex)
      (gl.glTexImage2D gl.GL_TEXTURE_2D 0 gl.GL_RGB width height 0 gl.GL_RGB gl.GL_UNSIGNED_BYTE)
      (gl.glTexParameteri gl.GL_TEXTURE_2D gl.GL_TEXTURE_MIN_FILTER gl.GL_LINEAR)
      (gl.glTexParameteri gl.GL_TEXTURE_2D gl.GL_TEXTURE_MAG_FILTER gl.GL_LINEAR)
      (gl.glTexParameteri gl.GL_TEXTURE_2D gl.GL_TEXTURE_WRAP_S gl.GL_CLAMP_TO_EDGE)
      (gl.glTexParameteri gl.GL_TEXTURE_2D gl.GL_TEXTURE_WRAP_T gl.GL_CLAMP_TO_EDGE)
      (gl.glFramebufferTexture2D gl.GL_FRAMEBUFFER gl.GL_COLOR_ATTACHMENT0 gl.GL_TEXTURE_2D tex 0)

      (local depth-rbo (gl.glGenRenderbuffers 1))
      (gl.glBindRenderbuffer gl.GL_RENDERBUFFER depth-rbo)
      (gl.glRenderbufferStorage gl.GL_RENDERBUFFER gl.GL_DEPTH_COMPONENT width height)
      (gl.glFramebufferRenderbuffer gl.GL_FRAMEBUFFER gl.GL_DEPTH_ATTACHMENT gl.GL_RENDERBUFFER depth-rbo)
      (gl.checkFramebuffer)

      (gl.glBindFramebuffer gl.GL_FRAMEBUFFER 0)
      (set state.fbo fbo)
      (set state.depth-rbo depth-rbo)
      (set state.color-texture tex)
      (set state.width width)
      (set state.height height)))

  (fn on-viewport-changed [_self viewport]
    (local width (to-int (and viewport viewport.width)))
    (local height (to-int (and viewport viewport.height)))
    (if (or (not (= width state.width)) (not (= height state.height)))
        (create-framebuffer width height)))

  (fn ready? [_self]
    (and state.fbo state.color-texture (> state.width 0) (> state.height 0)))

  (fn render [_self]
    (when (ready? _self)
      (shader:use)
      (shader:setInteger "u_colorTexture" 0)
      (shader:setVector2f "u_texelStep" (/ 1.0 state.width) (/ 1.0 state.height))
      (shader:setInteger "u_showEdges" (if state.show-edges 1 0))
      (shader:setInteger "u_fxaaOn" (if state.enabled 1 0))
      (shader:setFloat "u_lumaThreshold" (clamp state.luma-threshold 0.0 1.0))
      (shader:setFloat "u_mulReduce" (/ 1.0 (math.max 1.0 state.mul-reduce-reciprocal)))
      (shader:setFloat "u_minReduce" (/ 1.0 (math.max 1.0 state.min-reduce-reciprocal)))
      (shader:setFloat "u_maxSpan" (clamp state.max-span 1.0 16.0))
      (gl.glBindVertexArray vao)
      (gl.glActiveTexture gl.GL_TEXTURE0)
      (gl.glBindTexture gl.GL_TEXTURE_2D state.color-texture)
      (gl.glDrawArrays gl.GL_TRIANGLE_STRIP 0 4)))

  (fn drop [_self]
    (delete-framebuffer)
    (gl.glDeleteVertexArrays vao))

  (fn set-enabled [_self value]
    (set state.enabled (not (= value false))))

  (fn set-show-edges [_self value]
    (set state.show-edges (not (= value false))))

  (fn set-luma-threshold [_self value]
    (set state.luma-threshold (clamp value 0.0 1.0)))

  (fn set-mul-reduce-reciprocal [_self value]
    (set state.mul-reduce-reciprocal (clamp value 1.0 256.0)))

  (fn set-min-reduce-reciprocal [_self value]
    (set state.min-reduce-reciprocal (clamp value 1.0 512.0)))

  (fn set-max-span [_self value]
    (set state.max-span (clamp value 1.0 16.0)))

  (fn get-fbo [_self] state.fbo)
  (fn get-depth-rbo [_self] state.depth-rbo)
  (fn get-width [_self] state.width)
  (fn get-height [_self] state.height)

  {:render render
   :drop drop
   :ready? ready?
   :on-viewport-changed on-viewport-changed
   :set-enabled set-enabled
   :set-show-edges set-show-edges
   :set-luma-threshold set-luma-threshold
   :set-mul-reduce-reciprocal set-mul-reduce-reciprocal
   :set-min-reduce-reciprocal set-min-reduce-reciprocal
   :set-max-span set-max-span
   :get-fbo get-fbo
   :get-depth-rbo get-depth-rbo
   :get-width get-width
   :get-height get-height})

Fxaa
