(local Process (require :process))

(fn assert-git-result [result label]
  (when result.timed-out
    (error (.. label " timed out")))
  (when result.signal
    (error (.. label " exited from signal " (tostring result.signal) ": " (or result.stderr ""))))
  (when (not= result.exit-code 0)
    (error (.. label " exited with code " (tostring result.exit-code) ": " (or result.stderr result.stdout)))))

(fn git-run [opts]
  (local options (or opts {}))
  (local clone-path (or options.clone-path
                        (error "git-run requires :clone-path")))
  (local args (or options.args (error "git-run requires :args")))
  (assert (= (type args) "table") "git-run :args must be a table")
  (local full-args ["git" "-C" clone-path])
  (each [_ a (ipairs args)]
    (table.insert full-args a))
  (local process-opts {:args full-args
                       :timeout (or options.timeout 60)
                       :merge-stderr true})
  (when options.cwd
    (set process-opts.cwd options.cwd))
  (when options.env
    (set process-opts.env options.env))
  (Process.run process-opts))

(fn clone [url path]
  (local result (Process.run {:args ["git" "clone" url path]
                              :timeout 300
                              :merge-stderr true}))
  (assert-git-result result "git clone"))

(fn fetch [clone-path]
  (local result (git-run {:clone-path clone-path
                          :args ["fetch" "--prune" "origin"]
                          :timeout 120}))
  (assert-git-result result "git fetch"))

(fn default-branch [clone-path]
  (var result (git-run {:clone-path clone-path
                         :args ["symbolic-ref" "refs/remotes/origin/HEAD"]
                         :timeout 30}))
  (var ref "")
  (when (= result.exit-code 0)
    (set ref (or (string.match (or result.stdout "") "refs/remotes/origin/([^\n]+)") "")))
  (when (= (# ref) 0)
    (set result (git-run {:clone-path clone-path
                           :args ["branch" "--show-current"]
                           :timeout 30}))
    (when (= result.exit-code 0)
      (set ref (string.match (or result.stdout "") "^%s*(.-)%s*$"))))
  (assert (> (# ref) 0) (.. "could not determine default branch for " clone-path))
  ref)

(fn worktree-add [clone-path worktree-path branch base-ref]
  (local args ["worktree" "add" worktree-path "-b" branch base-ref])
  (local result (git-run {:clone-path clone-path
                          :args args
                          :timeout 60}))
  (assert-git-result result "git worktree add"))

(fn worktree-remove [clone-path worktree-path]
  (local result (git-run {:clone-path clone-path
                          :args ["worktree" "remove" worktree-path "--force"]
                          :timeout 30}))
  (assert-git-result result "git worktree remove"))

(fn status [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "status" "--porcelain=v1" "-z"]
                               :timeout 30
                               :merge-stderr true}))
  (assert-git-result result "git status --porcelain -z")
  result.stdout)

(fn diff [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "diff"]
                              :timeout 30
                              :merge-stderr true}))
  (assert-git-result result "git diff")
  result.stdout)

(fn diff-staged [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "diff" "--cached"]
                              :timeout 30
                              :merge-stderr true}))
  (assert-git-result result "git diff --cached")
  result.stdout)

(fn add-all [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "add" "-A"]
                              :timeout 30
                              :merge-stderr true}))
  (assert-git-result result "git add"))

(fn commit [worktree-path message]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "commit" "-m" message]
                              :timeout 30
                              :merge-stderr true}))
  (assert-git-result result "git commit"))

(fn push [worktree-path branch]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "push" "origin" branch]
                              :timeout 60
                              :merge-stderr true}))
  (assert-git-result result "git push"))

(fn push-force [worktree-path branch]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "push" "--force-with-lease" "origin" branch]
                              :timeout 60
                              :merge-stderr true}))
  (assert-git-result result "git push --force-with-lease"))

(fn current-branch [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "branch" "--show-current"]
                              :timeout 30
                              :merge-stderr true}))
  (assert-git-result result "git branch --show-current")
  (var branch (or (string.match (or result.stdout "") "^([^\n]+)") ""))
  (var trimmed (string.gsub branch "^%s*(.-)%s*$" "%1"))
  trimmed)

(fn head-commit [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "rev-parse" "HEAD"]
                              :timeout 30
                              :merge-stderr true}))
  (assert-git-result result "git rev-parse HEAD")
  (var sha (or (string.match (or result.stdout "") "([%x]+)") ""))
  (string.lower sha))

(fn tracked-files [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "ls-files" "-z"]
                               :timeout 30
                               :merge-stderr true}))
  (assert-git-result result "git ls-files -z")
  (local files [])
  (each [line (string.gmatch (or result.stdout "") "([^\0]+)")]
    (when (> (# line) 0)
      (table.insert files line)))
  files)

(fn all-known-files [worktree-path]
  (local Process (require :process))
  (local result (Process.run {:args ["git" "-C" worktree-path "ls-files" "-z" "--cached" "--others" "--exclude-standard"]
                               :timeout 30
                               :merge-stderr true}))
  (assert-git-result result "git ls-files -z --cached --others")
  (local files [])
  (each [line (string.gmatch (or result.stdout "") "([^\0]+)")]
    (when (> (# line) 0)
      (table.insert files line)))
  files)

{:git-run git-run
 :assert-git-result assert-git-result
 :clone clone
 :fetch fetch
 :default-branch default-branch
 :worktree-add worktree-add
 :worktree-remove worktree-remove
 :status status
 :diff diff
 :diff-staged diff-staged
 :add-all add-all
 :commit commit
 :push push
 :push-force push-force
 :current-branch current-branch
 :head-commit head-commit
 :tracked-files tracked-files
 :all-known-files all-known-files}
