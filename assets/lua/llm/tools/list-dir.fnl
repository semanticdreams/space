(local fs (require :fs))

(local tool-name "list_dir")

(fn safe-lower [text]
    (if text
        (string.lower text)
        ""))

(fn require-fs []
    (assert (and fs fs.list-dir fs.join-path fs.absolute) "list_files tool requires the fs binding with list-dir, join-path, absolute")
    fs)

(fn resolve-path [path ctx]
  (local cwd (or (and ctx ctx.cwd) (fs.cwd)))
  (if (fs.exists path) path ; Optimistic check, but better to force join if relative?
      ; Actually, fs.exists check on "main.c" might be true in process CWD but user meant conversation CWD.
      ; So we should check if path is absolute.
      ; But we don't have fs.is_absolute binding? We have fs.absolute.
      ; If fs.absolute(path) == path? No, fs.absolute resolves relative to process CWD.
      ; Let's simpler logic: if path starts with /, it's absolute (on linux). 
      (if (= (string.sub path 1 1) "/")
          path
          (fs.join-path cwd path))))

(fn normalize-entry [entry]
    {:name entry.name
     :path entry.path
     :is_dir (and entry.is-dir true)
     :is_file (and entry.is-file true)
     :size entry.size})

(fn sort-entries [entries]
    (table.sort entries
        (fn [a b]
            (local a-dir (and a.is_dir true))
            (local b-dir (and b.is_dir true))
            (if (= a-dir b-dir)
                (< (safe-lower a.name) (safe-lower b.name))
                a-dir)))
    entries)

(fn list-dir [args _ctx]
    (local options (or args {}))
    (local directory (or options.directory options.path))
    (assert directory "list_dir requires directory")
    (assert (= (type directory) :string) "list_dir.directory must be a string")
    (local include-hidden (if (not (= options.include_hidden nil))
                               options.include_hidden
                               false))
    (assert (or (= include-hidden true) (= include-hidden false))
            "list_dir.include_hidden must be a boolean")

    (local binding (require-fs))
    (local target (resolve-path directory _ctx))
    (local (ok entries) (pcall binding.list-dir target include-hidden))
    (if (not ok)
        (error (.. "list_dir failed to list " target ": " entries)))

    (local normalized [])
    (each [_ entry (ipairs entries)]
        (table.insert normalized (normalize-entry entry)))
    (sort-entries normalized)
    {:tool tool-name
     :directory directory
     :include_hidden include-hidden
     :count (# normalized)
     :entries normalized})

{:name tool-name
 :description "List the contents of a directory without descending into subdirectories."
 :parameters {:type "object"
              :properties {:directory {:type "string"
                                       :description "Absolute or relative path to list"}
                           :include_hidden {:type "boolean"
                                            :description "Whether to include dotfiles and hidden entries"
                                            :default false}}
              :required ["directory" "include_hidden"]
              :additionalProperties false}
 :strict true
 :call list-dir}
