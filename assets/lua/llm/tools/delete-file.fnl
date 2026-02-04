(local fs (require :fs))

(local tool-name "delete_file")

(fn require-fs []
    (assert (and fs fs.remove fs.stat) "delete_file tool requires fs bindings remove and stat")
    fs)

(fn resolve-path [path ctx]
  (local cwd (or (and ctx ctx.cwd) (fs.cwd)))
  (if (= (string.sub path 1 1) "/")
      path
      (fs.join-path cwd path)))

(fn delete-file [args _ctx]
    (local options (or args {}))
    (local path options.path)
    (assert path "delete_file requires path")
    (assert (= (type path) :string) "delete_file.path must be a string")

    (local binding (require-fs))
    (local target (resolve-path path _ctx))
    (local (stat-ok info) (pcall binding.stat target))
    (if (not stat-ok)
        (error (.. "delete_file failed to stat " path ": " info)))
    (assert info.exists (.. "delete_file path does not exist: " path))
    (assert (not info.is-dir) (.. "delete_file only deletes files, got directory: " path))

    (local (ok err) (pcall binding.remove target))
    (if (not ok)
        (error (.. "delete_file failed to delete " path ": " err)))

    {:tool tool-name
     :path path
     :deleted true})

{:name tool-name
 :description "Delete a file."
 :parameters {:type "object"
              :properties {:path {:type "string"
                                  :description "Absolute or relative file path to delete"}}
              :required ["path"]
              :additionalProperties false}
 :strict true
 :call delete-file}
