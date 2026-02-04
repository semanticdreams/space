(local glm (require :glm))
(local {: Layout} (require :layout))
(local RawImage (require :raw-image))

(local textures (require :textures))
(fn resolve-texture [opts]
  (if opts.texture
      opts.texture
      (let [path (or opts.path opts.texture-path opts.filename opts.file)]
        (when path
          (assert (and textures (or textures.load-texture-async textures.load-texture))
                  "Texture loading is unavailable")
          (local load-fn (or textures.load-texture-async textures.load-texture))
          (load-fn
            (or opts.texture-name path)
            (if app.engine.get-asset-path
                (app.engine.get-asset-path path)
                path))))))

(fn resolve-size [opts aspect]
  (var width (or opts.width (and opts.size opts.size.x)))
  (var height (or opts.height (and opts.size opts.size.y)))
  (when (and (not width) (not height))
    (set width (or opts.base-width 20.0)))
  (when (and width (not height))
    (set height (if (> aspect 0) (/ width aspect) width)))
  (when (and height (not width))
    (set width (* height aspect)))
  {:width (or width 1) :height (or height 1)})

(fn Image [opts]
  (assert opts "Image requires options")
  (fn build [ctx]
    (local texture (resolve-texture opts))
    (assert texture "Image requires :texture or :path")
    (local tex-height (or texture.height 1))
    (local aspect (if (> tex-height 0) (/ texture.width tex-height) 1.0))
    (local dimensions (resolve-size opts aspect))
    (local width dimensions.width)
    (local height dimensions.height)
    (local tint (or opts.tint (glm.vec4 1 1 1 1)))
    (local raw
      ((RawImage {:texture texture
                  :color tint
                  :size (glm.vec3 width height 0)}) ctx))

    (fn measurer [self]
      (set self.measure (glm.vec3 width height 0)))

    (fn layouter [self]
      (local should-render (not (self:effective-culled?)))
      (raw:set-visible should-render)
      (when should-render
        (set raw.size (glm.vec3 self.size.x self.size.y 0))
        (set raw.position self.position)
        (set raw.rotation self.rotation)
        (set raw.depth-offset-index self.depth-offset-index)
        (set raw.clip-region self.clip-region)
        (raw:update)))

    (local layout
      (Layout {:name (or opts.name "image")
               : measurer
               : layouter}))

    (fn drop [self]
      (self.layout:drop)
      (raw:drop))

  {:layout layout
   :drop drop
   :texture texture
   :raw raw
   :aspect aspect
   :tint tint}))

Image
