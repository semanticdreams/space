(local tests [])
(local fs (require :fs))
(local tempfile (require :tempfile))
(local Git (require :repo/git))

(var temp-counter 0)
(local test-root "/tmp/space/tests/repo-git")

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local d (fs.join-path test-root (.. "repo-git-" (os.time) "-" temp-counter)))
  (when (not (fs.exists (fs.parent d)))
    (fs.create-dirs (fs.parent d)))
  d)

(fn with-temp-repo [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local Process (require :process))
  (Process.run {:args ["git" "init" "--bare" "--initial-branch=main" dir] :merge-stderr true :timeout 30})
  (var committed? false)
  (local clone-dir (.. dir "-clone"))
  (when (fs.exists clone-dir)
    (fs.remove-all clone-dir))
  (Git.clone dir clone-dir)
  (local readme (fs.join-path clone-dir "README.md"))
  (fs.write-file readme "# test repo\n")
  (Process.run {:args ["git" "-C" clone-dir "add" "-A"] :timeout 30 :merge-stderr true})
  (Process.run {:args ["git" "-C" clone-dir "commit" "-m" "init"] :timeout 30 :merge-stderr true})
  (Process.run {:args ["git" "-C" clone-dir "push" "origin" "main"] :timeout 30 :merge-stderr true})
  (set committed? true)
  (local result (f dir clone-dir))
  (fs.remove-all dir)
  (when (fs.exists clone-dir)
    (fs.remove-all clone-dir))
  result)

(fn git-fetch-works []
  (with-temp-repo (fn [bare-path clone-path]
    (Git.fetch clone-path))))

(fn git-default-branch []
  (with-temp-repo (fn [bare-path clone-path]
    (local branch (Git.default-branch clone-path))
    (assert (= branch "main") (.. "expected main, got " (tostring branch))))))

(fn git-status-empty []
  (with-temp-repo (fn [bare-path clone-path]
    (local s (Git.status clone-path))
    (assert (= s "") "status should be empty on clean repo"))))

(fn git-status-modified []
  (with-temp-repo (fn [bare-path clone-path]
    (fs.write-file (fs.join-path clone-path "README.md") "# modified\n")
    (local s (Git.status clone-path))
    (assert (string.find s "README.md") "status should show modified README"))))

(fn git-diff-empty []
  (with-temp-repo (fn [bare-path clone-path]
    (local d (Git.diff clone-path))
    (assert (= d "") "diff should be empty on clean repo"))))

(fn git-diff-shows-changes []
  (with-temp-repo (fn [bare-path clone-path]
    (fs.write-file (fs.join-path clone-path "README.md") "# modified\n")
    (local d (Git.diff clone-path))
    (assert (and (> (# d) 0) (string.find d "README.md"))
            "diff should show changes"))))

(fn git-head-commit []
  (with-temp-repo (fn [bare-path clone-path]
    (local sha (Git.head-commit clone-path))
    (assert (= (# sha) 40) "commit SHA should be 40 chars")
    (each [c (string.gmatch sha ".")]
      (assert (string.find "0123456789abcdef" c 1 true) "SHA should be hex")))))

(fn git-tracked-files []
  (with-temp-repo (fn [bare-path clone-path]
    (local files (Git.tracked-files clone-path))
    (assert (>= (# files) 1) "should have at least one tracked file")
    (var found-readme false)
    (each [_ f (ipairs files)]
      (when (= f "README.md")
        (set found-readme true)))
    (assert found-readme "should include README.md"))))

(fn git-commit-works []
  (with-temp-repo (fn [bare-path clone-path]
    (fs.write-file (fs.join-path clone-path "newfile.txt") "hello\n")
    (Git.add-all clone-path)
    (Git.commit clone-path "add newfile")
    (local s (Git.status clone-path))
    (assert (= s "") "status should be clean after commit"))))

(fn git-add-all-commits-push []
  (with-temp-repo (fn [bare-path clone-path]
    (fs.write-file (fs.join-path clone-path "data.txt") "data\n")
    (Git.add-all clone-path)
    (Git.commit clone-path "add data")
    (Git.push clone-path "main"))))

(fn git-default-branch-fallback-slashes []
  (with-temp-repo (fn [bare-path clone-path]
    (local Process (require :process))
    (Process.run {:args ["git" "-C" clone-path "symbolic-ref" "refs/remotes/origin/HEAD" "--delete"]
                  :timeout 30 :merge-stderr true})
    (Process.run {:args ["git" "-C" clone-path "checkout" "-b" "release/2026"]
                  :timeout 30 :merge-stderr true})
    (local branch (Git.default-branch clone-path))
    (assert (= branch "release/2026") (.. "expected release/2026, got " (tostring branch))))))

(table.insert tests {:name "git fetch works" :fn git-fetch-works})
(table.insert tests {:name "git default branch" :fn git-default-branch})
(table.insert tests {:name "git status empty" :fn git-status-empty})
(table.insert tests {:name "git status modified" :fn git-status-modified})
(table.insert tests {:name "git diff empty" :fn git-diff-empty})
(table.insert tests {:name "git diff shows changes" :fn git-diff-shows-changes})
(table.insert tests {:name "git head commit" :fn git-head-commit})
(table.insert tests {:name "git tracked files" :fn git-tracked-files})
(table.insert tests {:name "git commit works" :fn git-commit-works})
(table.insert tests {:name "git add commit push flow" :fn git-add-all-commits-push})
(table.insert tests {:name "git default branch fallback with slashes" :fn git-default-branch-fallback-slashes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-git"
                       :tests tests})))

{:name "repo-git"
 :tests tests
 :main main}
