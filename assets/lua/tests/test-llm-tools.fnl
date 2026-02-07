(local LlmTools (require :llm/tools/init))
(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "llm-tools"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "llm-tools-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result) (pcall f dir))
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn names [entries]
    (local collected [])
    (each [_ entry (ipairs entries)]
        (table.insert collected entry.name))
    collected)

(fn contains? [items needle]
    (var found false)
    (each [_ item (ipairs items)]
        (when (= item needle)
            (set found true)))
    found)

(fn schema-includes-list-dir []
    (local openai (LlmTools.openai-tools))
    (var target nil)
    (each [_ tool (ipairs openai)]
        (when (= tool.name "list_dir")
            (set target tool)))
    (assert target "openai tool list should include list_dir")
    (assert (= target.type "function"))
    (assert target.parameters "list_dir should expose parameters")
    (local dir-prop (. target.parameters.properties "directory"))
    (assert (= dir-prop.type "string"))
    (assert (= (. target.parameters.required 1) "directory"))
    (assert (= (. target.parameters.required 2) "include_hidden"))
    (assert (= target.parameters.additionalProperties false)))

(fn schema-includes-fs-tools []
    (local openai (LlmTools.openai-tools))
    (var read nil)
    (var write nil)
    (var delete nil)
    (var apply nil)
    (var edit nil)
    (each [_ tool (ipairs openai)]
        (when (= tool.name "read_file")
            (set read tool))
        (when (= tool.name "write_file")
            (set write tool))
        (when (= tool.name "delete_file")
            (set delete tool))
        (when (= tool.name "apply_patch")
            (set apply tool))
        (when (= tool.name "edit_file")
            (set edit tool)))
    (assert (and read write delete apply edit)
            "openai tool list should include read_file, write_file, delete_file, apply_patch, edit_file")
    (assert (= (. read.parameters.required 1) "path"))
    (assert (= (. write.parameters.required 1) "path"))
    (assert (= (. write.parameters.required 2) "content"))
    (assert (= (. delete.parameters.required 1) "path"))
    (assert (= (. apply.parameters.required 1) "path"))
    (assert (= (. apply.parameters.required 2) "patch"))
    (assert (= (. apply.parameters.required 3) "allow_create"))
    (assert (= read.parameters.additionalProperties false))
    (assert (= write.parameters.additionalProperties false))
    (assert (= delete.parameters.additionalProperties false))
    (assert (= apply.parameters.additionalProperties false))
    (assert (= (. (. apply.parameters.properties :allow_create) :default) true)))

(fn schema-includes-bash []
    (local openai (LlmTools.openai-tools))
    (var bash nil)
    (each [_ tool (ipairs openai)]
        (when (= tool.name "bash")
            (set bash tool)))
    (assert bash "openai tool list should include bash")
    (assert (= bash.type "function"))
    (assert (= (. bash.parameters.required 1) "command"))
    (assert (= (. bash.parameters.required 2) "timeout"))
    (assert (= (. (. bash.parameters.properties "command") "type") "string"))
    (assert (= (. (. bash.parameters.properties "timeout") "type") "number"))
    (assert (= bash.parameters.additionalProperties false)))

(fn exercise-list-dir [root]
    (local visible (fs.join-path root "note.txt"))
    (local hidden (fs.join-path root ".secret"))
    (local subdir (fs.join-path root "folder"))
    (fs.write-file visible "visible")
    (fs.write-file hidden "hidden")
    (fs.create-dirs subdir)

    (local result (LlmTools.call "list_dir" {:directory root}))
    (local result-names (names result.entries))
    (assert (contains? result-names "note.txt"))
    (assert (contains? result-names "folder"))
    (assert (not (contains? result-names ".secret")))
    (assert (= result.include_hidden false))

    (local with-hidden (LlmTools.call "list_dir" {:directory root
                                                  :include_hidden true}))
    (local hidden-names (names with-hidden.entries))
    (assert (contains? hidden-names ".secret"))
    (assert (= with-hidden.include_hidden true)))

(fn list-dir-filters-hidden []
    (with-temp-dir exercise-list-dir))

(fn exercise-read-write-delete [root]
    (local file (fs.join-path root "note.txt"))
    (local write-result (LlmTools.call "write_file" {:path file
                                                    :content "hello"}))
    (assert (= write-result.tool "write_file"))
    (assert (= write-result.bytes 5))
    (assert (fs.exists file))

    (local read-result (LlmTools.call "read_file" {:path file}))
    (assert (= read-result.tool "read_file"))
    (assert (= read-result.content "hello"))
    (assert (= read-result.size 5))

    (local delete-result (LlmTools.call "delete_file" {:path file}))
    (assert (= delete-result.tool "delete_file"))
    (assert delete-result.deleted)
    (assert (not (fs.exists file)) "file should be removed"))

(fn read-write-delete-roundtrip []
    (with-temp-dir exercise-read-write-delete))

(fn apply-patch-creates-file [root]
    (local file (fs.join-path root "note.txt"))
    (local patch (table.concat ["*** Begin Patch"
                                (.. "*** Add File: " file)
                                "@@ -0,0 +1,2 @@"
                                "+hello"
                                "+world"
                                "*** End Patch"] "\n"))
    (local result (LlmTools.call "apply_patch" {:path file :patch patch}))
    (assert (= result.tool "apply_patch"))
    (assert (= result.hunks_applied 1) (.. "hunks_applied=" (tostring result.hunks_applied)))
    (assert (fs.exists file))
    (local content (fs.read-file file))
    (assert (= content "hello\nworld\n") (.. "content=" content)))

(fn apply-patch-updates-with-context [root]
    (local file (fs.join-path root "note.txt"))
    (fs.write-file file "alpha\nbeta\ngamma\n")
    (local patch (table.concat ["*** Begin Patch"
                                (.. "*** Update File: " file)
                                "@@ -1,3 +1,3 @@"
                                " alpha"
                                "-beta"
                                "+BETA"
                                " gamma"
                                "*** End Patch"] "\n"))
    (LlmTools.call "apply_patch" {:path file :patch patch})
    (local content (fs.read-file file))
    (assert (= content "alpha\nBETA\ngamma\n") (.. "content=" content)))

(fn apply-patch-respects-missing-newline [root]
    (local file (fs.join-path root "note.txt"))
    (fs.write-file file "line one")
    (local patch (table.concat ["*** Begin Patch"
                                (.. "*** Update File: " file)
                                "@@ -1 +1 @@"
                                "-line one"
                                "+line two"
                                "\\ No newline at end of file"
                                "*** End Patch"] "\n"))
    (LlmTools.call "apply_patch" {:path file :patch patch})
    (local content (fs.read-file file))
    (assert (= content "line two") (.. "content=" content)))

(fn apply-patch-suite []
    (with-temp-dir (fn [root]
        (apply-patch-creates-file root)
        (apply-patch-updates-with-context root)
        (apply-patch-respects-missing-newline root))))

(fn edit-file-replaces-text []
    (with-temp-dir (fn [root]
        (local file (fs.join-path root "note.txt"))
        (fs.write-file file "alpha beta alpha\nalpha\n")
        (local result (LlmTools.call "edit_file" {:path file
                                                  :old-text "alpha"
                                                  :new-text "ALPHA"}))
        (assert (= result.tool "edit_file"))
        (assert (= result.replacements 3))
        (local content (fs.read-file file))
        (assert (= content "ALPHA beta ALPHA\nALPHA\n") (.. "content=" content)))))

(fn assert-bash-cwd [root]
    (local rooted (LlmTools.call "bash" {:command "printf '%s' \"$PWD\""
                                         :timeout 1
                                         :cwd root}))
    (assert (= rooted.exit_code 0))
    (assert (= rooted.stdout root)))

(fn bash-runs-command []
    (local result (LlmTools.call "bash" {:command "printf 'hello'"
                                         :timeout 1}))
    (when (or (not (= result.exit_code 0))
              (not (= result.stdout "hello"))
              (not (= result.timed_out false)))
        (print (.. "[DEBUG] bash result exit_code=" (tostring result.exit_code)
                   " timed_out=" (tostring result.timed_out)
                   " stdout=" (tostring result.stdout)
                   " stderr=" (tostring result.stderr))))
    (assert (= result.exit_code 0))
    (assert (= result.stdout "hello"))
    (assert (= result.timed_out false))
    (with-temp-dir assert-bash-cwd))

(table.insert tests {:name "llm-tools exposes list_dir schema" :fn schema-includes-list-dir})
(table.insert tests {:name "llm-tools exposes fs tool schemas" :fn schema-includes-fs-tools})
(table.insert tests {:name "llm-tools exposes bash schema" :fn schema-includes-bash})
(table.insert tests {:name "llm-tools list_dir supports hidden toggle" :fn list-dir-filters-hidden})
(table.insert tests {:name "llm-tools read/write/delete roundtrip" :fn read-write-delete-roundtrip})
(table.insert tests {:name "llm-tools apply_patch covers creation and context" :fn apply-patch-suite})
(table.insert tests {:name "llm-tools bash runs command" :fn bash-runs-command})
(table.insert tests {:name "llm-tools edit_file replaces text" :fn edit-file-replaces-text})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "llm-tools"
                       :tests tests})))

{:name "llm-tools"
 :tests tests
 :main main}
