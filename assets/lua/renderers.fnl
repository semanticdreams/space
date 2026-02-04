(local TriangleRenderer (require :triangle-renderer))
(local LineRenderer (require :line-renderer))
(local PointRenderer (require :point-renderer))
(local TextRenderer (require :text-renderer))
(local ImageRenderer (require :image-renderer))
(local MeshRenderer (require :mesh-renderer))
(local SkyboxRenderer (require :skybox-renderer))
(local Fxaa (require :fxaa))

(local gl (require :gl))

(fn bool-option [options key default-value]
  (if (or (not options) (= (. options key) nil))
      default-value
      (not (= (. options key) false))))

(fn to-int [value]
  (math.max 0 (math.floor (or value 0))))

(fn Renderers []
  (local triangle-renderer (TriangleRenderer))
  (local line-renderer (LineRenderer))
  (local point-renderer (PointRenderer))
  (local text-renderer (TextRenderer))
  (local image-renderer (ImageRenderer))
  (local mesh-renderer (MeshRenderer))
  (local skybox-renderer (SkyboxRenderer {:brightness 0.1}))
  (local fxaa (Fxaa))
  (var sub-apps [])

  (var final-fbo nil)
  (var final-rbo nil)
  (var final-width 0)
  (var final-height 0)

  (fn delete-final-fbo []
    (when final-fbo
      (gl.glDeleteFramebuffers final-fbo)
      (set final-fbo nil))
    (when final-rbo
      (gl.glDeleteRenderbuffers final-rbo)
      (set final-rbo nil))
    (set final-width 0)
    (set final-height 0))

  (fn create-final-fbo [viewport]
    (delete-final-fbo)
    (local width (to-int (and viewport viewport.width)))
    (local height (to-int (and viewport viewport.height)))
    (when (and (> width 0) (> height 0))
      (set final-fbo (gl.glGenFramebuffers 1))
      (gl.glBindFramebuffer gl.GL_FRAMEBUFFER final-fbo)
      (set final-rbo (gl.glGenRenderbuffers 1))
      (gl.glBindRenderbuffer gl.GL_RENDERBUFFER final-rbo)
      (gl.glRenderbufferStorage gl.GL_RENDERBUFFER gl.GL_RGBA8 width height)
      (gl.glFramebufferRenderbuffer gl.GL_FRAMEBUFFER gl.GL_COLOR_ATTACHMENT0 gl.GL_RENDERBUFFER final-rbo)
      (gl.checkFramebuffer)
      (gl.glBindFramebuffer gl.GL_FRAMEBUFFER 0)
      (set final-width width)
      (set final-height height)))

  (fn draw-target [_self target options]
    (when (and target target.projection)
      (local draw-geometry (bool-option options :geometry true))
      (local draw-text (bool-option options :text true))
      (local view (target:get-view-matrix))
      (local projection target.projection)
      (when draw-geometry
        (local triangle-vector (and target.get-triangle-vector (target:get-triangle-vector)))
        (local triangle-batches (and target.get-triangle-batches (target:get-triangle-batches)))
        (when triangle-vector
          (triangle-renderer:render triangle-vector projection view triangle-batches))
        (local mesh-batches (and target.get-mesh-batches (target:get-mesh-batches)))
        (when (and mesh-batches (> (length mesh-batches) 0))
          (mesh-renderer:render mesh-batches projection view))
        (local image-batches (and target.get-image-batches (target:get-image-batches)))
        (when image-batches
          (image-renderer:render image-batches projection view))
        (local line-vector (and target.get-line-vector (target:get-line-vector)))
        (when line-vector
          (line-renderer:render-lines line-vector projection view))
        (local line-strips (and target.get-line-strips (target:get-line-strips)))
        (when (and line-strips (> (length line-strips) 0))
          (line-renderer:render-line-strips line-strips projection view))
        (local point-vector (and target.get-point-vector (target:get-point-vector)))
        (when point-vector
          (point-renderer:render point-vector projection view)))
      (when draw-text
        (local text-batches (and target.get-text-batches (target:get-text-batches)))
        (each [font vector (pairs (target:get-text-vectors))]
          (local batches (and text-batches (. text-batches font)))
          (text-renderer:render vector font projection view batches)))))

  (fn prerender-sub-apps [_self]
    (when (> (length sub-apps) 0)
      (each [_ sub-app (ipairs sub-apps)]
        (when (and sub-app sub-app.prerender)
          (sub-app:prerender)))))

  (fn draw-sub-apps [_self target]
    (when (and target target.projection target.get-view-matrix (> (length sub-apps) 0))
      (local view (target:get-view-matrix))
      (local projection target.projection)
      (each [_ sub-app (ipairs sub-apps)]
        (when (and sub-app sub-app.render)
          (sub-app:render image-renderer projection view)))))

  (fn draw-hud [self]
    (when app.hud
      (gl.glClear gl.GL_DEPTH_BUFFER_BIT)
      (self:draw-target app.hud)))

  (fn use-fxaa? []
    (and (fxaa:ready?)
         final-fbo final-rbo
         (> final-width 0)
         (> final-height 0)))

  (fn update [self]
    (local active-theme (and app.themes app.themes.get-active-theme
                             (app.themes.get-active-theme)))
    (when (and active-theme active-theme.skybox active-theme.skybox.brightness)
      (skybox-renderer:set-brightness active-theme.skybox.brightness))
    (self:prerender-sub-apps)
    (local viewport app.viewport)
    (when (and viewport viewport.width viewport.height)
      (gl.glViewport viewport.x viewport.y viewport.width viewport.height))
    (local use-fxaa (use-fxaa?))
    (gl.glDisable gl.GL_CULL_FACE)
    (gl.glEnable gl.GL_DEPTH_TEST)
    (gl.glDepthFunc gl.GL_LESS)
    (gl.glClearColor 0.0 0.0 0.0 1.0)
    (gl.glBindFramebuffer gl.GL_FRAMEBUFFER (if use-fxaa (fxaa:get-fbo) 0))
    (gl.glClear (bor gl.GL_COLOR_BUFFER_BIT gl.GL_DEPTH_BUFFER_BIT))
    (when app.scene
      (skybox-renderer:render app.scene)
      (self:draw-target app.scene {:text false}))
    (if use-fxaa
        (do
          (gl.glBindFramebuffer gl.GL_FRAMEBUFFER final-fbo)
          (gl.glDisable gl.GL_DEPTH_TEST)
          (gl.glClear gl.GL_COLOR_BUFFER_BIT)
          (fxaa:render)
          (gl.glFramebufferRenderbuffer gl.GL_FRAMEBUFFER gl.GL_DEPTH_ATTACHMENT gl.GL_RENDERBUFFER (fxaa:get-depth-rbo))
          (gl.glEnable gl.GL_DEPTH_TEST)
          (when app.scene
            (self:draw-target app.scene {:geometry false})
            (self:draw-sub-apps app.scene))
          (draw-hud self)
          (gl.glBindFramebuffer gl.GL_READ_FRAMEBUFFER final-fbo)
          (gl.glBindFramebuffer gl.GL_DRAW_FRAMEBUFFER 0)
          (local width (fxaa:get-width))
          (local height (fxaa:get-height))
          (when (and (> width 0) (> height 0))
            (gl.glBlitFramebuffer 0 0 width height 0 0 width height gl.GL_COLOR_BUFFER_BIT gl.GL_NEAREST))
          (gl.glBindFramebuffer gl.GL_FRAMEBUFFER 0))
        (do
          (when app.scene
            (self:draw-target app.scene {:geometry false})
            (self:draw-sub-apps app.scene))
          (draw-hud self))))

  (fn on-viewport-changed [_self viewport]
    (fxaa:on-viewport-changed viewport)
    (create-final-fbo viewport))

  (fn drop [_self]
    (delete-final-fbo)
    (each [_ sub-app (ipairs sub-apps)]
      (when (and sub-app sub-app.drop)
        (sub-app:drop)))
    (set sub-apps [])
    (when fxaa
      (fxaa:drop)))

  {:update update
   :apply-theme (fn [_self theme]
                  (when (and theme theme.skybox theme.skybox.brightness)
                    (skybox-renderer:set-brightness theme.skybox.brightness)))
   :draw-target draw-target
   :prerender-sub-apps prerender-sub-apps
   :draw-sub-apps draw-sub-apps
   :add-sub-app (fn [_self sub-app]
                  (when sub-app
                    (table.insert sub-apps sub-app))
                  sub-app)
   :remove-sub-app (fn [_self sub-app]
                     (when sub-app
                       (for [i 1 (length sub-apps)]
                         (when (= (. sub-apps i) sub-app)
                           (table.remove sub-apps i)
                           (lua "break")))))
   :skybox skybox-renderer
   :on-viewport-changed on-viewport-changed
   :drop drop})
