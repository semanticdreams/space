(local fs (require :fs))
(local json (require :json))
(local PathPolicy (require :repo/path-policy))
(local Sha256 (require :repo/sha256))
(local Git (require :repo/git))
(local Profiles (require :repo/profiles))
(local Checks (require :repo/checks))
(local CountMap (require :count-map))
(local Display (require :repo/display))

(fn ensure-workspace [app]
  (when (not app.repo-workspace)
    (local WorkspaceMod (require :repo/workspace))
    (local data-dir (fs.join-path app.user-data-dir "repositories"))
    (set app.repo-workspace (WorkspaceMod.Workspace {:data-dir data-dir})))
  app.repo-workspace)

(fn repo-available! [app]
  (when app.agent-presets
    (local old-ctx (app.agent-presets:get-context))
    (set old-ctx.repos-available? true)
    (app.agent-presets:set-context old-ctx)))

(fn register-repo-adapters [adapters]
  (adapters:register
    {:id "repo.clone"
     :mcp-name "space_repo_clone"
     :description "Clone and register a remote Git repository."
     :inputSchema {:type "object"
                   :properties {:url {:type "string" :description "Remote git URL to clone"}}
                    :required ["url"]}
      :make-run (fn [app]
                  (fn [args]
                    (local ws (ensure-workspace app))
                    (local repo (ws:clone-repo args.url))
                    (repo-available! app)
                    (json.dumps (Display.safe-repo-summary repo))))
     :managed-source "repo.clone"})

  (adapters:register
    {:id "repo.list"
     :mcp-name "space_repo_list"
     :description "List registered repositories."
     :inputSchema {:type "object" :properties {}}
      :make-run (fn [app]
                  (fn [_args]
                    (local ws (ensure-workspace app))
                    (local repos (ws:list-repos))
                    (local safe-repos [])
                    (each [_ repo (ipairs repos)]
                       (table.insert safe-repos (Display.safe-repo-summary repo)))
                    (json.dumps safe-repos)))
     :managed-source "repo.list"})

  (adapters:register
    {:id "repo.create-task"
     :mcp-name "space_repo_create_task"
     :description "Create a task worktree and branch for a repo."
     :inputSchema {:type "object"
                   :properties {:repo-id {:type "string" :description "Repository ID to work on"}
                                :prompt {:type "string" :description "Agent prompt describing the task"}
                                :base-branch {:type "string" :description "Base branch (defaults to repo default)"}}
                   :required ["repo-id" "prompt"]}
     :make-run (fn [app]
                 (fn [args]
                   (local ws (ensure-workspace app))
                   (local task (ws:create-task args.repo-id args.prompt args.base-branch))
                   (json.dumps {:id task.id
                                :repo-id task.repo-id
                                :branch task.branch
                                :base-branch task.base-branch
                                :base-commit task.base-commit
                                :status task.status
                                 :file-count (CountMap.count (or task.file-hashes {}))
                                :created-at task.created-at})))
     :managed-source "repo.create-task"})

  (adapters:register
    {:id "repo.status"
     :mcp-name "space_repo_status"
     :description "Git status for a task worktree."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}}
                   :required ["task-id"]}
     :make-run (fn [app]
                 (fn [args]
                   (local ws (ensure-workspace app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                    (local status-output (Git.status task.worktree-path))
                    (local raw-tokens [])
                    (each [token (string.gmatch (or status-output "") "([^\0]+)")]
                      (when (> (# token) 0)
                        (table.insert raw-tokens token)))
                    (local files [])
                    (var i 1)
                    (while (<= i (# raw-tokens))
                      (local entry (. raw-tokens i))
                      (local code (string.sub entry 1 2))
                      (local rest (string.sub entry 4))
                      (if (and (or (string.find code "R" 1 true)
                                   (string.find code "C" 1 true))
                               (<= (+ i 1) (# raw-tokens)))
                          (do
                            (local old-path (. raw-tokens (+ i 1)))
                            (table.insert files {:code code :file rest :old-file old-path :renamed true})
                            (set i (+ i 2)))
                          (do
                            (table.insert files {:code code :file rest})
                            (set i (+ i 1)))))
                   (json.dumps {:task-id args.task-id
                                :branch task.branch
                                :status task.status
                                :files files
                                :raw status-output})))
     :managed-source "repo.status"})

  (adapters:register
    {:id "repo.diff"
     :mcp-name "space_repo_diff"
     :description "Unstaged and staged diff for a task worktree, with per-file hashes."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}}
                   :required ["task-id"]}
     :make-run (fn [app]
                 (fn [args]
                   (local ws (ensure-workspace app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                     (local unstaged (Git.diff task.worktree-path))
                     (local staged (Git.diff-staged task.worktree-path))
                     (local tracked-files (Git.tracked-files task.worktree-path))
                     (local tracked-set {})
                     (each [_ f (ipairs tracked-files)]
                       (tset tracked-set f true))
                     (local untracked-content {})
                     (local known-files-untracked (Git.all-known-files task.worktree-path))
                     (each [_ file (ipairs known-files-untracked)]
                       (PathPolicy.resolve-worktree-path task.worktree-path file)
                       (local abs-path (fs.join-path task.worktree-path file))
                       (when (not (. tracked-set file))
                         (when (fs.exists abs-path)
                           (local info (fs.stat abs-path))
                           (when (and (not info.is-dir) (not info.is-symlink))
                             (if (< info.size 100000)
                                 (tset untracked-content file (fs.read-file abs-path))
                                 (tset untracked-content file {:truncated true
                                                                :size info.size
                                                                :note "file exceeds 100KB limit"}))))))
                     (local (file-hashes oversized-keys) (ws:compute-file-hashes task.worktree-path))
                     (json.dumps {:task-id args.task-id
                                 :unstaged-diff unstaged
                                 :staged-diff staged
                                 :file-hashes file-hashes
                                 :untracked-files untracked-content
                                 :oversized-files oversized-keys})))
     :managed-source "repo.diff"})

  (adapters:register
    {:id "repo.read-file"
     :mcp-name "space_repo_read_file"
     :description "Read a repo-relative file. Returns content and sha256 hash."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}
                                :path {:type "string" :description "Repo-relative file path"}
                                :offset {:type "integer" :description "Line offset (1-based)"}
                                :limit {:type "integer" :description "Max lines to return"}}
                   :required ["task-id" "path"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                    (local resolved (PathPolicy.validate-read task.worktree-path args.path))
                     (local file-info (fs.stat resolved))
                     (assert (< file-info.size 100000)
                             (.. "file too large (" file-info.size " bytes) for read-file"))
                    (local content (fs.read-file resolved))
                   (var result-content content)
                   (when (or args.offset args.limit)
                     (local lines [])
                     (each [line (string.gmatch content "([^\n]*)\n?")]
                       (table.insert lines line))
                     (local start (or args.offset 1))
                     (var finish (or (when args.limit (+ start args.limit -1)) (# lines)))
                     (when (> finish (# lines))
                       (set finish (# lines)))
                     (var sliced [])
                     (for [i start finish]
                       (table.insert sliced (. lines i)))
                     (set result-content (table.concat sliced "\n")))
                   (local content-hash (.. "sha256:" (Sha256.hash content)))
                   (json.dumps {:content result-content
                                :sha256 content-hash
                                :path args.path
                                :size (# content)})))
     :managed-source "repo.read-file"})

  (adapters:register
    {:id "repo.search"
     :mcp-name "space_repo_search"
     :description "Search for files and text content inside a task worktree."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}
                                :query {:type "string" :description "Text or glob pattern to search for"}
                                :path {:type "string" :description "Subdirectory to search in (repo-relative)"}}
                   :required ["task-id" "query"]}
      :make-run (fn [_app]
                  (fn [args]
                    (local ws (ensure-workspace _app))
                    (local task (ws:get-task args.task-id))
                    (assert task (.. "task not found: " args.task-id))
                    (var search-dir task.worktree-path)
                    (when args.path
                      (set search-dir (PathPolicy.resolve-worktree-path task.worktree-path args.path)))
                    (local results [])
                    (fn search-recursive [dir depth]
                      (when (> depth 20)
                        (lua "return nil"))
                      (local entries (fs.list-dir dir))
                       (each [_ entry (ipairs entries)]
                         (when (and entry.name (not= entry.name ".git"))
                           (if entry.is-symlink
                              nil  ;; skip symlinks — do not follow
                              entry.is-dir
                              (search-recursive entry.path (+ depth 1))
                              entry.is-file
                              (do
                                (local rel-path (string.sub entry.path (+ (# task.worktree-path) 2)))
                                (PathPolicy.validate-read task.worktree-path rel-path)
                                (var name-match? false)
                                (var content-match? false)
                                (when (or (string.find (string.lower rel-path) (string.lower args.query) 1 true)
                                          (string.find (string.lower entry.name) (string.lower args.query) 1 true))
                                  (set name-match? true))
                                (when (< entry.size 100000)
                                  (local (ok content) (pcall fs.read-file entry.path))
                                  (when (and ok (string.find (string.lower content) (string.lower args.query) 1 true))
                                    (set content-match? true)))
                                (when (or name-match? content-match?)
                                  (table.insert results {:path rel-path
                                                         :name entry.name
                                                         :size entry.size
                                                         :name-match name-match?
                                                         :content-match content-match?})))))))
                    (search-recursive search-dir 0)
                    (json.dumps {:task-id args.task-id
                                 :query args.query
                                 :result-count (# results)
                                 :results results})))
     :managed-source "repo.search"})

  (adapters:register
    {:id "repo.apply-patch"
     :mcp-name "space_repo_apply_patch"
     :description "Apply a unified diff patch to files in a task worktree. Requires expected-hashes."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}
                                :patch {:type "string" :description "Unified diff patch text"}
                                :expected-hashes {:type "object"
                                                 :description "Map of file path to expected sha256:hex hash for every touched existing file"}}
                   :required ["task-id" "patch" "expected-hashes"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                    (assert task (.. "task not found: " args.task-id))
                    (local expected-hashes (or args.expected-hashes {}))
                     (local toucher (require :repo.patch-toucher))
                     (assert (not (toucher.has-symlink-modes args.patch))
                             "patches that create or modify symlinks are not allowed")
                     (local touched (toucher.touched-files args.patch))
                    (assert (and touched (> (# touched) 0)) "patch does not touch any files")
                     (var failed-paths [])
                      (each [_ file-path (ipairs touched)]
                        (PathPolicy.validate-write task.worktree-path file-path)
                        (local full-path (fs.join-path task.worktree-path file-path))
                        (when (fs.exists full-path)
                          (local file-info (fs.stat full-path))
                          (local expected (. expected-hashes file-path))
                          (if (>= file-info.size 100000)
                              (table.insert failed-paths {:path file-path :size file-info.size :error (.. "file too large (" file-info.size " bytes) for patching")})
                              (do
                                (local current-hash (.. "sha256:" (Sha256.hash-file full-path)))
                                (if (not expected)
                                    (table.insert failed-paths {:path file-path :current current-hash :error "missing expected hash"})
                                    (not= current-hash expected)
                                    (table.insert failed-paths {:path file-path :expected expected :current current-hash}))))))
                    (when (> (# failed-paths) 0)
                      (error (.. "hash mismatch: " (json.dumps failed-paths))))
                    (local tmpfile (require :tempfile))
                    (local pf (tmpfile.NamedTemporaryFile {:prefix "repo-patch-" :suffix ".diff"}))
                    (local Process (require :process))
                     (local (ok apply-result) (pcall
                                              (fn []
                                                (fs.write-file pf.path args.patch)
                                                (Process.run {:args ["git" "-C" task.worktree-path "apply" "--whitespace=nowarn" pf.path]
                                                               :timeout 30
                                                               :merge-stderr true}))))
                     (when (not ok)
                       (pf:drop)
                       (error (.. "git apply failed (process): " (tostring apply-result))))
                     (when (not= apply-result.exit-code 0)
                       (pf:drop)
                       (error (.. "git apply failed: " (or apply-result.stderr apply-result.stdout))))
                     (local (post-ok post-err)
                       (pcall (fn []
                                (local (hashes oversized-keys) (ws:compute-file-hashes task.worktree-path))
                                (set task.file-hashes hashes)
                                (ws:update-task task)
                                (json.dumps {:task-id args.task-id
                                             :files-touched touched
                                             :file-hashes task.file-hashes
                                             :oversized-files oversized-keys}))))
                     (if post-ok
                         (do
                           (pf:drop)
                           post-err)
                         (do
                           (local rev-result (Process.run {:args ["git" "-C" task.worktree-path "apply" "-R" pf.path]
                                                            :timeout 30
                                                            :merge-stderr true}))
                           (pf:drop)
                           (if (and (= rev-result.exit-code 0) (not rev-result.timed-out) (not rev-result.signal))
                               (error (.. "post-apply validation failed (rolled back): " (tostring post-err)))
                               (error (.. "post-apply validation failed AND rollback failed: " (tostring post-err)
                                          " (rollback: " (or rev-result.stderr rev-result.stdout "unknown error") ")")))))))
      :managed-source "repo.apply-patch"})

  (adapters:register
    {:id "repo.run-check"
     :mcp-name "space_repo_run_check"
     :description "Run a profile-defined check and return output."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}
                                :check-id {:type "string" :description "Check ID to run"}}
                   :required ["task-id" "check-id"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                   (local repo (ws.store:get-repo task.repo-id))
                   (assert repo (.. "repo not found: " task.repo-id))
                   (local checks (Profiles.profile-checks repo.profile repo.clone-path task.worktree-path))
                   (var matched nil)
                   (each [_ c (ipairs checks)]
                     (when (= c.id args.check-id)
                       (set matched c)))
                   (assert matched (.. "check not found: " args.check-id))
                   (local raw-result (Checks.run-check matched task.worktree-path))
                   (local parsed (Checks.check-result raw-result))
                    (json.dumps {:task-id args.task-id
                                 :check-id args.check-id
                                 :label matched.label
                                 :status parsed.status
                                 :exit-code parsed.exit-code
                                 :timed-out parsed.timed-out
                                 :signal parsed.signal
                                 :stdout parsed.stdout
                                 :stderr parsed.stderr
                                 :duration-ms parsed.duration-ms})))
      :managed-source "repo.run-check"})

  (adapters:register
    {:id "repo.list-checks"
     :mcp-name "space_repo_list_checks"
     :description "List available checks for the repo profile."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}}
                   :required ["task-id"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                   (local repo (ws.store:get-repo task.repo-id))
                   (assert repo (.. "repo not found: " task.repo-id))
                   (local checks (Profiles.profile-checks repo.profile repo.clone-path task.worktree-path))
                   (local result [])
                   (each [_ c (ipairs checks)]
                     (table.insert result {:id c.id :label c.label :timeout c.timeout}))
                   (json.dumps {:task-id args.task-id
                                :profile repo.profile
                                :checks result})))
     :managed-source "repo.list-checks"})

  (adapters:register
    {:id "repo.commit"
     :mcp-name "space_repo_commit"
     :description "Commit the current task diff with a message."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}
                                :message {:type "string" :description "Commit message"}}
                   :required ["task-id" "message"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                   (Git.add-all task.worktree-path)
                   (Git.commit task.worktree-path args.message)
                   (set task.committed-at (os.time))
                   (set task.status :committed)
                   (ws:update-task task)
                   (json.dumps {:task-id args.task-id
                                :status task.status
                                :committed-at task.committed-at})))
     :managed-source "repo.commit"})

  (adapters:register
    {:id "repo.push"
     :mcp-name "space_repo_push"
     :description "Push the task branch to origin."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}}
                   :required ["task-id"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                   (Git.push task.worktree-path task.branch)
                   (set task.status :pushed)
                   (ws:update-task task)
                   (json.dumps {:task-id args.task-id
                                :status task.status
                                :branch task.branch})))
     :managed-source "repo.push"})

  (adapters:register
    {:id "repo.open-pr"
     :mcp-name "space_repo_open_pr"
     :description "Open a pull request (draft by default)."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}
                                :title {:type "string" :description "PR title"}
                                :body {:type "string" :description "PR body"}
                                :draft {:type "boolean" :description "Create as draft PR (default true)"}}
                   :required ["task-id" "title" "body"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                   (local repo (ws.store:get-repo task.repo-id))
                   (assert repo (.. "repo not found: " task.repo-id))
                   (assert (= repo.host :github)
                           (.. "PRs only supported for GitHub repos, got " (tostring repo.host)))
                   (local Process (require :process))
                   (var pr-args ["gh" "pr" "create"
                                 "--repo" (.. repo.owner "/" repo.name)
                                 "--head" task.branch
                                 "--base" task.base-branch
                                 "--title" args.title
                                 "--body" args.body])
                   (when (not= args.draft false)
                     (table.insert pr-args "--draft"))
                   (local result (Process.run {:args pr-args
                                                :timeout 30
                                                :merge-stderr true
                                                :cwd task.worktree-path}))
                   (when (not= result.exit-code 0)
                     (error (.. "gh pr create failed: " (or result.stderr result.stdout))))
                    (local pr-url (or (string.match (or result.stdout "")
                                                    "(https?://[^\n]+)") ""))
                    (assert (> (# pr-url) 0) "gh pr create did not return a PR URL")
                   (set task.pr-url pr-url)
                   (set task.status :pr-open)
                   (ws:update-task task)
                   (json.dumps {:task-id args.task-id
                                :status task.status
                                :pr-url pr-url})))
     :managed-source "repo.open-pr"})

  (adapters:register
    {:id "repo.pr-status"
     :mcp-name "space_repo_pr_status"
     :description "Poll CI status for the task's PR."
     :inputSchema {:type "object"
                   :properties {:task-id {:type "string" :description "Task ID"}}
                   :required ["task-id"]}
      :make-run (fn [_app]
                 (fn [args]
                   (local ws (ensure-workspace _app))
                   (local task (ws:get-task args.task-id))
                   (assert task (.. "task not found: " args.task-id))
                    (assert (> (# (or task.pr-url "")) 0) "task has no PR URL")
                   (local Process (require :process))
                   (local result (Process.run {:args ["gh" "pr" "view" task.pr-url
                                                      "--json" "statusCheckRollup"
                                                      "--jq" ".statusCheckRollup"]
                                                :timeout 30
                                                :merge-stderr true}))
                   (when (not= result.exit-code 0)
                     (error (.. "gh pr view failed: " (or result.stderr result.stdout))))
                   (json.dumps {:task-id args.task-id
                                :pr-url task.pr-url
                                :ci-status (or result.stdout "")})))
     :managed-source "repo.pr-status"})
  true)

(fn register-repo-presets [mgr]
  (mgr:register
    {:name "repo-bootstrap-tools"
     :group "repo"
     :default-state :auto
     :risk :shell
     :contexts [{:surface :any}]
     :tool-ids ["repo.clone" "repo.list"]
     :system-prompt
     "Repository Workbench allows cloning and working on remote git repositories."})

  (mgr:register
    {:name "repo-discover-tools"
     :group "repo"
     :default-state :auto
     :risk :filesystem-read
     :contexts [{:surface :any :repos-available? true}]
     :tool-ids ["repo.status" "repo.read-file" "repo.search" "repo.diff" "repo.list-checks"]
     :system-prompt
     "Use repository discovery tools to explore the task worktree: read files, search code, and inspect git state."})

  (mgr:register
    {:name "repo-edit-tools"
     :group "repo"
     :default-state :auto
     :risk :filesystem-write
     :contexts [{:surface :any :repos-available? true}]
     :tool-ids ["repo.apply-patch" "repo.create-task" "repo.commit"]
     :system-prompt
     "Repository edit tools allow patching files in the task worktree. All patches require expected-hashes to prevent race conditions."})

  (mgr:register
    {:name "repo-check-tools"
     :group "repo"
     :default-state :auto
     :risk :shell
     :contexts [{:surface :any :repos-available? true}]
     :tool-ids ["repo.run-check"]
     :system-prompt
     "Repository check tools run profile-defined checks (build, test, lint) inside the task worktree."})

  (mgr:register
    {:name "repo-pr-tools"
     :group "repo"
     :default-state :auto
     :risk :shell
     :contexts [{:surface :any :repos-available? true}]
     :tool-ids ["repo.push" "repo.open-pr" "repo.pr-status"]
     :system-prompt
     "Repository PR tools push branches and open pull requests. Only push and open PRs after checks pass."}))

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-repo-adapters adapters))
  (when (and (= (type mgr) :table) (. mgr :register))
    (register-repo-presets mgr))
  true)

{:register register
 :repo-available! repo-available!}
