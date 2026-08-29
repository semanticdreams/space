(local tests [])
(local fs (require :fs))
(local process (require :process))

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

(fn string-contains? [haystack needle]
  (not= nil (string.find (tostring haystack) needle 1 true)))

(fn repeated-text [chunk count]
  (local parts [])
  (for [i 1 count]
    (table.insert parts chunk))
  (table.concat parts))

(fn assert-read-text-window-error [description f]
  (local (ok err) (pcall f))
  (assert (not ok) description)
  (assert (string-contains? err "fs.read_text_window")
          (.. description ": expected fs.read_text_window in " (tostring err))))

(fn space-bin []
  (if (fs.exists "./build/space")
      "./build/space"
      "./space"))

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

(fn fs-read-text-window-bounded-range []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "window.txt"))
    (fs.write-file file "abcdef")
    (local window (fs.read-text-window file 2 3))
    (assert (= window.path file))
    (assert (= window.offset 2))
    (assert (= window.next-offset 5))
    (assert (= window.size 6))
    (assert (= window.bytes-read 3))
    (assert (not window.eof))
    (assert (= window.text "cde"))
    (assert (= window.truncated-utf8 false)))))

(fn fs-read-text-window-caps-max-bytes []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "large.txt"))
    (fs.write-file file (repeated-text "a" 262145))
    (local window (fs.read-text-window file 0 999999))
    (assert (= window.bytes-read 262144))
    (assert (= (# window.text) 262144))
    (assert (= window.next-offset 262144)))))

(fn fs-read-text-window-sanitizes-display-text []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "binary.txt"))
    (fs.write-file file (.. "a" (string.char 0) "b" (string.char 255) "c"))
    (local window (fs.read-text-window file 0 5))
    (assert (not (string-contains? window.text (string.char 0))) "text should not contain NUL")
    (assert (string-contains? window.text "�") "text should contain replacement character"))))

(fn fs-read-text-window-preserves-trailing-ascii-after-invalid-lead []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "malformed.txt"))
    (fs.write-file file (.. (string.char 0xE2) "("))
    (local window (fs.read-text-window file 0 2))
    (assert (= window.text "�(") "invalid lead should be replaced and trailing ASCII preserved")
    (assert (= window.truncated-utf8 false) "invalid lead plus ASCII should not be marked truncated"))))

(fn fs-read-text-window-rejects-invalid-arguments []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-fs:invalid-argument-main"]
                              :env {:SPACE_DISABLE_AUDIO "1"
                                    :SPACE_ASSETS_PATH (os.getenv "SPACE_ASSETS_PATH")
                                    :FENNEL_PATH (os.getenv "FENNEL_PATH")
                                    :FENNEL_MACRO_PATH (os.getenv "FENNEL_MACRO_PATH")}
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "invalid-argument child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn invalid-argument-main []
  (assert-read-text-window-error "empty path should fail"
                                 (fn [] (fs.read-text-window "" 0 1)))
  (assert-read-text-window-error "negative offset should fail"
                                 (fn [] (fs.read-text-window "/tmp/space-fs-window.txt" -1 1)))
  (assert-read-text-window-error "zero max-bytes should fail"
                                 (fn [] (fs.read-text-window "/tmp/space-fs-window.txt" 0 0))))

(table.insert tests {:name "fs write/read/stat" :fn fs-write-read-stat})
(table.insert tests {:name "fs list_dir filters hidden files" :fn fs-list-dir-hidden-filter})
(table.insert tests {:name "fs copy and rename" :fn fs-copy-rename-remove})
(table.insert tests {:name "fs read-text-window reads bounded range" :fn fs-read-text-window-bounded-range})
(table.insert tests {:name "fs read-text-window caps max bytes" :fn fs-read-text-window-caps-max-bytes})
(table.insert tests {:name "fs read-text-window sanitizes display text" :fn fs-read-text-window-sanitizes-display-text})
(table.insert tests {:name "fs read-text-window preserves trailing ascii after invalid lead" :fn fs-read-text-window-preserves-trailing-ascii-after-invalid-lead})
(table.insert tests {:name "fs read-text-window rejects invalid arguments" :fn fs-read-text-window-rejects-invalid-arguments})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fs"
                       :tests tests})))

{:name "fs"
  :tests tests
  :main main
  :invalid-argument-main invalid-argument-main}
