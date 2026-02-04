(local fs (require :fs))
(local appdirs (require :appdirs))
(local toml (require :toml))

(assert fs "settings requires the fs module")
(assert appdirs "settings requires the appdirs module")
(assert toml "settings requires the toml module")

(fn split-key [key]
  (assert (and key (> (# key) 0)) "settings key must be a non-empty string")
  (local parts [])
  (each [part (string.gmatch key "([^%.]+)")]
    (table.insert parts part))
  (assert (> (length parts) 0) "settings key must include at least one segment")
  (when (= (string.sub key 1 1) ".")
    (error "settings key cannot start with a dot"))
  (when (= (string.sub key (# key)) ".")
    (error "settings key cannot end with a dot"))
  (when (string.find key ".." 1 true)
    (error "settings key cannot include empty segments"))
  parts)

(fn read-path [data parts]
  (var current data)
  (each [_ part (ipairs parts)]
    (if (not (= (type current) :table))
        (lua "return nil")
        (set current (. current part))))
  current)

(fn set-path [data parts value]
  (var current data)
  (local count (length parts))
  (each [idx part (ipairs parts)]
    (if (= idx count)
        (tset current part value)
        (do
          (var next (. current part))
          (when (not (= (type next) :table))
            (set next {})
            (tset current part next))
          (set current next)))))

(fn resolve-save? [opts]
  (if (and opts (not (= (. opts :save?) nil)))
      (. opts :save?)
      true))

(fn table-is-array? [value]
  (if (not (= (type value) :table))
      false
      (do
        (var count 0)
        (var max 0)
        (each [k _ (pairs value)]
          (if (or (not (= (type k) :number)) (not (= k (math.floor k))) (< k 1))
              (lua "return false")
              (do
                (set count (+ count 1))
                (when (> k max)
                  (set max k)))))
        (if (= count 0)
            false
            (= count max)))))

(fn clone-value [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (tset out k (clone-value v)))
        out)
      value))

(fn merge-tables [base override]
  (local result (clone-value base))
  (each [k v (pairs override)]
    (local existing (. result k))
    (if (and (= (type v) :table)
             (= (type existing) :table)
             (not (table-is-array? v))
             (not (table-is-array? existing)))
        (tset result k (merge-tables existing v))
        (tset result k (clone-value v))))
  result)

(fn Settings [opts]
  (assert (and app.engine fs.join-path) "settings requires fs.join-path")
  (local options (or opts {}))
  (local app-name (or (. options :app-name) "space"))
  (local config-dir (or (. options :config-dir) (appdirs.user-config-dir app-name)))
  (local site-config-dir (or (. options :site-config-dir) (appdirs.site-config-dir app-name)))
  (assert config-dir "settings requires a config directory")
  (local filename (or (. options :filename) "settings.toml"))
  (local config-path (fs.join-path config-dir filename))
  (local site-config-path (and site-config-dir (fs.join-path site-config-dir filename)))
  (var system-data {})
  (var user-data {})
  (var data {})
  (tset system-data :llm {:default_conversation_cwd nil})

  (fn load-file [path]
    (local (read-ok content) (pcall fs.read-file path))
    (when (not read-ok)
      (error (string.format "Settings failed to read %s: %s" path content)))
    (local (parse-ok decoded) (pcall toml.loads content))
    (when (not parse-ok)
      (error (string.format "Settings failed to parse %s: %s" path decoded)))
    (when (not (= (type decoded) :table))
      (error (string.format "Settings file %s must decode to a table" path)))
    decoded)

  (fn refresh-merged []
    (set data (merge-tables system-data user-data))
    data)

  (fn load []
    (set system-data {})
    (set user-data {})
    (when (and site-config-path (fs.exists site-config-path))
      (set system-data (load-file site-config-path)))
    (when (fs.exists config-path)
      (set user-data (load-file config-path)))
    (refresh-merged))

  (fn save []
    (local (ok err) (pcall fs.create-dirs config-dir))
    (when (not ok)
      (error (string.format "Settings failed to create %s: %s" config-dir err)))
    (local serialized (toml.dumps user-data))
    (local (write-ok write-err) (pcall fs.write-file config-path serialized))
    (when (not write-ok)
      (error (string.format "Settings failed to write %s: %s" config-path write-err)))
    true)

  (fn get-value [key fallback]
    (local parts (split-key key))
    (local value (read-path data parts))
    (if (= value nil) fallback value))

  (fn set-value [key value opts]
    (local parts (split-key key))
    (set-path user-data parts value)
    (refresh-merged)
    (when (resolve-save? opts)
      (save))
    value)

  (fn has-value? [key]
    (local parts (split-key key))
    (not (= (read-path data parts) nil)))

  (fn drop []
    (set system-data {})
    (set user-data {})
    (set data {}))

  (load)

  {:load load
   :save save
   :get-value get-value
   :set-value set-value
   :has-value? has-value?
   :drop drop
   :path config-path
   :system-path site-config-path})

Settings
