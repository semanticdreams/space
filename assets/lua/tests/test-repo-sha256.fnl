(local tests [])
(local fs (require :fs))
(local tempfile (require :tempfile))
(local Sha256 (require :repo/sha256))

(fn sha256-empty-string []
  (local h (Sha256.hash ""))
  (assert (= (# h) 64) "sha256 hex should be 64 chars")
  (assert (= h "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
          "sha256 of empty string should match known value"))

(fn sha256-known-value []
  (local h (Sha256.hash "hello"))
  (assert (= h "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")))

(fn sha256-binary-content []
  (var content "")
  (for [i 0 255]
    (set content (.. content (string.char i))))
  (local h (Sha256.hash content))
  (assert (= (# h) 64) "sha256 should produce 64 hex chars for binary content"))

(fn sha256-file []
  (local h (tempfile.NamedTemporaryFile {:prefix "sha256test_" :suffix ".txt"}))
  (fs.write-file h.path "test content\n")
  (local file-hash (Sha256.hash-file h.path))
  (local direct-hash (Sha256.hash "test content\n"))
  (assert (= file-hash direct-hash) "file hash should match content hash")
  (h:drop))

(fn sha256-rejects-nil []
  (local (ok _err) (pcall Sha256.hash nil))
  (assert (not ok) "should reject nil"))

(table.insert tests {:name "sha256 of empty string" :fn sha256-empty-string})
(table.insert tests {:name "sha256 of known value" :fn sha256-known-value})
(table.insert tests {:name "sha256 of binary content" :fn sha256-binary-content})
(table.insert tests {:name "sha256 file hashing" :fn sha256-file})
(table.insert tests {:name "sha256 rejects nil" :fn sha256-rejects-nil})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-sha256"
                       :tests tests})))

{:name "repo-sha256"
 :tests tests
 :main main}
