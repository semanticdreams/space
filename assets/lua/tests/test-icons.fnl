(local fennel (require :fennel))
;; Ensure app exists and has engine mock before requiring modules that use it
(global app (or _G.app {}))
(set app.engine (or app.engine {}))
(set app.engine.get-asset-path (fn [path] (.. (os.getenv "SPACE_ASSETS_PATH") "/" path)))
(set app.themes {:get-active-theme (fn [] {:font "default-font"
                                             :text {:scale 1.0}})
                 :get-color (fn [] [1 1 1 1])})

;; Mock textures to avoid Engine/JobSystem dependency
(tset package.loaded :textures 
      {:load-texture (fn [_name _path] {:width 512 :height 512 :id 1})
       :load-texture-async (fn [_name _path] {:width 512 :height 512 :id 1})})

(local Icons (require :icons))
(local Icon (require :icon-widget))
(local Button (require :button))

(fn test-icons-resolve []
  (local icons (Icons {:theme "Adwaita"}))
  
  ;; Test Material Icon (legacy)
  (local material-res (icons:resolve "arrow_drop_down"))
  (assert (= material-res.type :font) "Material icon should identify as font")
  (assert material-res.codepoint "Material icon should have a codepoint")

  ;; Test Image Path
  (local image-res (icons:resolve "/tmp/some-icon.png"))
  (assert (= image-res.type :image) "Absolute path should identify as image")
  (assert (= image-res.path "/tmp/some-icon.png") "Path should be preserved")

  (print "test-icons-resolve passed"))

(fn test-icon-widget-render []
  ;; Mock Context with Icons service
  (local icons (Icons))
  
  (local mock-vector
    {:allocate (fn [])
     :delete (fn [])
     :set-float (fn [])
     :set-glm-vec3 (fn [])
     :set-glm-vec2 (fn [])
     :set-glm-vec4 (fn [])})

  (local ctx {:icons icons
              :get-text-vector (fn [] mock-vector)
              :track-text-handle (fn [])
              :untrack-text-handle (fn [])})
  
  ;; Render Material Icon
  (local icon-builder (Icon {:icon "home"}))
  (local widget (icon-builder ctx))
  (assert widget "Icon widget should build")
  (assert widget.layout "Icon widget should have layout")
  ;; We know it's a Text widget underneath for material icons, checking children would rely on implementation details
  ;; but we can verify it doesn't crash.
  
  (print "test-icon-widget-render passed"))

(fn main []
  (test-icons-resolve)
  (test-icon-widget-render)
  (print "All icon tests passed."))

{:main main}
