(local fs (require :fs))

(local tool-name "edit_file")

(fn require-fs []
    (assert (and fs fs.read-file fs.write-file) "edit_file tool requires the fs binding with read-file/write-file")
    fs)

(fn resolve-path [path ctx]
  (local cwd (or (and ctx ctx.cwd) (fs.cwd)))
  (if (= (string.sub path 1 1) "/")
      path
      (fs.join-path cwd path)))

(fn edit-file [args _ctx]
    (local options (or args {}))
    (local path options.path)
    (assert path "edit_file requires path")
    (assert (= (type path) :string) "edit_file.path must be a string")

    (local old-text options.old-text)
    (assert (not (= old-text nil)) "edit_file requires old-text")
    (assert (= (type old-text) :string) "edit_file.old-text must be a string")

    (local new-text (or options.new-text ""))
    (assert (= (type new-text) :string) "edit_file.new-text must be a string")

    (local binding (require-fs))
    (local target (resolve-path path _ctx))
    (local (ok content) (pcall binding.read-file target))
    (if (not ok)
        (error (.. "edit_file failed to read " path ": " content)))

    (local escaped (string.gsub old-text "([%%%^%$%(%)%.%[%]%*%+%-%?])" "%%%1"))
    (local (updated count) (string.gsub content escaped new-text))
    (when (= count 0)
        (error (.. "edit_file did not find old-text in " path)))

    (local (write-ok write-err) (pcall binding.write-file target updated))
    (if (not write-ok)
        (error (.. "edit_file failed to write " path ": " write-err)))

    {:tool tool-name
     :path path
     :replacements count})

{:name tool-name
 :description "Replace exact occurrences of old-text with new-text in a file."
 :parameters {:type "object"
              :properties {:path {:type "string"
                                  :description "Absolute or relative file path to edit"}
                           :old-text {:type "string"
                                      :description "Exact text to replace"}
                           :new-text {:type "string"
                                      :description "Replacement text"}}
              :required ["path" "old-text" "new-text"]
              :additionalProperties false}
 :strict true
 :call edit-file}
