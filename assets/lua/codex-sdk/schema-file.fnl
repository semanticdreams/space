(local fs (require :fs))
(local tempfile (require :tempfile))
(local JsonUtils (require :json-utils))

(fn json-object-table? [value]
  (if (not (= (type value) :table))
      false
      (do
        (var ok true)
        (each [k _ (pairs value)]
          (when (not (= (type k) :string))
            (set ok false)))
        ok)))

(fn create-output-schema-file [schema]
  (if (= schema nil)
      {:schema-path nil
       :cleanup (fn [] nil)}
      (do
        (when (not (json-object-table? schema))
          (error "codex-sdk output-schema must be a plain JSON object table"))
        (local directory (tempfile.TemporaryDirectory {:prefix "codex-output-schema-"}))
        (local schema-path (fs.join-path directory.path "schema.json"))
        (local cleanup
          (fn []
            (local (ok err) (pcall (fn [] (directory:drop))))
            (when (not ok)
              (error err))))
        (local (ok err) (pcall (fn [] (JsonUtils.write-json! schema-path schema))))
        (when (not ok)
          (cleanup)
          (error err))
        {:schema-path schema-path
         :cleanup cleanup})))

{:create-output-schema-file create-output-schema-file}
