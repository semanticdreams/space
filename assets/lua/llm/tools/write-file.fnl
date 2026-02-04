(local fs (require :fs))

(local tool-name "write_file")

(fn require-fs []
    (assert (and fs fs.write-file) "write_file tool requires the fs binding with write-file")
    fs)

(fn resolve-path [path ctx]
  (local cwd (or (and ctx ctx.cwd) (fs.cwd)))
  (if (= (string.sub path 1 1) "/")
      path
      (fs.join-path cwd path)))

(fn write-file [args _ctx]
    (local options (or args {}))
    (local path options.path)
    (assert path "write_file requires path")
    (assert (= (type path) :string) "write_file.path must be a string")

    (local content (or options.content ""))
    (assert (= (type content) :string) "write_file.content must be a string")

    (local binding (require-fs))
    (local target (resolve-path path _ctx))
    (local (ok err) (pcall binding.write-file target content))
    (if (not ok)
        (error (.. "write_file failed to write " path ": " err)))

    {:tool tool-name
     :path path
     :bytes (string.len content)})

{:name tool-name
 :description "Write text contents to a file, replacing any existing data."
 :parameters {:type "object"
              :properties {:path {:type "string"
                                  :description "Absolute or relative file path to write"}
                           :content {:type "string"
                                     :description "Text content to write to the file"}}
              :required ["path" "content"]
              :additionalProperties false}
 :strict true
 :call write-file}
