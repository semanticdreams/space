(local Font (require :font))
(local Xdg (require :xdg-icons))
(local fs (require :fs))
(local IoUtils (require :io-utils))

(local codepoints-file "material-design-icons/MaterialSymbolsSharp[FILL,GRAD,opsz,wght].codepoints")
(local icon-metadata "material-design-icons/msdf/icons.json")
(local icon-texture "material-design-icons/msdf/icons.png")

(fn parse-codepoints []
  (local entries {})
  (if (and app.engine app.engine.get-asset-path)
      (let [content (IoUtils.read-file (app.engine.get-asset-path codepoints-file))
            matcher (string.gmatch content "[^\r\n]+")]
        (var line (matcher))
        (while line
          (let [(name hex) (string.match line "^(%S+)%s+(%S+)$")]
            (when (and name hex)
              (set (. entries name) (tonumber hex 16))))
          (set line (matcher))))
      entries)
  entries)

(fn Icons [opts]
  (local options (or opts {}))
  (local active-theme (or options.theme "Adwaita")) ;; Default XDG theme
  (local codepoints (parse-codepoints))
  (local font
    (Font {:metadata-path icon-metadata
           :texture-path icon-texture
           :texture-name "material-icons"}))
  
  (fn resolve [self name opts]
    (local opts (or opts {}))
    (local material-cp (. codepoints name))
    
    (if material-cp
        {:type :font
         :codepoint material-cp
         :font font}
        (if (or (string.find name "/") (string.find name "\\%"))
            {:type :image
             :path name}
            (let [xdg-path (Xdg.resolve name active-theme)]
              (if xdg-path
                  {:type :image
                   :path xdg-path}
                  nil)))))

  (local self {:codepoints codepoints
               :font font
               :theme active-theme})

  (fn get-codepoint [_self name]
    (local value (. codepoints name))
    (if value
        value
        (error (.. "Unknown icon " name))))

  (fn drop [_self]
    nil)

  (set self.get get-codepoint)
  (set self.resolve resolve)
  (set self.drop drop)
  self)

Icons
