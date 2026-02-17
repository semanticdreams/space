(local fs (require :fs))
(local uuid (require :uuid))
(local libtorrent (require :libtorrent))

(fn assert-available []
  (assert libtorrent "libtorrent module missing")
  (assert libtorrent.available
          (.. "libtorrent unavailable: " (or (. libtorrent :missing-reason) "unknown"))))

(fn make-root [suite-name]
  (fs.join-path "/tmp/space/tests" suite-name (uuid.v4)))

(fn with-cleanup [root cb]
  (local (ok result) (pcall cb))
  (when (fs.exists root)
    (fs.remove-all root))
  (if ok
      result
      (error result)))

(fn read-first [items]
  (if (> (# items) 0)
      (. items 1)
      nil))

(fn ensure-dir [path]
  (when (not (fs.exists path))
    (fs.create-dirs path))
  path)

{:assert-available assert-available
 :make-root make-root
 :with-cleanup with-cleanup
 :read-first read-first
 :ensure-dir ensure-dir}
