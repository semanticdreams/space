(local fs (require :fs))

(local tool-name "read_file")

(fn require-fs []
    (assert (and fs fs.read-file) "read_file tool requires the fs binding with read-file")
    fs)

(fn resolve-path [path ctx]
  (local cwd (or (and ctx ctx.cwd) (fs.cwd)))
  (if (= (string.sub path 1 1) "/")
      path
      (fs.join-path cwd path)))

(fn read-file [args _ctx]
    (local options (or args {}))
    (local path options.path)
    (assert path "read_file requires path")
    (assert (= (type path) :string) "read_file.path must be a string")

    (local binding (require-fs))
    (local target (resolve-path path _ctx))
    (local (ok content) (pcall binding.read-file target))
    (if (not ok)
        (error (.. "read_file failed to read " path ": " content)))

    {:tool tool-name
     :path path
     :content content
     :size (string.len (or content ""))})

{:name tool-name
 :description "Read the full contents of a file."
 :parameters {:type "object"
              :properties {:path {:type "string"
                                  :description "Absolute or relative file path to read"}}
              :required ["path"]
              :additionalProperties false}
 :strict true
 :call read-file}
