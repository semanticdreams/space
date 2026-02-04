(local fs (require :fs))
(local process (require :process))
(local tempfile (require :tempfile))

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

(fn resolve-settings [opts]
  (local settings (or (and opts (. opts :settings)) app.settings))
  (assert (and settings (. settings :get-value)) "external-editor requires settings with get-value")
  settings)

(fn resolve-config [opts]
  (local settings (resolve-settings opts))
  (local program (settings.get-value "external-editor.program" nil))
  (local args (settings.get-value "external-editor.args" nil))
  (when (= program nil)
    (error "external-editor requires external-editor.program in settings"))
  (when (= args nil)
    (error "external-editor requires external-editor.args in settings"))
  (when (not (= (type program) :string))
    (error "external-editor settings external-editor.program must be a string"))
  (when (not (table-is-array? args))
    (error "external-editor settings external-editor.args must be an array"))
  (each [_ value (ipairs args)]
    (when (not (= (type value) :string))
      (error "external-editor settings external-editor.args entries must be strings")))
  {:program program
   :args args})

(fn substitute-placeholders [template replacements]
  (when (not (= (type template) :string))
    (error "external-editor placeholder templates must be strings"))
  (local (out _count)
    (string.gsub template "{(.-)}"
                 (fn [key]
                   (local value (. replacements key))
                   (when (= value nil)
                     (error (string.format "external-editor unknown placeholder {%s}" key)))
                   (tostring value))))
  out)

(fn merge-placeholders [base extra]
  (local out {})
  (each [k v (pairs (or base {}))]
    (tset out k v))
  (each [k v (pairs (or extra {}))]
    (tset out k v))
  out)

(fn build-argv [path opts]
  (assert (and (= (type path) :string) (> (# path) 0))
          "external-editor requires a non-empty path string")
  (local config (resolve-config opts))
  (local placeholders (merge-placeholders {:path path} (and opts (. opts :placeholders))))
  (local argv [])
  (table.insert argv (substitute-placeholders config.program placeholders))
  (each [_ arg (ipairs config.args)]
    (table.insert argv (substitute-placeholders arg placeholders)))
  argv)

(fn open-file [path callback opts]
  (assert (= (type callback) :function) "external-editor.open-file requires a callback")
  (local argv (build-argv path opts))
  (process.spawn {:args argv}
                 (fn [result]
                   (callback)))
  true)

(fn edit-string [text callback opts]
  (assert (= (type callback) :function) "external-editor.edit-string requires a callback")
  (local options (or opts {}))
  (local raise-on-changed (or (. options :raise-on-changed) false))
  (when (not (= (type raise-on-changed) :boolean))
    (error "external-editor.edit-string raise-on-changed must be a boolean"))
  (local file-suffix (or (. options :file-suffix) ""))
  (when (not (= (type file-suffix) :string))
    (error "external-editor.edit-string file-suffix must be a string"))
  (when (and (> (# file-suffix) 0) (not (= (string.sub file-suffix 1 1) ".")))
    (error "external-editor.edit-string file-suffix must start with '.' when non-empty"))
  (local tempfile-overrides (or (. options :tempfile) {}))
  (when (and (. options :tempfile) (not (= (type (. options :tempfile)) :table)))
    (error "external-editor.edit-string tempfile must be a table when provided"))
  (local suffix
    (if (not (= (. tempfile-overrides :suffix) nil))
        (. tempfile-overrides :suffix)
        file-suffix))
  (local handle
    (tempfile.NamedTemporaryFile
      {:prefix (or (. tempfile-overrides :prefix) "edit-")
       :suffix suffix
       :dir (. tempfile-overrides :dir)
       :delete (if (not (= (. tempfile-overrides :delete) nil))
                   (. tempfile-overrides :delete)
                   true)}))
  (local original (or text ""))
  (fs.write-file handle.path original)
  (open-file handle.path
             (fn []
                (local (read-ok content) (pcall fs.read-file handle.path))
               (handle:drop)
               (when (not read-ok)
                 (error content))
               (when (and raise-on-changed (not (= content original)))
                 (local msg "external-editor.edit-string content changed with raise-on-changed")
                 (callback nil msg)
                 (error msg))
               (callback content))
             options)
  handle.path)

{:open-file open-file
 :edit-string edit-string}
