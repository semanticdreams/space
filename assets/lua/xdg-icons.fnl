(local fs (require :fs))
(local logging (require :logging))
(local IoUtils (require :io-utils))

(fn file-exists? [path]
  (local stat (fs.stat path))
  (and stat stat.exists stat.is-file))

(fn dir-exists? [path]
  (local stat (fs.stat path))
  (and stat stat.exists stat.is-dir))

(fn read-ini [path]
  (local content (IoUtils.read-file path))
  (local sections {})
  (var current-section nil)
  (when content
    (each [line (string.gmatch content "[^\r\n]+")]
      (local section-match (string.match line "^%[([^%]]+)%]"))
      (if section-match
          (do
            (set current-section section-match)
            (set (. sections current-section) {}))
          (when current-section
            (local (key value) (string.match line "^([^=]+)=(.*)$"))
            (when (and key value)
              (tset sections current-section key value))))))
  sections)

(fn get-icon-dirs []
  (local dirs [])
  (local home (os.getenv "HOME"))
  (local xdg-data (or (os.getenv "XDG_DATA_HOME") (and home (.. home "/.local/share"))))
  (when xdg-data
    (table.insert dirs (.. xdg-data "/icons")))
  (table.insert dirs (and home (.. home "/.icons")))
  (local xdg-data-dirs (or (os.getenv "XDG_DATA_DIRS") "/usr/local/share:/usr/share"))
  (each [dir (string.gmatch xdg-data-dirs "[^:]+")]
    (table.insert dirs (.. dir "/icons")))
  (table.insert dirs "/usr/share/pixmaps")
  dirs)

(fn find-best-icon [candidates size scale]
  ;; TODO: Implement smarter selection based on size/scale distance
  (or (. candidates 1) nil))

(fn scan-dir [dir-path icon-name extensions]
  (var found nil)
  (each [_ ext (ipairs extensions)]
    (when (not found)
      (local path (.. dir-path "/" icon-name "." ext))
      (when (file-exists? path)
        (set found path))))
  found)

(fn lookup-fallback [icon-name]
  (local dirs (get-icon-dirs))
  (var found nil)
  (local extensions ["png" "svg" "xpm"])
  (each [_ base-dir (ipairs dirs)]
    (when (not found)
      (set found (scan-dir base-dir icon-name extensions))))
  found)

(fn resolve-icon [icon-name theme-name size scale]
  (local dirs (get-icon-dirs))
  (local extensions ["png" "svg" "xpm"])
  (var found nil)
  
  (fn check-theme [theme]
    (each [_ base-dir (ipairs dirs)]
      (when (not found)
        (local theme-dir (.. base-dir "/" theme))
        (local index-path (.. theme-dir "/index.theme"))
        (when (file-exists? index-path)
          (local ini (read-ini index-path))
          (local icon-theme (or (. ini "Icon Theme") {}))
          (local subdirs-str (or icon-theme.Directories ""))
          
          (each [subdir (string.gmatch subdirs-str "[^,]+")]
            (when (not found)
              (local full-dir (.. theme-dir "/" subdir))
              (set found (scan-dir full-dir icon-name extensions))))

          (when (and (not found) icon-theme.Inherits)
             ;; Recurse on inherited themes
             ;; Note: infinite loop protection omitted for brevity in this first pass
             (each [parent (string.gmatch icon-theme.Inherits "[^,]+")]
               (when (not found)
                (check-theme parent))))))))

  (when (and theme-name (not (= theme-name "")))
    (check-theme theme-name))
  
  (when (not found)
    (check-theme "hicolor"))
    
  (or found (lookup-fallback icon-name)))

{:resolve resolve-icon
 :get-dirs get-icon-dirs}
