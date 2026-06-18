(local fs (require :fs))
(local fennel (require :fennel))

(var cache-dir nil)

(fn init! [dir]
  (set cache-dir dir))

(fn sanitize-cache-name [name]
  (string.gsub (or name "") "[^%w%._-]" "_"))

(fn cache-stem [module-path module-name]
  (when (and cache-dir module-path module-name)
    (local stat (fs.stat module-path))
    (local modified (and stat stat.modified))
    (local size (and stat stat.size))
    (local version (sanitize-cache-name (or fennel.version "unknown")))
    (local lua-version (sanitize-cache-name (or _VERSION "lua")))
    (local correlate-flag "c1")
    (when (and modified size)
      (fs.join-path cache-dir
                    (.. (sanitize-cache-name module-name)
                        "_" version "_" lua-version "_" correlate-flag
                        "_" modified "_" size)))))

(fn cache-path-source [module-path module-name]
  (local stem (cache-stem module-path module-name))
  (and stem (.. stem ".lua")))

(fn cache-path-bytecode [module-path module-name]
  (local stem (cache-stem module-path module-name))
  (and stem (.. stem ".luac")))

(fn clear-fennel-module-cache! [module-name module-path]
  (when (and cache-dir module-name module-path)
    (local source-cache (cache-path-source module-path module-name))
    (local bytecode-cache (cache-path-bytecode module-path module-name))
    (when source-cache
      (pcall os.remove source-cache))
    (when bytecode-cache
      (pcall os.remove bytecode-cache))))

{:init! init!
 :cache-path-source cache-path-source
 :cache-path-bytecode cache-path-bytecode
 :clear-fennel-module-cache! clear-fennel-module-cache!}
