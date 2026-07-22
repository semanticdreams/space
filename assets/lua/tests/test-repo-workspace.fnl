(local tests [])
(local fs (require :fs))
(local tempfile (require :tempfile))
(local Git (require :repo/git))
(local WorkspaceMod (require :repo/workspace))
(local CountMap (require :count-map))

(var temp-counter 0)
(local test-root "/tmp/space/tests/repo-workspace")

(fn make-data-dir []
  (set temp-counter (+ temp-counter 1))
  (local d (fs.join-path test-root (.. "ws-" (os.time) "-" temp-counter)))
  (when (fs.exists d)
    (fs.remove-all d))
  (fs.create-dirs d)
  d)

(fn setup-bare-repo []
  (local Process (require :process))
  (set temp-counter (+ temp-counter 1))
  (local repo-dir (.. "/tmp/space/tests/repo-ws-bare-" (os.time) "-" temp-counter))
  (when (fs.exists repo-dir)
    (fs.remove-all repo-dir))
  (fs.create-dirs repo-dir)
  (Process.run {:args ["git" "init" "--bare" "--initial-branch=main" repo-dir]
                :merge-stderr true :timeout 30})
  repo-dir)

(fn make-repo-entry [bare-repo data-dir]
  (local clones-dir (fs.join-path data-dir "clones"))
  (when (not (fs.exists clones-dir))
    (fs.create-dirs clones-dir))
  (local repo-id "local-test-repo")
  (local clone-path (fs.join-path clones-dir repo-id))
  (when (fs.exists clone-path)
    (fs.remove-all clone-path))
  (Git.clone bare-repo clone-path)
  (local readme (fs.join-path clone-path "README.md"))
  (fs.write-file readme "# test workspace repo\n")
  (local Process (require :process))
  (Process.run {:args ["git" "-C" clone-path "add" "-A"] :timeout 30 :merge-stderr true})
  (Process.run {:args ["git" "-C" clone-path "commit" "-m" "init"] :timeout 30 :merge-stderr true})
  (Process.run {:args ["git" "-C" clone-path "push" "origin" "main"] :timeout 30 :merge-stderr true})
  (local repo-data
    {:id repo-id
     :remote-url bare-repo
     :host :unknown
     :host-key "unknown"
     :host-raw "unknown"
     :owner "test"
     :name "repo"
     :default-branch "main"
     :clone-path clone-path
     :profile :generic
     :created-at (os.time)})
  repo-data)

(fn with-workspace [f]
  (local data-dir (make-data-dir))
  (local bare-repo (setup-bare-repo))
  (local ws (WorkspaceMod.Workspace {:data-dir data-dir}))
  (local repo-data (make-repo-entry bare-repo data-dir))
  (ws.store:add-repo repo-data)
  (local (ok result) (pcall f ws data-dir bare-repo repo-data))
  (when (fs.exists repo-data.clone-path) (fs.remove-all repo-data.clone-path))
  (when (fs.exists bare-repo) (fs.remove-all bare-repo))
  (when (fs.exists data-dir) (fs.remove-all data-dir))
  (if ok result (error result)))

(fn workspace-clone-and-list-repos []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local repos (ws:list-repos))
    (assert (= (# repos) 1) "should have one repo")
    (local repo (. repos 1))
    (assert (= repo.id repo-data.id) "repo id should match")
    (assert repo.clone-path "repo should have clone-path"))))

(fn workspace-create-task []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local task (ws:create-task repo-data.id "fix the README"))
    (assert task.id "task should have id")
    (assert (= task.repo-id repo-data.id) "task repo-id should match")
    (assert (= task.status :working) "task should be in working status")
    (assert task.worktree-path "task should have worktree path")
    (assert (fs.exists task.worktree-path) "worktree should exist")
    (assert task.file-hashes "task should have file-hashes table")
    (assert (>= (CountMap.count task.file-hashes) 1) "file-hashes should have at least one entry"))))

(fn workspace-create-task-with-branch []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local task (ws:create-task repo-data.id "another task" "main"))
    (assert (= (type task.branch) "string") "branch should be string")
    (local branch-prefix (string.sub task.branch 1 12))
    (assert (= branch-prefix "space-agent/")
            (.. "branch should have prefix, got: '" (tostring task.branch) "'"))
    (assert (not= nil (string.find task.branch task.id 1 true))
             (.. "branch should contain task id " task.id ", branch=" task.branch)))))

(fn workspace-task-status []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local task (ws:create-task repo-data.id "status test"))
    (local loaded (ws:get-task task.id))
    (assert (= loaded.id task.id) "retrieved task should match"))))

(fn workspace-close-task []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local task (ws:create-task repo-data.id "close test"))
    (local closed (ws:close-task task.id))
    (assert (= closed.status :closed) "task should be closed"))))

(fn workspace-read-file-in-task []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local task (ws:create-task repo-data.id "read test"))
    (local PathPolicy (require :repo/path-policy))
    (local resolved (PathPolicy.validate-read task.worktree-path "README.md"))
    (assert (fs.exists resolved) "README should exist")
    (local content (fs.read-file resolved))
    (assert (> (# content) 0) "README should have content"))))

(fn workspace-compute-file-hashes []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local task (ws:create-task repo-data.id "hash test"))
    (local hashes (ws:compute-file-hashes task.worktree-path))
    (assert hashes "should return hashes table")
    (assert (>= (CountMap.count hashes) 1) "should compute at least one file hash")
    (local readme-hash (. hashes "README.md"))
    (assert readme-hash "README.md should have a hash")
    (assert (string.find readme-hash "^sha256:") "hash should have sha256: prefix"))))

(fn workspace-compute-file-hashes-oversized []
  (with-workspace (fn [ws _data-dir _bare-repo repo-data]
    (local task (ws:create-task repo-data.id "oversized test"))
    (local parts [])
    (for [_ 1 200000]
      (table.insert parts "x"))
    (fs.write-file (fs.join-path task.worktree-path "large.bin") (table.concat parts ""))
    (local (hashes oversized-keys) (ws:compute-file-hashes task.worktree-path))
    (assert (not (. hashes "large.bin")) "oversized file should not be in hashes")
    (assert (>= (CountMap.count hashes) 1) "small files should still be hashed")
    (var found-large nil)
    (each [_ f (ipairs oversized-keys)]
      (when (= f "large.bin")
        (set found-large true)))
    (assert found-large "large.bin should be in oversized-keys from compute-file-hashes"))))

(fn workspace-clone-repo-rejects-url-collision []
  (local data-dir (make-data-dir))
  (local ws (WorkspaceMod.Workspace {:data-dir data-dir}))
  (local Remote (require :repo/remote))
  (local url-a "https://github.com/foo-bar/repo")
  (local parsed-a (Remote.parse url-a))
  (local repo-id parsed-a.repo-id)
  (local entry-a
    {:id repo-id
     :remote-url url-a
     :host parsed-a.host
     :host-key parsed-a.host-key
     :host-raw parsed-a.host-raw
     :owner parsed-a.owner
     :name parsed-a.name
     :default-branch "main"
     :clone-path "/nonexistent/a"
     :profile :generic
     :created-at (os.time)})
  (ws.store:add-repo entry-a)
  (local url-b "https://github.com/foo_bar/repo")
  (local (ok err) (pcall ws.clone-repo ws url-b))
  (assert (not ok) "should reject collision")
  (assert (string.find (tostring err) "repo%-id collision") "error should mention repo-id collision")
  (fs.remove-all data-dir))
(fn workspace-clone-repo-rejects-unknown-host-collision []
  (local data-dir (make-data-dir))
  (local ws (WorkspaceMod.Workspace {:data-dir data-dir}))
  (local Remote (require :repo/remote))
  (local url-a "https://my-host.org/same-owner/repo")
  (local parsed-a (Remote.parse url-a))
  (local repo-id parsed-a.repo-id)
  (local entry-a
    {:id repo-id
     :remote-url url-a
     :host parsed-a.host
     :host-key parsed-a.host-key
     :host-raw parsed-a.host-raw
     :owner parsed-a.owner
     :name parsed-a.name
     :default-branch "main"
     :clone-path "/nonexistent/a"
     :profile :generic
     :created-at (os.time)})
  (ws.store:add-repo entry-a)
  (local url-b "https://my_host.org/same-owner/repo")
  (local (ok err) (pcall ws.clone-repo ws url-b))
  (assert (not ok) "should reject collision across unknown hosts")
  (assert (string.find (tostring err) "repo%-id collision") "error should mention repo-id collision")
  (fs.remove-all data-dir))
(table.insert tests {:name "clone-repo rejects unknown host collision" :fn workspace-clone-repo-rejects-unknown-host-collision})

(table.insert tests {:name "clone-repo rejects url collision" :fn workspace-clone-repo-rejects-url-collision})

(fn workspace-clone-repo-accepts-url-aliases []
  (local data-dir (make-data-dir))
  (local ws (WorkspaceMod.Workspace {:data-dir data-dir}))
  (local Remote (require :repo/remote))
  (local url-a "https://github.com/test-owner/repo")
  (local parsed-a (Remote.parse url-a))
  (local repo-id parsed-a.repo-id)
  (local entry-a
    {:id repo-id
     :remote-url url-a
     :host parsed-a.host
     :host-key parsed-a.host-key
     :host-raw parsed-a.host-raw
     :owner parsed-a.owner
     :name parsed-a.name
     :default-branch "main"
     :clone-path "/nonexistent/a"
     :profile :generic
     :created-at (os.time)})
  (ws.store:add-repo entry-a)
  (local url-b "https://github.com/test-owner/repo.git")
  (local result (ws:clone-repo url-b))
  (assert result "should return existing entry for URL alias")
  (assert (= result.id repo-id) "should return same repo")
  (assert (= result.owner "test-owner") "should return same owner")
  (assert (= result.name "repo") "should return same repo name")
  (fs.remove-all data-dir))
(table.insert tests {:name "clone-repo accepts url aliases same repo" :fn workspace-clone-repo-accepts-url-aliases})

(table.insert tests {:name "clone and list repos" :fn workspace-clone-and-list-repos})
(table.insert tests {:name "create task" :fn workspace-create-task})
(table.insert tests {:name "create task with branch" :fn workspace-create-task-with-branch})
(table.insert tests {:name "get task by id" :fn workspace-task-status})
(table.insert tests {:name "close task" :fn workspace-close-task})
(table.insert tests {:name "read file in task worktree" :fn workspace-read-file-in-task})
(table.insert tests {:name "compute file hashes" :fn workspace-compute-file-hashes})
(table.insert tests {:name "compute file hashes oversized tracking" :fn workspace-compute-file-hashes-oversized})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-workspace"
                       :tests tests})))

{:name "repo-workspace"
 :tests tests
 :main main}
