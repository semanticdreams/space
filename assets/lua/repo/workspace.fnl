(local fs (require :fs))
(local Git (require :repo/git))
(local Remote (require :repo/remote))
(local Store (require :repo/store))
(local Sha256 (require :repo/sha256))
(local Profiles (require :repo/profiles))
(local PathPolicy (require :repo/path-policy))
(local Uuid (require :uuid))

(fn slug [text max-len]
  (var result "")
  (each [c (string.gmatch (string.lower text) ".")]
    (if (string.match c "[%w]")
        (set result (.. result c))
        (string.match c "[%s%-_%.]")
        (set result (.. result "-"))))
  (var trimmed (string.gsub result "^%-*(.-)%-*$" "%1"))
  (if (> (# trimmed) (or max-len 40))
      (string.sub trimmed 1 (or max-len 40))
      trimmed))

(fn compute-file-hashes [_self worktree-path]
  (local files (Git.all-known-files worktree-path))
  (local hashes {})
  (local oversized {})
  (each [_ file (ipairs files)]
    (PathPolicy.resolve-worktree-path worktree-path file)
    (local abs-path (fs.join-path worktree-path file))
    (when (fs.exists abs-path)
      (local info (fs.stat abs-path))
      (when (and (not info.is-dir) (not info.is-symlink))
        (if (< info.size 100000)
            (tset hashes file (.. "sha256:" (Sha256.hash-file abs-path)))
            (tset oversized file true)))))
  (local oversized-keys [])
  (each [k _ (pairs oversized)]
    (table.insert oversized-keys k))
  (table.sort oversized-keys)
  (values hashes oversized-keys))

(fn Workspace [opts]
  (local options (or opts {}))
  (local data-dir (or options.data-dir
                      (error "Workspace requires :data-dir")))
  (local clones-dir (fs.join-path data-dir "clones"))
  (local worktrees-dir (fs.join-path data-dir "worktrees"))
  (local store (Store.Store data-dir))

  (when (not (fs.exists clones-dir))
    (fs.create-dirs clones-dir))
  (when (not (fs.exists worktrees-dir))
    (fs.create-dirs worktrees-dir))

  (fn assert-repo-id [repo-id]
    (assert (= (type repo-id) "string") "repo-id must be a string")
    (assert (string.match repo-id "^[%w%-.]+$")
            (.. "repo-id must match safe format: " (tostring repo-id))))

  (fn clone-path* [repo-id]
    (assert-repo-id repo-id)
    (fs.join-path clones-dir repo-id))

  (fn worktree-path* [repo-id task-id]
    (assert-repo-id repo-id)
    (fs.join-path worktrees-dir repo-id task-id))

  (fn clone-repo [_self url]
    (local parsed (Remote.parse url))
    (local repo-id parsed.repo-id)
    (local existing (store:get-repo repo-id))
    (if existing
        (do
          (assert (and (= existing.host-raw parsed.host-raw)
                       (= existing.owner parsed.owner)
                       (= existing.name parsed.name))
                  (.. "repo-id collision: " repo-id " registered as "
                      existing.owner "/" existing.name " (" (tostring existing.host-raw)
                   "), not " parsed.owner "/" parsed.name " (" (tostring parsed.host-raw) ")"))
           (doto existing
             (tset :remote-url (.. "https://" existing.host-raw "/" existing.owner "/" existing.name ".git"))))
        (do
          (local dest (clone-path* repo-id))
          (when (not (fs.exists dest))
            (fs.create-dirs (fs.parent dest))
            (Git.clone url dest))
          (var branch (Git.default-branch dest))
          (var profile :generic)
          (match (Profiles.detect-space-profile dest)
            :space (set profile :space)
            _ nil)
          (local repo-data
            {:id repo-id
             :remote-url (.. "https://" parsed.host-raw "/" parsed.owner "/" parsed.name ".git")
             :host parsed.host
             :host-key parsed.host-key
             :host-raw parsed.host-raw
             :owner parsed.owner
             :name parsed.name
             :default-branch branch
             :clone-path dest
             :profile profile
             :created-at (os.time)})
          (store:add-repo repo-data)
          repo-data)))

  (fn fetch-repo [_self repo-id]
    (local repo-data (store:get-repo repo-id))
    (assert repo-data (.. "repository not found: " repo-id))
    (Git.fetch repo-data.clone-path)
    repo-data)

  (fn create-task [_self repo-id prompt base-branch]
    (local repo-data (store:get-repo repo-id))
    (assert repo-data (.. "repository not found: " repo-id))
    (local base (or base-branch repo-data.default-branch))
    (fetch-repo nil repo-id)
    (local task-id (.. "task-" (Uuid.v4)))
    (local branch-name (.. "space-agent/" task-id "-" (slug prompt 30)))
    (local wt-path (worktree-path* repo-id task-id))
    (when (not (fs.exists (fs.parent wt-path)))
      (fs.create-dirs (fs.parent wt-path)))
    (Git.worktree-add repo-data.clone-path wt-path branch-name (.. "origin/" base))
    (local base-commit (Git.head-commit wt-path))
    (local file-hashes (compute-file-hashes nil wt-path))
    (local task-data
      {:id task-id
       :repo-id repo-id
       :prompt prompt
       :base-branch base
       :branch branch-name
       :worktree-path wt-path
       :base-commit base-commit
       :file-hashes file-hashes
       :status :working
       :agent-session-id nil
       :created-at (os.time)
       :committed-at nil
       :pr-url nil})
    (store:save-task task-data)
    task-data)

  (fn get-task [_self task-id]
    (store:load-task task-id))

  (fn update-task [_self task-data]
    (store:save-task task-data)
    task-data)

  (fn close-task [_self task-id]
    (local task-data (store:load-task task-id))
    (assert task-data (.. "task not found: " task-id))
    (when (and task-data.worktree-path
               (fs.exists task-data.worktree-path))
      (local repo (store:get-repo task-data.repo-id))
      (assert repo (.. "repository not found: " task-data.repo-id))
      (Git.worktree-remove repo.clone-path task-data.worktree-path))
    (tset task-data :status :closed)
    (store:save-task task-data)
    task-data)

  (fn list-repos [_self]
    (store:list-repos))

  (fn list-tasks [_self repo-id]
    (store:list-tasks repo-id))

  {:compute-file-hashes compute-file-hashes
   :store store
   :clone-repo clone-repo
   :fetch-repo fetch-repo
   :create-task create-task
   :get-task get-task
   :update-task update-task
   :close-task close-task
   :list-repos list-repos
   :list-tasks list-tasks
   :clone-path* clone-path*
   :worktree-path* worktree-path*})

{:Workspace Workspace}
