(local tests [])
(local fs (require :fs))
(local tempfile (require :tempfile))
(local PathPolicy (require :repo/path-policy))

(var temp-counter 0)
(local test-root "/tmp/space/tests/repo-path-policy")

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local d (fs.join-path test-root (.. "path-policy-" (os.time) "-" temp-counter)))
  (when (not (fs.exists (fs.parent d)))
    (fs.create-dirs (fs.parent d)))
  d)

(fn with-worktree [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local result (f dir))
  (fs.remove-all dir)
  result)

(fn validate-relative-path []
  (with-worktree (fn [root]
    (assert (PathPolicy.validate-path-segments "src/main.cpp"))
    (assert (PathPolicy.validate-path-segments "a/b/c/d.fnl"))
    (assert (PathPolicy.validate-path-segments "single-file")))))

(fn reject-absolute-path []
  (with-worktree (fn [root]
    (local (ok _err) (pcall PathPolicy.validate-path-segments "/etc/passwd"))
    (assert (not ok) "should reject absolute path"))))

(fn reject-dot-dot []
  (with-worktree (fn [root]
    (local (ok _err) (pcall PathPolicy.validate-path-segments "../secret"))
    (assert (not ok) "should reject .. segment"))))

(fn reject-nul-byte []
  (with-worktree (fn [root]
    (local (ok _err) (pcall PathPolicy.validate-path-segments "good\0bad"))
    (assert (not ok) "should reject NUL byte"))))

(fn reject-empty []
  (with-worktree (fn [root]
    (local (ok _err) (pcall PathPolicy.validate-path-segments ""))
    (assert (not ok) "should reject empty path"))))

(fn resolve-path-stays-inside []
  (with-worktree (fn [root]
    (local resolved (PathPolicy.resolve-worktree-path root "src/a.cpp"))
    (assert (string.find resolved root nil (string.len root) true)
            "resolved path should start with worktree root"))))

(fn reject-path-escape []
  (with-worktree (fn [root]
    (local (ok _err) (pcall PathPolicy.resolve-worktree-path root "a/../../etc/passwd"))
    (assert (not ok) "should reject path that escapes via .."))))

(fn validate-read-existing []
  (with-worktree (fn [root]
    (local f (fs.join-path root "test.txt"))
    (fs.write-file f "hello")
    (local resolved (PathPolicy.validate-read root "test.txt"))
    (assert (= resolved (fs.absolute f)) "resolved path should be absolute"))))

(fn validate-read-rejects-missing []
  (with-worktree (fn [root]
    (local (ok _err) (pcall PathPolicy.validate-read root "nonexistent.txt"))
    (assert (not ok) "should reject missing file"))))

(fn validate-read-rejects-git-dir []
  (with-worktree (fn [root]
    (local git-dir (fs.join-path root ".git"))
    (fs.create-dirs git-dir)
    (fs.write-file (fs.join-path git-dir "config") "")
    (local (ok _err) (pcall PathPolicy.validate-read root ".git/config"))
    (assert (not ok) "should reject file inside .git"))))

(fn validate-write-creates-new []
  (with-worktree (fn [root]
    (local resolved (PathPolicy.validate-write root "newfile.txt"))
    (assert (string.find resolved root nil (string.len root) true)
            "resolved should be inside worktree"))))

(fn validate-write-rejects-git []
  (with-worktree (fn [root]
    (local git-dir (fs.join-path root ".git"))
    (fs.create-dirs git-dir)
    (local (ok _err) (pcall PathPolicy.validate-write root ".git/config"))
    (assert (not ok) "should reject write inside .git"))))

(table.insert tests {:name "validate relative path" :fn validate-relative-path})
(table.insert tests {:name "reject absolute path" :fn reject-absolute-path})
(table.insert tests {:name "reject dot dot" :fn reject-dot-dot})
(table.insert tests {:name "reject NUL byte" :fn reject-nul-byte})
(table.insert tests {:name "reject empty path" :fn reject-empty})
(table.insert tests {:name "resolve stays inside worktree" :fn resolve-path-stays-inside})
(table.insert tests {:name "reject path escape" :fn reject-path-escape})
(table.insert tests {:name "validate read existing file" :fn validate-read-existing})
(table.insert tests {:name "validate read rejects missing" :fn validate-read-rejects-missing})
(table.insert tests {:name "validate read rejects .git" :fn validate-read-rejects-git-dir})
(table.insert tests {:name "validate write creates new" :fn validate-write-creates-new})
(table.insert tests {:name "validate write rejects .git" :fn validate-write-rejects-git})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-path-policy"
                       :tests tests})))

{:name "repo-path-policy"
 :tests tests
 :main main}
