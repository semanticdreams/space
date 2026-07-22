(local tests [])
(local fs (require :fs))
(local json (require :json))
(local Process (require :process))

(fn assert-exit-code [result label]
  (assert (= result.exit-code 0)
          (.. label ": " (or result.stderr result.stdout ""))))

(fn live-github-e2e []
  (assert (= (or (os.getenv "SPACE_REPO_LIVE_GITHUB") "") "1")
          "SPACE_REPO_LIVE_GITHUB must be set to 1")

  (local auth-status (Process.run {:args ["gh" "auth" "status"]
                                   :timeout 10 :merge-stderr true}))
  (assert-exit-code auth-status "gh not authenticated")

  (local user-result (Process.run {:args ["gh" "api" "user" "--jq" ".login"]
                                   :timeout 10 :merge-stderr true}))
  (assert-exit-code user-result "failed to get GitHub username")
  (local owner (string.gsub (or user-result.stdout "") "%s+$" ""))
  (assert (> (# owner) 0) "GitHub username is empty")

  (local timestamp (os.time))
  (math.randomseed timestamp)
  (local random-suffix (.. (tostring (math.random 10000 99999))))
  (local repo-name (.. "space-live-e2e-" timestamp "-" random-suffix))
  (local full-repo (.. owner "/" repo-name))
  (local remote-url (.. "https://github.com/" full-repo ".git"))

  (local test-root "/tmp/space/tests/live-github-e2e")
  (when (not (fs.exists test-root))
    (fs.create-dirs test-root))

  (local seed-dir (fs.join-path test-root (.. "seed-" timestamp "-" random-suffix)))
  (local data-dir (fs.join-path test-root (.. "data-" timestamp "-" random-suffix)))

  (var cleanup-actions [])
  (fn add-cleanup! [label action]
    (table.insert cleanup-actions {:label label :action action}))

  (add-cleanup! "remove-data-dir" (fn [] (fs.remove-all data-dir)))
  (add-cleanup! "remove-seed-dir" (fn [] (fs.remove-all seed-dir)))

  (var pr-number nil)
  (var task-branch nil)

  (fn run-cleanup! []
    (var errors [])
    (for [i (# cleanup-actions) 1 -1]
      (local step (. cleanup-actions i))
      (local (ok err) (pcall step.action))
      (when (not ok)
        (table.insert errors (.. step.label ": " (tostring err)))))
    errors)

  (fn run-all! []
    ;; Phase 0: create seed repo
    (fs.create-dirs seed-dir)
    (fs.create-dirs (fs.join-path seed-dir "src"))
    (fs.write-file (fs.join-path seed-dir "README.md")
                   "# space-live-e2e\n\nTest repo for Repository Workbench live E2E tests.\n")
    (fs.write-file (fs.join-path seed-dir "src/main.fnl")
                   "{:main (fn [] (print :hello))}\n")
    (assert-exit-code (Process.run {:args ["git" "-C" seed-dir "init" "-b" "main"]
                                    :timeout 30 :merge-stderr true})
                      "git init")
    (assert-exit-code (Process.run {:args ["git" "-C" seed-dir "add" "-A"]
                                    :timeout 30 :merge-stderr true})
                      "git add")
    (assert-exit-code (Process.run {:args ["git" "-C" seed-dir "commit" "-m" "initial commit"]
                                    :timeout 30 :merge-stderr true})
                      "git commit")

    ;; Register GitHub cleanup before creating the repo, so cleanup runs even on partial create failure.
    ;; Registration order: close-pr first (reversed runs first), delete-branch next, delete-repo last.
    (add-cleanup! "delete-repo" (fn []
      (assert-exit-code (Process.run {:args ["gh" "repo" "delete" full-repo "--yes"]
                                       :timeout 30 :merge-stderr true})
                        "gh repo delete")))
    (add-cleanup! "delete-branch" (fn []
      (when task-branch
        (assert-exit-code (Process.run {:args ["gh" "api"
                                               (.. "repos/" full-repo "/git/refs/heads/" task-branch)
                                               "-X" "DELETE"]
                                        :timeout 30 :merge-stderr true})
                          (.. "delete branch " task-branch)))))
    (add-cleanup! "close-pr" (fn []
      (when pr-number
        (assert-exit-code (Process.run {:args ["gh" "pr" "close" pr-number "--repo" full-repo]
                                        :timeout 30 :merge-stderr true})
                          (.. "close PR #" pr-number)))))

    (assert-exit-code (Process.run {:args ["gh" "repo" "create" full-repo
                                           "--private"
                                           (.. "--source=" seed-dir)
                                           "--remote=origin"
                                           "--push"]
                                    :timeout 60 :merge-stderr true})
                      "gh repo create")

    ;; Phase 1: set up app and exercise every adapter
    (fs.create-dirs data-dir)
    (local app {:user-data-dir data-dir})
    (local {: ToolAdapterRegistry} (require :llm/presets/tool-adapters))
    (local adapters (ToolAdapterRegistry {}))
    (local BuiltinRepo (require :llm/presets/builtins/repo))
    (BuiltinRepo.register {:tool-adapters adapters})

    (local clone-def (adapters:resolve "repo.clone" app))
    (local clone-result (json.loads (clone-def.run {:url remote-url})))
    (assert clone-result.id "clone should return repository id")
    (assert (= clone-result.host :github)
            (.. "host should be github, got " (tostring clone-result.host)))
    (assert (= clone-result.owner owner)
            (.. "owner should match, got " (tostring clone-result.owner)))
    (assert (= clone-result.name repo-name)
            (.. "name should match, got " (tostring clone-result.name)))
    (assert (= clone-result.default-branch "main") "default branch should be main")

    (local create-task-def (adapters:resolve "repo.create-task" app))
    (local task-result (json.loads (create-task-def.run {:repo-id clone-result.id
                                                          :prompt "live e2e test task"})))
    (assert task-result.id "task should have an id")
    (assert (string.find task-result.branch "space-agent/" 1 true)
            (.. "branch should have space-agent/ prefix, got " task-result.branch))
    (assert (= task-result.status :working) "task status should be working")
    (set task-branch task-result.branch)

    (local read-def (adapters:resolve "repo.read-file" app))
    (local readme-result (json.loads (read-def.run {:task-id task-result.id
                                                     :path "README.md"})))
    (assert readme-result.content "read-file should return content")
    (assert readme-result.sha256 "read-file should return sha256")
    (local readme-hash readme-result.sha256)

    (local patch "--- a/README.md\n+++ b/README.md\n@@ -1,3 +1,3 @@\n-# space-live-e2e\n+# space-live-e2e (patched)\n \n Test repo for Repository Workbench live E2E tests.\n")
    (local patch-def (adapters:resolve "repo.apply-patch" app))
    (local patch-result (json.loads (patch-def.run {:task-id task-result.id
                                                     :patch patch
                                                     :expected-hashes {"README.md" readme-hash}})))
    (assert patch-result.files-touched "apply-patch should return files-touched")
    (assert (. patch-result.file-hashes "README.md")
            "post-patch hashes should include README.md")

    (local diff-def (adapters:resolve "repo.diff" app))
    (local diff-result (json.loads (diff-def.run {:task-id task-result.id})))
    (assert diff-result.file-hashes "diff result should include file-hashes")

    (local commit-def (adapters:resolve "repo.commit" app))
    (local commit-result (json.loads (commit-def.run {:task-id task-result.id
                                                       :message "e2e test commit: patch README"})))
    (assert (= commit-result.status :committed) "status should be committed")
    (assert commit-result.committed-at "should have committed-at timestamp")

    (local push-def (adapters:resolve "repo.push" app))
    (local push-result (json.loads (push-def.run {:task-id task-result.id})))
    (assert (= push-result.status :pushed) "status should be pushed")

    (local pr-def (adapters:resolve "repo.open-pr" app))
    (local pr-result (json.loads (pr-def.run {:task-id task-result.id
                                               :title "e2e test PR"
                                               :body "Automated E2E test pull request from Repository Workbench."})))
    (assert pr-result.pr-url "open-pr should return pr-url")
    (assert (string.find pr-result.pr-url "github.com" 1 true)
            "pr-url should be a GitHub URL")
    (assert (= pr-result.status :pr-open) "status should be pr-open")
    (set pr-number (string.match pr-result.pr-url "/pull/(%d+)$"))
    (assert pr-number "should extract PR number from URL")

    (local pr-status-def (adapters:resolve "repo.pr-status" app))
    (local pr-status-result (json.loads (pr-status-def.run {:task-id task-result.id})))
    (assert pr-status-result.pr-url "pr-status should return pr-url")
    true)

  (local (ok err-msg) (pcall run-all!))
  (local cleanup-errors (run-cleanup!))

  (if (and ok (= (# cleanup-errors) 0))
      true
      ok
      (error (.. "live e2e cleanup failed: " (table.concat cleanup-errors ", ")))
      (do
        (when (> (# cleanup-errors) 0)
          (io.stderr:write (.. "also: cleanup issues: " (table.concat cleanup-errors ", ") "\n")))
        (error (.. "live e2e test failed: " (tostring err-msg))))))

(table.insert tests {:name "live-github-e2e: clone,task,read,patch,diff,commit,push,open-pr,pr-status"
                     :fn live-github-e2e})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "live-repo-github-e2e"
                       :tests tests})))

{:name "live-repo-github-e2e"
 :tests tests
 :main main}
