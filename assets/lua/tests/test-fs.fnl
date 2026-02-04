(local tests [])
(local fs (require :fs))

(var temp-counter 0)
(local fs-temp-root (fs.join-path "/tmp/space/tests" "fs-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path fs-temp-root (.. "fs-test-" (os.time) "-" temp-counter)))

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

(fn list-names [entries]
  (local names [])
  (each [_ entry (ipairs entries)]
    (table.insert names entry.name))
  names)

(fn contains? [items needle]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item needle)
      (set found true)))
  found)

(fn fs-write-read-stat []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "note.txt"))
    (fs.write-file file "hello world")
    (assert (= (fs.read-file file) "hello world"))
    (local info (fs.stat file))
    (assert info.exists "file should exist")
    (assert info.is-file "file should be regular")
    (assert (= info.name "note.txt"))
    (assert (= info.size 11))
    (assert (not info.is-dir))
    (assert (= (fs.parent file) root)))))

(fn fs-list-dir-hidden-filter []
  (with-temp-dir (fn [root]
    (local visible (fs.join-path root "visible.txt"))
    (local hidden (fs.join-path root ".secret"))
    (fs.write-file visible "v")
    (fs.write-file hidden "h")
    (local entries (fs.list-dir root false))
    (local names (list-names entries))
    (assert (contains? names "visible.txt") "visible entry missing")
    (assert (not (contains? names ".secret")) "hidden entry should be filtered"))))

(fn fs-copy-rename-remove []
  (with-temp-dir (fn [root]
    (local source (fs.join-path root "source.txt"))
    (fs.write-file source "contents")
    (local copy (fs.join-path root "copy.txt"))
    (fs.copy-file source copy true)
    (assert (= (fs.read-file copy) "contents"))
    (local renamed (fs.join-path root "renamed.txt"))
    (fs.rename copy renamed)
    (assert (not (fs.exists copy)) "copy path should be gone after rename")
    (assert (fs.exists renamed) "renamed file should exist")
    (assert (fs.remove renamed) "remove should report true")
    (assert (not (fs.exists renamed)) "renamed file should be removed"))))

(table.insert tests {:name "fs write/read/stat" :fn fs-write-read-stat})
(table.insert tests {:name "fs list_dir filters hidden files" :fn fs-list-dir-hidden-filter})
(table.insert tests {:name "fs copy and rename" :fn fs-copy-rename-remove})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fs"
                       :tests tests})))

{:name "fs"
 :tests tests
 :main main}
