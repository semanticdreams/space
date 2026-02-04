(local json (require :json))

(local textures (require :textures))
(local IoUtils (require :io-utils))

(local loaded-fonts {})

(fn load-msdf-font [metadata-path texture-path texture-name opts]
  (when app.disable_font_textures
    (error "Font textures are disabled (app.disable_font_textures); enable textures to load fonts"))
  (assert app.engine.get-asset-path "Font requires app.engine.get-asset-path")
  (assert (and textures (or textures.load-texture-async textures.load-texture))
          "Font requires textures.load-texture")
  (assert metadata-path "Font missing metadata path")
  (assert texture-path "Font missing texture path")
  (local metadata (json.loads (IoUtils.read-file (app.engine.get-asset-path metadata-path))))
  (local load-fn (or textures.load-texture-async textures.load-texture))
  (local texture
    (load-fn
      (or texture-name texture-path)
      (app.engine.get-asset-path texture-path)))
  (local glyph-map (collect [_ x (ipairs metadata.glyphs)] x.unicode x))
  (local engine-glyph (. glyph-map 32))
  (local advance (or (and engine-glyph engine-glyph.advance) 1))
  (local font {:metadata metadata
               :texture texture
               :glyph-map glyph-map
               :advance advance})
  (each [_ glyph (pairs glyph-map)]
    (set glyph.font font))
  font) 

(fn Font [name-or-options]
  (local opts
    (if (= (type name-or-options) "table")
        name-or-options
        {:metadata-path (.. "ubuntu-font/msdf/" name-or-options ".json")
         :texture-path (.. "ubuntu-font/msdf/" name-or-options ".png")
         :texture-name (.. "font-" name-or-options)}))
  (load-msdf-font opts.metadata-path opts.texture-path opts.texture-name opts))
