(local package package)

(local tests [])

(fn reload [module-name]
  (set (. package.loaded module-name) nil)
  (require module-name))

(fn with-font-stubs [cb]
  (local original-json (. package.loaded "json"))
  (local original-textures (. package.loaded "textures"))
  (local original-io-utils (. package.loaded "io-utils"))
  (local original-font (. package.loaded "font"))
  (local original-app _G.app)
  (local counts {:read-file 0
                 :json-loads 0
                 :texture-loads 0})
  (set (. package.loaded "json")
       {:loads (fn [_content]
                 (set counts.json-loads (+ counts.json-loads 1))
                 {:metrics {:ascender 7
                            :descender -2
                            :lineHeight 9}
                  :atlas {:width 64
                          :height 64}
                  :glyphs [{:unicode 32
                            :advance 1.25
                            :planeBounds {:left 0 :right 1 :bottom 0 :top 1}
                            :atlasBounds {:left 0 :right 10 :bottom 0 :top 10}}
                           {:unicode 65533
                            :advance 2.0
                            :planeBounds {:left 0 :right 1 :bottom 0 :top 1}
                            :atlasBounds {:left 10 :right 20 :bottom 0 :top 10}}]})})
  (set (. package.loaded "textures")
       {:load-texture-async (fn [name path]
                              (set counts.texture-loads (+ counts.texture-loads 1))
                              {:name name :path path :ready true})})
  (set (. package.loaded "io-utils")
       {:read-file (fn [path]
                     (set counts.read-file (+ counts.read-file 1))
                     (.. "stub:" path))})
  (global app {:disable_font_textures false
               :engine {:get-asset-path (fn [path] (.. "/assets/" path))}})
  (local (ok result)
    (pcall cb counts))
  (set (. package.loaded "font") original-font)
  (set (. package.loaded "json") original-json)
  (set (. package.loaded "textures") original-textures)
  (set (. package.loaded "io-utils") original-io-utils)
  (set _G.app original-app)
  (if ok
      result
      (error result)))

(fn font-loads-on-first-access []
  (with-font-stubs
    (fn [counts]
      (local Font (reload "font"))
      (local font
        (Font {:metadata-path "fonts/test.json"
               :texture-path "fonts/test.png"
               :texture-name "test-font"}))
      (assert (= counts.read-file 0))
      (assert (= counts.json-loads 0))
      (assert (= counts.texture-loads 0))
      (assert (= font.metadata-path "fonts/test.json"))
      (assert (= font.texture-path "fonts/test.png"))
      (assert (= font.texture-name "test-font"))
      (assert (= font.advance 1.25))
      (assert (= counts.read-file 1))
      (assert (= counts.json-loads 1))
      (assert (= counts.texture-loads 1))
      (assert (= font.metadata.metrics.ascender 7))
      (assert (= font.texture.name "test-font"))
      (local fallback-glyph (. font.glyph-map 65533))
      (assert (= fallback-glyph.font font))
      (assert (= font.advance 1.25))
      (assert (= counts.read-file 1))
      (assert (= counts.json-loads 1))
      (assert (= counts.texture-loads 1)))))

(table.insert tests {:name "Font defers file and texture load until first field access"
                     :fn font-loads-on-first-access})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "font"
                       :tests tests})))

{:name "font"
 :tests tests
 :main main}
