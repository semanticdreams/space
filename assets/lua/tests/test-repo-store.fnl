(local tests [])
(local fs (require :fs))
(local tempfile (require :tempfile))

(var temp-counter 0)
(local test-root "/tmp/space/tests/repo-store")

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local d (fs.join-path test-root (.. "store-" (os.time) "-" temp-counter)))
  (when (not (fs.exists (fs.parent d)))
    (fs.create-dirs (fs.parent d)))
  d)

(fn test-task-id-rejects-traversal []
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local Store (require :repo/store))
  (local s (Store.Store dir))
  (local (ok1 _) (pcall s.load-task s "../registry"))
  (assert (not ok1) "should reject dot-dot in task-id")
  (local (ok2 _) (pcall s.load-task s "malformed-id"))
  (assert (not ok2) "should reject non-task-prefixed id")
  (local (ok3 _) (pcall s.load-task s "task-my-task-id-123"))
  (assert ok3 "valid task-id should not throw (file may not exist)")
  (local (ok4 _) (pcall s.save-task s {:id "../registry" :repo-id "x" :prompt "x" :branch "x"}))
  (assert (not ok4) "save-task should reject dot-dot in task-id")
  (fs.remove-all dir))

(table.insert tests {:name "task-id rejects traversal" :fn test-task-id-rejects-traversal})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-store"
                       :tests tests})))

{:name "repo-store"
 :tests tests
 :main main}
