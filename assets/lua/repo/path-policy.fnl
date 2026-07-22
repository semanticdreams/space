(local fs (require :fs))

(fn validate-path-segments [path]
  (assert (= (type path) "string") "path must be a string")
  (assert (> (# path) 0) "path must not be empty")
  (assert (not (string.find path "\0" 1 true)) "path contains NUL byte")
  (assert (not (string.match path "^/")) "path must not be absolute")
  (assert (not (or (string.match path "^%a:[\\/]")))
          "path must not be absolute")
  (each [segment (string.gmatch path "[^/]+")]
    (assert (not= segment "..") "path must not contain '..' segment"))
  true)

(fn check-no-symlink-ancestors [absolute-path worktree-root]
  (var current absolute-path)
  (local root (fs.absolute worktree-root))
  (while (and (> (# current) (# root))
               (not= current root)
               (not= current (fs.parent root)))
    (local stat (fs.stat current))
    (when (and stat.exists stat.is-symlink)
      (error (.. "ancestor is a symlink: " current)))
    (set current (fs.parent current))))

(fn resolve-worktree-path [worktree-root repo-relative-path]
  (validate-path-segments repo-relative-path)
  (local joined (fs.join-path worktree-root repo-relative-path))
  (local root-absolute (fs.absolute worktree-root))
  (local resolved-absolute (fs.absolute joined))
  (assert (and (>= (# resolved-absolute) (# root-absolute))
               (= (string.sub resolved-absolute 1 (# root-absolute)) root-absolute)
               (or (= (# resolved-absolute) (# root-absolute))
                   (= (string.sub resolved-absolute (+ (# root-absolute) 1)
                                  (+ (# root-absolute) 1)) "/")))
          (.. "path escapes worktree: " repo-relative-path))
  (check-no-symlink-ancestors resolved-absolute worktree-root)
  resolved-absolute)

(fn check-no-symlinks [absolute-path]
  (var current absolute-path)
  (var ok true)
  (while (and ok (> (# current) 0))
    (local stat (fs.stat current))
    (when (and stat.exists stat.is-symlink)
      (set ok false))
    (when ok
      (set current (fs.parent current))))
  (assert ok (.. "path contains symlink component: " absolute-path)))

(fn validate-read [worktree-root path]
  (local resolved (resolve-worktree-path worktree-root path))
  (assert (fs.exists resolved) (.. "file not found: " path))
  (local stat (fs.stat resolved))
  (assert (not stat.is-dir) (.. "cannot read directory: " path))
  (assert (not stat.is-symlink) (.. "cannot read symlink: " path))
  (check-no-symlink-ancestors resolved worktree-root)
  (assert (not (string.find resolved "/%.git/"))
          "cannot read files inside .git/")
  (assert (not (string.match resolved "/%.git$"))
          "cannot read .git")
  resolved)

(fn validate-write [worktree-root path]
  (local resolved (resolve-worktree-path worktree-root path))
  (assert (not (string.find resolved "/%.git/"))
          "cannot write files inside .git/")
  (assert (not (string.match resolved "/%.git$"))
          "cannot write .git")
  (when (fs.exists resolved)
    (local stat (fs.stat resolved))
    (assert (not stat.is-symlink) (.. "cannot write to symlink: " path))
    (assert (not stat.is-dir) (.. "cannot write to directory: " path)))
  (check-no-symlink-ancestors resolved worktree-root)
  resolved)

{:validate-path-segments validate-path-segments
 :resolve-worktree-path resolve-worktree-path
 :check-no-symlinks check-no-symlinks
 :check-no-symlink-ancestors check-no-symlink-ancestors
 :validate-read validate-read
 :validate-write validate-write}
