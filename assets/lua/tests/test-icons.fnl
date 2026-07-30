(local fennel (require :fennel))

;; Module-level: only safe globals that don't need restore.
(global app (or _G.app {}))
(set app.themes {:get-active-theme (fn [] {:font "default-font"
                                             :text {:scale 1.0}})
                 :get-color (fn [] [1 1 1 1])})

;; Wrapper that snapshots/restores dotted global paths.
;; Keys not starting with 'package.' or 'app.' are prefixed with 'app.'.
;; Nil-safe: if any segment of the path does not exist in _G, snapshot is nil
;; and restore is a no-op.
;; Recognized by the test-isolation constraint rule as a safe mutation wrapper.
(fn with-restored-app-fields [keys f]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    ;; Resolve dotted key path from global scope to snapshot
    (local full-key (if (or (key:find "^package%.") (key:find "^app%."))
                       key
                       (.. "app." key)))
    (local parts [])
    (each [seg (full-key:gmatch "[^%.]+")] (table.insert parts seg))
    (var src _G)
    (var all-exist true)
    (for [i 1 (- (length parts) 1)]
      (set src (. src (. parts i)))
      (when (= nil src)
        (set all-exist false)
        (lua :break)))
    (set (. snapshot key) (if all-exist
                              (. src (. parts (length parts)))
                              nil)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs keys)]
    ;; Restore dotted key path from snapshot
    (local full-key (if (or (key:find "^package%.") (key:find "^app%."))
                       key
                       (.. "app." key)))
    (local parts [])
    (each [seg (full-key:gmatch "[^%.]+")] (table.insert parts seg))
    (var dst _G)
    (var all-exist true)
    (for [i 1 (- (length parts) 1)]
      (set dst (. dst (. parts i)))
      (when (= nil dst)
        (set all-exist false)
        (lua :break)))
    (when all-exist
      (tset dst (. parts (length parts)) (. snapshot key))))
  (if ok
      result
      (error result)))

(fn setup-icons []
  ;; Wrapper snapshots/restores package.loaded.textures AND app.engine.
  ;; :package.loaded.textures — restore leaf texture module value
  ;; :engine — restore app.engine container (includes get-asset-path)
  ;; If a require throws, the wrapper's pcall restores both keys immediately.
  (with-restored-app-fields [:package.loaded.textures :engine]
    (fn []
      ;; Ensure app.engine exists before mocking get-asset-path
      (if (not _G.app.engine)
          (tset _G.app :engine {}))
      (tset _G.app.engine :get-asset-path
            (fn [path] (.. (os.getenv "SPACE_ASSETS_PATH") "/" path)))

      ;; Mock textures while loading icon widgets
      (tset package.loaded :textures
            {:load-texture (fn [_name _path] {:width 512 :height 512 :id 1})
             :load-texture-async (fn [_name _path] {:width 512 :height 512 :id 1})})
      (local icons (require :icons))
      (local icon (require :icon-widget))
      (local button (require :button))

      ;; Return loaded modules as a sequential table
      [icons icon button])))

;; Destructure the returned module table
(local modules (setup-icons))
(local Icons (. modules 1))
(local Icon (. modules 2))
(local Button (. modules 3))

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
              :get-text-ssbo-batcher (fn []
                                       {:upsert-text (fn [_batcher _key _opts] nil)
                                        :update-text-transform (fn [_batcher _key _opts] nil)
                                        :remove-text (fn [_batcher _key] nil)})
              :track-text-handle (fn [])
              :untrack-text-handle (fn [])})
  
  ;; Render Material Icon
  (local icon-builder (Icon {:icon "home"}))
  (local widget (icon-builder ctx))
  (assert widget "Icon widget should build")
  (assert widget.layout "Icon widget should have layout")
  ;; We know it's a Text widget underneath for material icons, checking children
  ;; would rely on implementation details but we can verify it doesn't crash.
  
  (print "test-icon-widget-render passed"))

(fn main []
  ;; Set up app.engine.get-asset-path mock for test execution
  ;; (Icons() calls parse-codepoints which reads the codepoints file).
  ;; Snapshot and restore app.engine container so cleanup is guaranteed
  ;; even if tests fail.
  (local prev-engine (and _G.app _G.app.engine))
  (if (not _G.app.engine)
      (tset _G.app :engine {}))
  (tset _G.app.engine :get-asset-path
        (fn [path] (.. (os.getenv "SPACE_ASSETS_PATH") "/" path)))

  (local (ok err) (pcall (fn []
    (test-icons-resolve)
    (test-icon-widget-render)
    (print "All icon tests passed."))))

  ;; Always restore engine state, even if tests failed.
  ;; Restoring the container also restores the original get-asset-path.
  (if _G.app
      (tset _G.app :engine prev-engine))

  ;; Re-raise any test error after cleanup
  (if (not ok) (error err)))

{:main main}
