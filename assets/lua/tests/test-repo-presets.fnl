(local tests [])
(local fs (require :fs))
(local json (require :json))
(local tempfile (require :tempfile))
(local Git (require :repo/git))
(local Sha256 (require :repo/sha256))
(local CountMap (require :count-map))
(local WorkspaceMod (require :repo/workspace))
(local {: ToolAdapterRegistry} (require :llm/presets/tool-adapters))
(local {: PresetRegistry} (require :llm/presets/registry))
(local {: PresetManager} (require :llm/presets/init))
(local sysinfo (require :sysinfo))
(local platform-os (. (sysinfo.platform) :os))
(local is-windows (= platform-os "windows"))
(local is-ci (os.getenv "CI"))
(local skip-module (or is-windows is-ci))

(var temp-counter 0)
(local test-root "/tmp/space/tests/repo-presets")

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local d (fs.join-path test-root (.. "presets-" (os.time) "-" temp-counter)))
  (when (not (fs.exists (fs.parent d)))
    (fs.create-dirs (fs.parent d)))
  d)

(fn setup-test-env []
  (local data-dir (make-temp-dir))
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local repos-dir (fs.join-path data-dir "repositories"))
  (fs.create-dirs repos-dir)
  (local clones-dir (fs.join-path repos-dir "clones"))
  (fs.create-dirs clones-dir)
  (local worktrees-dir (fs.join-path repos-dir "worktrees"))
  (fs.create-dirs worktrees-dir)

  (local bare-repo (fs.join-path data-dir "bare.git"))
  (local Process (require :process))
  (Process.run {:args ["git" "init" "--bare" "--initial-branch=main" bare-repo]
                :merge-stderr true :timeout 30})

  (local ws (WorkspaceMod.Workspace {:data-dir repos-dir}))
  (local clone-path (fs.join-path clones-dir "local-test-repo"))
  (Git.clone bare-repo clone-path)
  (fs.create-dirs (fs.join-path clone-path "src"))
  (fs.write-file (fs.join-path clone-path "README.md") "# readme\n")
  (fs.write-file (fs.join-path clone-path "src/main.fnl") "{:main (fn [] (print :hello))}\n")
  (Process.run {:args ["git" "-C" clone-path "add" "-A"] :timeout 30 :merge-stderr true})
  (Process.run {:args ["git" "-C" clone-path "commit" "-m" "init"] :timeout 30 :merge-stderr true})
  (Process.run {:args ["git" "-C" clone-path "push" "origin" "main"] :timeout 30 :merge-stderr true})

  (local repo-data
    {:id "local-test-repo"
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
  (ws.store:add-repo repo-data)

  (local app {:user-data-dir data-dir})

  (local adapters (ToolAdapterRegistry {}))
  (local BuiltinRepo (require :llm/presets/builtins/repo))
  (BuiltinRepo.register {:tool-adapters adapters})

  {:app app :adapters adapters :clone-path clone-path :bare-repo bare-repo
   :data-dir data-dir :repos-dir repos-dir :ws ws :repo-data repo-data})

(fn teardown-test-env [data-dir]
  (fs.remove-all data-dir))

(fn create-task-via-adapter [app adapters repo-id]
  (local def (adapters:resolve "repo.create-task" app))
  (local result (json.loads (def.run {:repo-id repo-id :prompt "test task"})))
  (assert result.id "task should have id")
  (assert (= result.status :working) "task should be in working status")
  (assert (>= result.file-count 1) "task should have at least one file hash")
  result)

(fn test-read-file-json []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.read-file" app))
  (local result (json.loads (def.run {:task-id task.id :path "README.md"})))
  (assert result.content "read-file should return content")
  (assert (= result.path "README.md") "result should include path")
  (assert result.sha256 "read-file should return sha256")
  (assert (string.find result.sha256 "^sha256:") "sha256 should have sha256: prefix")
  (assert (> result.size 0) "should have non-zero size")
  (local expected-hash (.. "sha256:" (Sha256.hash result.content)))
  (assert (= result.sha256 expected-hash) "hash should match content hash")
  (teardown-test-env data-dir))

(fn test-search-content-match []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.search" app))
  (local name-result (json.loads (def.run {:task-id task.id :query "readme"})))
  (assert (>= name-result.result-count 1) "should find README by name")
  (var found false)
  (each [_ r (ipairs name-result.results)]
    (when (= r.path "README.md")
      (set found true)
      (assert r.name-match "README.md should be a name match")))
  (assert found "should find README.md in results")
  (local content-result (json.loads (def.run {:task-id task.id :query "hello"})))
  (assert (>= content-result.result-count 1) "should find content match for 'hello'")
  (var content-found false)
  (each [_ r (ipairs content-result.results)]
    (when (and (= r.path "src/main.fnl") r.content-match)
      (set content-found true)))
  (assert content-found "should find content match in src/main.fnl")
  (teardown-test-env data-dir))

(fn test-search-literal-matching []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local marker-path (fs.join-path full-task.worktree-path "parens(foo).txt"))
  (fs.write-file marker-path "(capture group)\n")
  (local def (adapters:resolve "repo.search" app))
  (local match-result (json.loads (def.run {:task-id task.id :query "(capture"})))
  (assert (>= match-result.result-count 1) "should find file by literal content")
  (local name-result (json.loads (def.run {:task-id task.id :query "parens("})))
  (assert (>= name-result.result-count 1) "should find file by literal name")
  (local pct-result (json.loads (def.run {:task-id task.id :query "%w"})))
  (assert (= pct-result.result-count 0) (.. "%w must match nothing (literal), got " (tostring pct-result.result-count) " results"))
  (teardown-test-env data-dir))

(fn compute-readme-hash-via-adapter [app adapters task-id]
  (local def (adapters:resolve "repo.read-file" app))
  (local result (json.loads (def.run {:task-id task-id :path "README.md"})))
  result.sha256)

(fn test-apply-patch-success []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local readme-hash (compute-readme-hash-via-adapter app adapters task.id))
  (local patch "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-# readme\n+# modified readme\n")
  (local def (adapters:resolve "repo.apply-patch" app))
  (local result (json.loads (def.run {:task-id task.id
                                       :patch patch
                                       :expected-hashes {"README.md" readme-hash}})))
  (assert result.files-touched "apply-patch should return files-touched")
  (assert result.oversized-files "apply-patch result should include oversized-files")
  (assert (= (# result.oversized-files) 0) "oversized-files should be empty for small patch")
  (assert (>= (CountMap.count result.file-hashes) 1) "post-patch hashes should have entries")
  (local new-hash (. result.file-hashes "README.md"))
  (assert (not= new-hash readme-hash) "content changed => hash must differ")
  (teardown-test-env data-dir))

(fn test-apply-patch-rejects-missing-hash []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local patch "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-# readme\n+# modified readme\n")
  (local def (adapters:resolve "repo.apply-patch" app))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch patch
                                   :expected-hashes {}}))
  (assert (not ok) "should reject patch with missing expected hash")
  (assert (string.find (tostring err) "hash mismatch") "error should mention hash mismatch")
  (teardown-test-env data-dir))

(fn test-apply-patch-rejects-wrong-hash []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local patch "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-# readme\n+# modified readme\n")
  (local def (adapters:resolve "repo.apply-patch" app))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch patch
                                   :expected-hashes {"README.md" "sha256:deadbeef00000000000000000000000000000000000000000000000000000000"}}))
  (assert (not ok) "should reject patch with wrong expected hash")
  (assert (string.find (tostring err) "hash mismatch") "error should mention hash mismatch")
  (teardown-test-env data-dir))

(fn test-space-repo-status-returns-files []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.status" app))
  (local result (json.loads (def.run {:task-id task.id})))
  (assert (= result.status :working) "should report working status")
  (assert (= result.branch task.branch) "should report task branch")
  (teardown-test-env data-dir))

(fn test-space-repo-diff-includes-hashes []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.diff" app))
  (local result (json.loads (def.run {:task-id task.id})))
  (assert result.file-hashes "diff result should include file-hashes")
  (assert (>= (CountMap.count result.file-hashes) 1) "diff should include hashes for tracked files")
  (assert (. result.file-hashes "README.md") "README.md should be in diff hashes")
  (assert result.oversized-files "diff result should include oversized-files")
  (assert (= (# result.oversized-files) 0) "oversized-files should be empty for small repo")
  (teardown-test-env data-dir))

(fn test-space-repo-diff-untracked-content []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local untracked-path (fs.join-path full-task.worktree-path "untracked.txt"))
  (fs.write-file untracked-path "new file content\n")
  (local def (adapters:resolve "repo.diff" app))
  (local result (json.loads (def.run {:task-id task.id})))
  (assert result.untracked-files "diff result should include untracked-files")
  (assert (. result.untracked-files "untracked.txt") "untracked.txt should be in untracked-files")
  (teardown-test-env data-dir))

(fn test-create-task-returns-branch []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (assert task.branch "task should have branch")
  (assert (not= nil (string.find task.branch "space-agent/" 1 true)) "branch should have space-agent/ prefix")
  (teardown-test-env data-dir))

(fn test-repo-context-gate-activates-after-repos-available []
  (local env (setup-test-env))
  (local app env.app)
  (local data-dir env.data-dir)
  (local adapters (ToolAdapterRegistry {}))
  (local registry (PresetRegistry {}))
  (local mgr (PresetManager {:registry registry
                              :tool-adapters adapters
                              :app app
                              :context {:surface :scene :canvas-visible? false}}))
  (local builtin-repo (require :llm/presets/builtins/repo))
  (builtin-repo.register mgr)
  (local no-repo-tools (mgr:get-tool-ids))
  (var has-discover nil)
  (each [_ tid (ipairs no-repo-tools)]
    (when (= tid "repo.status") (set has-discover true)))
  (assert (not has-discover) "repo.discover should be absent when no repos")

  (mgr:set-context {:surface :scene :canvas-visible? false :repos-available? true})
  (local with-repo-tools (mgr:get-tool-ids))
  (var found-discover nil)
  (var found-edit nil)
  (each [_ tid (ipairs with-repo-tools)]
    (when (= tid "repo.status") (set found-discover true))
    (when (= tid "repo.apply-patch") (set found-edit true))
    (when (= tid "repo.create-task") (set found-edit true)))
  (assert found-discover "repo-discover-tools should activate after repos-available?")
  (assert found-edit "repo-edit-tools should activate after repos-available?")
  (teardown-test-env data-dir))

(fn test-clone-adapter-context-refresh-pattern []
  (local env (setup-test-env))
  (local app env.app)
  (local data-dir env.data-dir)
  (local adapters (ToolAdapterRegistry {}))
  (local registry (PresetRegistry {}))
  (local mgr (PresetManager {:registry registry
                              :tool-adapters adapters
                              :app app
                              :context {:surface :scene :canvas-visible? false}}))
  (tset app :agent-presets mgr)
  (local builtin-repo (require :llm/presets/builtins/repo))
  (builtin-repo.register mgr)
  (local no-repo-tools (mgr:get-tool-ids))
  (each [_ tid (ipairs no-repo-tools)]
    (assert (not= tid "repo.status") "discover tools must be absent initially"))

  (builtin-repo.repo-available! app)
  (local with-repo-tools (mgr:get-tool-ids))
  (var found-discover nil)
  (each [_ tid (ipairs with-repo-tools)]
    (when (= tid "repo.status") (set found-discover true)))
  (assert found-discover "repo-available! must activate tools")
  (teardown-test-env data-dir))

(fn test-symlink-patch-new-file-rejected []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local symlink-patch "diff --git a/link b/link\nnew file mode 120000\nindex 0000000..abcdef0\n--- /dev/null\n+++ b/link\n@@ -0,0 +1 @@\n+target\n")
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch symlink-patch
                                   :expected-hashes {}}))
  (assert (not ok) "should reject symlink creation patch")
  (assert (string.find (tostring err) "not allowed") "error should mention not allowed")
  (teardown-test-env data-dir))

(fn test-symlink-mode-conversion-rejected []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local mode-patch "diff --git a/README.md b/README.md\nold mode 100644\nnew mode 120000\n")
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch mode-patch
                                   :expected-hashes {}}))
  (assert (not ok) "should reject file-to-symlink mode change")
  (assert (string.find (tostring err) "not allowed") "error should mention not allowed")
  (teardown-test-env data-dir))

(fn test-apply-patch-deletes-file []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local readfile-def (adapters:resolve "repo.read-file" app))
  (local readfile-result (json.loads (readfile-def.run {:task-id task.id :path "src/main.fnl"})))
  (local main-hash readfile-result.sha256)
  (local patch "--- a/src/main.fnl\n+++ /dev/null\n@@ -1 +0,0 @@\n-{:main (fn [] (print :hello))}\n")
  (local def (adapters:resolve "repo.apply-patch" app))
  (local result (json.loads (def.run {:task-id task.id
                                       :patch patch
                                       :expected-hashes {"src/main.fnl" main-hash}})))
  (assert result.files-touched "apply-patch should return files-touched")
  (assert (not (. result.file-hashes "src/main.fnl")) "deleted file should not be in post-patch hashes")
  (assert (>= (CountMap.count result.file-hashes) 1) "other files should still be present")
  (assert (. result.file-hashes "README.md") "README.md should remain")
  (teardown-test-env data-dir))

(fn test-rejected-patch-preserves-prior-work []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local readme-hash (compute-readme-hash-via-adapter app adapters task.id))
  (local patch-a "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-# readme\n+# modified readme\n")
  (local def (adapters:resolve "repo.apply-patch" app))
  (def.run {:task-id task.id :patch patch-a :expected-hashes {"README.md" readme-hash}})
  (local new-hash (compute-readme-hash-via-adapter app adapters task.id))
  (assert (not= new-hash readme-hash) "first patch should have modified README")
  (local bad-patch "--- a/src/main.fnl\n+++ b/src/main.fnl\n@@ -1 +1 @@\n-{:main (fn [] (print :hello))}\n+{:main (fn [] (print :bad))}\n")
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch bad-patch
                                   :expected-hashes {"src/main.fnl" "sha256:deadbeef00000000000000000000000000000000000000000000000000000000"}}))
  (assert (not ok) "should reject patch with wrong hash")
  (assert (string.find (tostring err) "hash mismatch") "error should mention hash mismatch")
  (local after-reject-hash (compute-readme-hash-via-adapter app adapters task.id))
  (assert (= after-reject-hash new-hash) "README should retain first modification after second patch rejected")
  (teardown-test-env data-dir))

(fn test-symlink-patch-crlf-rejected []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local crlf-patch (.. "diff --git a/link b/link\r\nnew file mode 120000\r\nindex 0000000..abcdef0\r\n--- /dev/null\r\n+++ b/link\r\n@@ -0,0 +1 @@\r\n+target\r\n"))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch crlf-patch
                                   :expected-hashes {}}))
  (assert (not ok) "should reject crlf symlink creation patch")
  (assert (string.find (tostring err) "not allowed") "error should mention not allowed")
  (teardown-test-env data-dir))

(fn test-read-file-rejects-oversized []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local large-path (fs.join-path full-task.worktree-path "large.bin"))
  (local parts [])
  (for [_ 1 200000]
    (table.insert parts "x"))
  (local data (table.concat parts ""))
  (fs.write-file large-path data)
  (local def (adapters:resolve "repo.read-file" app))
  (local (ok err) (pcall def.run {:task-id task.id :path "large.bin"}))
  (assert (not ok) "should reject oversized file")
  (assert (string.find (tostring err) "too large") "error should mention too large")
  (teardown-test-env data-dir))

(fn test-diff-oversized-files-listed []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local parts [])
  (for [_ 1 200000]
    (table.insert parts "x"))
  (fs.write-file (fs.join-path full-task.worktree-path "large.bin") (table.concat parts ""))
  (local def (adapters:resolve "repo.diff" app))
  (local result (json.loads (def.run {:task-id task.id})))
  (assert result.oversized-files "diff should include oversized-files")
  (assert (>= (# result.oversized-files) 1) "oversized-files should not be empty")
  (var found-large false)
  (each [_ f (ipairs result.oversized-files)]
    (when (= f "large.bin")
      (set found-large true)))
  (assert found-large "large.bin should be in oversized-files entry")
  (assert (not (. result.file-hashes "large.bin")) "large.bin should not be in file-hashes")
  (teardown-test-env data-dir))

(table.insert tests {:name "repo presets: read-file returns JSON content and sha256" :fn test-read-file-json})
(table.insert tests {:name "repo presets: read-file rejects oversized" :fn test-read-file-rejects-oversized})
(table.insert tests {:name "repo presets: search finds content match" :fn test-search-content-match})
(fn test-search-finds-dotfiles []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local dotfile-path (fs.join-path full-task.worktree-path ".clang-format"))
  (fs.write-file dotfile-path "BasedOnStyle: LLVM\n")
  (local def (adapters:resolve "repo.search" app))
  (local result (json.loads (def.run {:task-id task.id :query ".clang-format"})))
  (assert (>= result.result-count 1) "should find .clang-format dotfile")
  (var found false)
  (each [_ r (ipairs result.results)]
    (when (= r.path ".clang-format")
      (set found true)))
  (assert found ".clang-format should be in search results")
  (teardown-test-env data-dir))

(table.insert tests {:name "repo presets: search finds dotfiles" :fn test-search-finds-dotfiles})
(table.insert tests {:name "repo presets: search literal matching" :fn test-search-literal-matching})
(table.insert tests {:name "repo presets: apply-patch succeeds with correct hash" :fn test-apply-patch-success})
(table.insert tests {:name "repo presets: apply-patch rejects missing hash" :fn test-apply-patch-rejects-missing-hash})
(table.insert tests {:name "repo presets: apply-patch rejects wrong hash" :fn test-apply-patch-rejects-wrong-hash})
(table.insert tests {:name "repo presets: status returns files" :fn test-space-repo-status-returns-files})
(table.insert tests {:name "repo presets: diff includes file hashes" :fn test-space-repo-diff-includes-hashes})
(table.insert tests {:name "repo presets: diff oversized files listed" :fn test-diff-oversized-files-listed})
(table.insert tests {:name "repo presets: diff includes untracked content" :fn test-space-repo-diff-untracked-content})
(table.insert tests {:name "repo presets: create-task returns branch" :fn test-create-task-returns-branch})
(table.insert tests {:name "repo presets: context gate activates after repos available" :fn test-repo-context-gate-activates-after-repos-available})
(table.insert tests {:name "repo presets: clone adapter get-context set-context pattern" :fn test-clone-adapter-context-refresh-pattern})
(table.insert tests {:name "repo presets: symlink patch new file rejected" :fn test-symlink-patch-new-file-rejected})
(table.insert tests {:name "repo presets: symlink mode conversion rejected" :fn test-symlink-mode-conversion-rejected})
(table.insert tests {:name "repo presets: symlink patch crlf rejected" :fn test-symlink-patch-crlf-rejected})
(fn test-patch-toucher-quoted-path []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/\\303\\251.txt\"\n"
                   "+++ \"b/\\303\\251.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect quoted non-ASCII path")
  (local expected (.. (string.char 195 169) ".txt"))
  (assert (= (. touched 1) expected)
          (.. "should return unescaped path, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher unescapes quoted path" :fn test-patch-toucher-quoted-path})
(fn test-patch-toucher-escaped-quote []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\\"bar.txt\"\n"
                   "+++ \"b/foo\\\"bar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with escaped quote")
  (local expected "foo\"bar.txt")
  (assert (= (. touched 1) expected)
          (.. "should unescape quote, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher handles escaped quote in path" :fn test-patch-toucher-escaped-quote})
(fn test-patch-toucher-backslash-before-quote []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\\\\"\n"
                   "+++ \"b/foo\\\\\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with trailing escaped backslash")
  (local expected (.. "foo\\"))
  (assert (= (. touched 1) expected)
          (.. "should unescape backslash, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher handles backslash before closing quote" :fn test-patch-toucher-backslash-before-quote})
(fn test-patch-toucher-escaped-backslash-midpath []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\\\bar.txt\"\n"
                   "+++ \"b/foo\\\\bar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with escaped backslash mid-path")
  (local expected (.. "foo\\bar.txt"))
  (assert (= (. touched 1) expected)
          (.. "should unescape backslash mid-path, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher handles escaped backslash mid-path" :fn test-patch-toucher-escaped-backslash-midpath})
(fn test-patch-toucher-backslash-literal-octal []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/\\\\303.txt\"\n"
                   "+++ \"b/\\\\303.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with backslash before octal-looking digits")
  (local expected (.. "\\303.txt"))
  (assert (= (. touched 1) expected)
          (.. "should preserve literal backslash before octal, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher preserves literal backslash before octal" :fn test-patch-toucher-backslash-literal-octal})
(fn test-patch-toucher-backslash-quote-backslash []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\\\\\\"bar.txt\"\n"
                   "+++ \"b/foo\\\\\\\"bar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with escaped backslash before escaped quote")
  (local expected (.. "foo\\\"bar.txt"))
  (assert (= (. touched 1) expected)
          (.. "should decode backslash-quote pair, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher decodes backslash-quote pair" :fn test-patch-toucher-backslash-quote-backslash})
(fn test-patch-toucher-tab-escape []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\tbar.txt\"\n"
                   "+++ \"b/foo\\tbar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with tab escape")
  (local expected "foo\tbar.txt")
  (assert (= (. touched 1) expected)
          (.. "should decode tab escape, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher decodes tab escape" :fn test-patch-toucher-tab-escape})

(fn test-patch-toucher-newline-escape []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\nbar.txt\"\n"
                   "+++ \"b/foo\\nbar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with newline escape")
  (local expected "foo\nbar.txt")
  (assert (= (. touched 1) expected)
          (.. "should decode newline escape, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher decodes newline escape" :fn test-patch-toucher-newline-escape})

(fn test-patch-toucher-cr-escape []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\rbar.txt\"\n"
                   "+++ \"b/foo\\rbar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with CR escape")
  (local expected "foo\rbar.txt")
  (assert (= (. touched 1) expected)
          (.. "should decode CR escape, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher decodes cr escape" :fn test-patch-toucher-cr-escape})

(fn test-patch-toucher-rejects-unknown-escape []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\xbar.txt\"\n"
                   "+++ \"b/foo\\xbar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local (ok err) (pcall toucher.touched-files patch))
  (assert (not ok) "should reject unknown backslash escape")
  (assert (string.find (tostring err) "unsupported quotePath escape") "error should mention unsupported quotePath escape"))
(table.insert tests {:name "repo presets: patch-toucher rejects unknown backslash escape" :fn test-patch-toucher-rejects-unknown-escape})

(fn test-patch-toucher-leading-space-filename []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/ leading.txt\"\n"
                   "+++ \"b/ leading.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with leading space")
  (local expected " leading.txt")
  (assert (= (. touched 1) expected)
          (.. "should preserve leading space, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher preserves leading space in filename" :fn test-patch-toucher-leading-space-filename})

(fn test-patch-toucher-trailing-space-filename []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/trailing .txt\"\n"
                   "+++ \"b/trailing .txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with trailing space")
  (local expected "trailing .txt")
  (assert (= (. touched 1) expected)
          (.. "should preserve trailing space, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher preserves trailing space in filename" :fn test-patch-toucher-trailing-space-filename})

(fn test-patch-toucher-short-octal-escape []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\11bar.txt\"\n"
                   "+++ \"b/foo\\11bar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with 2-digit octal escape")
  (local expected (.. "foo" (string.char 9) "bar.txt"))
  (assert (= (. touched 1) expected)
          (.. "should decode 2-digit octal \\11 to tab, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher decodes 2-digit octal escape" :fn test-patch-toucher-short-octal-escape})

(fn test-patch-toucher-single-digit-octal-escape []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- \"a/foo\\7bar.txt\"\n"
                   "+++ \"b/foo\\7bar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path with 1-digit octal escape")
  (local expected (.. "foo" (string.char 7) "bar.txt"))
  (assert (= (. touched 1) expected)
          (.. "should decode 1-digit octal \\7 to BEL, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher decodes 1-digit octal escape" :fn test-patch-toucher-single-digit-octal-escape})

(fn test-patch-toucher-bare-crlf-header []
  (local toucher (require :repo/patch-toucher))
  (local patch (.. "--- a/README.MD\r\n"
                   "+++ b/README.MD\r\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local touched (toucher.touched-files patch))
  (assert (>= (# touched) 1) "should detect path from bare CRLF header")
  (assert (= (. touched 1) "README.MD")
          (.. "should strip trailing CR from bare header, got: " (tostring (. touched 1)))))
(table.insert tests {:name "repo presets: patch-toucher strips CRLF from bare header" :fn test-patch-toucher-bare-crlf-header})

(fn test-apply-patch-short-octal-filename-hash-gate []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local tab-name (.. "foo" (string.char 9) "bar.txt"))
  (local tab-path (fs.join-path full-task.worktree-path tab-name))
  (fs.write-file tab-path "hello\n")
  (local patch (.. "--- \"a/foo\\11bar.txt\"\n"
                   "+++ \"b/foo\\11bar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch patch
                                   :expected-hashes {}}))
  (assert (not ok) "should reject patch touching short-octal-named file without expected hash")
  (assert (string.find (tostring err) "hash mismatch") "error should mention hash mismatch")
  (local content (fs.read-file tab-path))
  (assert (= content "hello\n") "short-octal file should be unchanged after rejected patch")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: apply-patch short octal filename without hash rejects" :fn test-apply-patch-short-octal-filename-hash-gate})

(fn test-apply-patch-leading-space-filename-hash-gate []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local space-name " leading.txt")
  (local space-path (fs.join-path full-task.worktree-path space-name))
  (fs.write-file space-path "hello\n")
  (local patch (.. "--- \"a/ leading.txt\"\n"
                   "+++ \"b/ leading.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch patch
                                   :expected-hashes {}}))
  (assert (not ok) "should reject patch touching leading-space file without expected hash")
  (assert (string.find (tostring err) "hash mismatch") "error should mention hash mismatch")
  (local content (fs.read-file space-path))
  (assert (= content "hello\n") "leading-space file should be unchanged after rejected patch")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: apply-patch leading-space filename without hash rejects" :fn test-apply-patch-leading-space-filename-hash-gate})

(fn test-apply-patch-rejects-oversized-existing []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local parts [])
  (for [_ 1 200000]
    (table.insert parts "x"))
  (fs.write-file (fs.join-path full-task.worktree-path "large.bin") (table.concat parts ""))
  (local diff-def (adapters:resolve "repo.diff" app))
  (local diff-result (json.loads (diff-def.run {:task-id task.id})))
  (var found-large false)
  (each [_ f (ipairs diff-result.oversized-files)]
    (when (= f "large.bin")
      (set found-large true)))
  (assert found-large "large.bin should be in oversized-files")
  (local patch (.. "--- a/large.bin\n+++ b/large.bin\n@@ -1,3 +1,3 @@\n"
                   (table.concat parts "" 1 3) "\n"
                   "+yyy\n"))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch patch
                                   :expected-hashes {"README.md" "sha256:0000000000000000000000000000000000000000000000000000000000000000"}}))
  (assert (not ok) "should reject patch touching oversized file without expected hash")
  (assert (string.find (tostring err) "too large") "error should mention too large")
  (teardown-test-env data-dir))

(table.insert tests {:name "repo presets: apply-patch rejects oversized existing" :fn test-apply-patch-rejects-oversized-existing})

(fn test-apply-patch-quoted-unicode-path []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local accent-name (.. (string.char 195 169) ".txt"))
  (local accent-path (fs.join-path full-task.worktree-path accent-name))
  (fs.write-file accent-path "hello\n")
  (local accent-hash (.. "sha256:" (Sha256.hash-file accent-path)))
  (local patch (.. "--- \"a/\\303\\251.txt\"\n"
                   "+++ \"b/\\303\\251.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local expected-hashes {})
  (tset expected-hashes accent-name accent-hash)
  (local result (json.loads (def.run {:task-id task.id :patch patch :expected-hashes expected-hashes})))
  (assert result.files-touched "apply-patch should return files-touched")
  (local modified (fs.read-file accent-path))
  (assert (= modified "world\n") (.. "file should be modified, got: " modified))
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: apply-patch with quoted unicode path" :fn test-apply-patch-quoted-unicode-path})

(fn test-apply-patch-tab-filename-hash-gate []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local tab-name "foo\tbar.txt")
  (local tab-path (fs.join-path full-task.worktree-path tab-name))
  (fs.write-file tab-path "hello\n")
  (local patch (.. "--- \"a/foo\\tbar.txt\"\n"
                   "+++ \"b/foo\\tbar.txt\"\n"
                   "@@ -1 +1 @@\n"
                   "-hello\n"
                   "+world\n"))
  (local def (adapters:resolve "repo.apply-patch" app))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch patch
                                   :expected-hashes {}}))
  (assert (not ok) "should reject patch touching tab-named file without expected hash")
  (assert (string.find (tostring err) "hash mismatch") "error should mention hash mismatch")
  (local content (fs.read-file tab-path))
  (assert (= content "hello\n") "tab-named file should be unchanged after rejected patch")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: apply-patch tab filename without hash rejects" :fn test-apply-patch-tab-filename-hash-gate})

(table.insert tests {:name "repo presets: apply-patch deletes file" :fn test-apply-patch-deletes-file})
(table.insert tests {:name "repo presets: rejected patch preserves prior work" :fn test-rejected-patch-preserves-prior-work})

(fn test-repo-list-returns-safe-fields []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local def (adapters:resolve "repo.list" app))
  (local result (json.loads (def.run {})))
  (assert (>= (# result) 1) "list should return at least one repo")
  (local listed (. result 1))
  (assert listed.id "listed repo should have id")
  (assert listed.host "listed repo should have host")
  (assert listed.owner "listed repo should have owner")
  (assert listed.name "listed repo should have name")
  (assert (= (type listed.remote-url) "string") "listed repo should have remote-url")
  (assert (not (string.find listed.remote-url "@" 1 true)) "remote-url must not contain @")
  (assert (not (string.find listed.remote-url "?" 1 true)) "remote-url must not contain query string")
  (assert (not (string.find listed.remote-url "#" 1 true)) "remote-url must not contain fragment")
  (assert (string.find listed.remote-url "unknown/test/repo" 1 true) "remote-url should be derived from host/owner/name not stored value")
  (assert (not listed.clone-path) "listed repo must not expose clone-path")
  (assert (not listed.host-raw) "listed repo must not expose host-raw")
  (assert (not listed.host-key) "listed repo must not expose host-key")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: list returns safe fields only" :fn test-repo-list-returns-safe-fields})

(fn test-commit-adapter []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local readme-hash (compute-readme-hash-via-adapter app adapters task.id))
  (local patch "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-# readme\n+# modified readme\n")
  (local apply-def (adapters:resolve "repo.apply-patch" app))
  (apply-def.run {:task-id task.id :patch patch :expected-hashes {"README.md" readme-hash}})
  (local commit-def (adapters:resolve "repo.commit" app))
  (local result (json.loads (commit-def.run {:task-id task.id :message "test commit"})))
  (assert (= result.status :committed) "status should be committed")
  (assert result.committed-at "should have committed-at timestamp")
  (local ws (WorkspaceMod.Workspace {:data-dir env.repos-dir}))
  (local full-task (ws:get-task task.id))
  (assert (= full-task.status :committed) "persisted status should be committed")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: commit adapter" :fn test-commit-adapter})

(fn test-push-adapter []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local readme-hash (compute-readme-hash-via-adapter app adapters task.id))
  (local patch "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-# readme\n+# modified readme\n")
  (local apply-def (adapters:resolve "repo.apply-patch" app))
  (apply-def.run {:task-id task.id :patch patch :expected-hashes {"README.md" readme-hash}})
  (local commit-def (adapters:resolve "repo.commit" app))
  (commit-def.run {:task-id task.id :message "test commit"})
  (local push-def (adapters:resolve "repo.push" app))
  (local result (json.loads (push-def.run {:task-id task.id})))
  (assert (= result.status :pushed) "status should be pushed")
  (assert (= result.branch task.branch) "should return task branch")
  (local ws (WorkspaceMod.Workspace {:data-dir env.repos-dir}))
  (local full-task (ws:get-task task.id))
  (assert (= full-task.status :pushed) "persisted status should be pushed")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: push adapter" :fn test-push-adapter})

(fn test-list-checks-adapter []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.list-checks" app))
  (local result (json.loads (def.run {:task-id task.id})))
  (assert (= result.profile :generic) "profile should be generic")
  (assert (= (type result.checks) "table") "checks should be a table")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: list-checks adapter" :fn test-list-checks-adapter})

(fn test-run-check-adapter-rejects-unknown-check []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.run-check" app))
  (local (ok err) (pcall def.run {:task-id task.id :check-id "nonexistent"}))
  (assert (not ok) "should reject unknown check id")
  (assert (string.find (tostring err) "check not found") "error should mention check not found")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: run-check adapter rejects unknown check" :fn test-run-check-adapter-rejects-unknown-check})

(fn test-open-pr-adapter-rejects-non-github []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.open-pr" app))
  (local (ok err) (pcall def.run {:task-id task.id :title "test" :body "test body"}))
  (assert (not ok) "should reject non-github host for PR")
  (assert (string.find (tostring err) "PRs only supported for GitHub") "error should mention GitHub only")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: open-pr adapter rejects non-github" :fn test-open-pr-adapter-rejects-non-github})

(fn test-repo-list-sanitizes-legacy-credential-url []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  ;; Seed an entry whose host-raw contains credentials, emulating what the old parser stored.
  ;; safe-display-url must reject this rather than silently constructing a dangerous URL.
  (ws.store:add-repo
    {:id "github.com-legacy-owner-legacy-repo"
     :remote-url "https://token@github.com/legacy-owner/legacy-repo.git"
     :host :github
     :host-key "token@github.com"
     :host-raw "token@github.com"
     :owner "legacy-owner"
     :name "legacy-repo"
     :default-branch "main"
     :clone-path "/nonexistent/legacy"
     :profile :generic
     :created-at (os.time)})
  (local def (adapters:resolve "repo.list" app))
  (local (ok err) (pcall def.run {}))
  (assert (not ok) "should reject corrupted registry entry with credential in host-raw")
  (assert (string.find (tostring err) "must not contain" 1 true)
          (.. "error should flag unsafe host-raw, got: " (tostring err)))
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: list rejects corrupted host-raw in registry" :fn test-repo-list-sanitizes-legacy-credential-url})

(fn test-repo-clone-alias-sanitizes-legacy-credential-url []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local ws env.ws)
  (local Remote (require :repo/remote))
  (local parsed (Remote.parse "https://github.com/legacy-clone-owner/legacy-clone-repo"))
  (local repo-id parsed.repo-id)
  (ws.store:add-repo
    {:id repo-id
     :remote-url "https://token@github.com/legacy-clone-owner/legacy-clone-repo.git"
     :host parsed.host
     :host-key parsed.host-key
     :host-raw parsed.host-raw
     :owner parsed.owner
     :name parsed.name
     :default-branch "main"
     :clone-path "/nonexistent/legacy-clone"
     :profile :generic
     :created-at (os.time)})
  (local def (adapters:resolve "repo.clone" app))
  (local result (json.loads (def.run {:url "https://github.com/legacy-clone-owner/legacy-clone-repo.git"})))
  (assert result.id "should return repo")
  (assert (= result.id repo-id) "should return same repo-id")
  (assert (not (string.find result.remote-url "token@" 1 true))
          (.. "legacy credential URL must be sanitized in clone alias, got: " result.remote-url))
  (assert (not (string.find result.remote-url "@" 1 true))
          "sanitized clone URL must not contain @")
  (assert (string.find result.remote-url "legacy-clone-owner" 1 true)
          "sanitized clone URL should contain owner")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: clone alias sanitizes legacy credential URL" :fn test-repo-clone-alias-sanitizes-legacy-credential-url})

(fn test-pr-status-adapter-rejects-no-pr-url []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local def (adapters:resolve "repo.pr-status" app))
  (local (ok err) (pcall def.run {:task-id task.id}))
  (assert (not ok) "should reject pr-status when task has no PR URL")
  (assert (string.find (tostring err) "no PR URL") "error should mention no PR URL")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: pr-status adapter rejects no pr-url" :fn test-pr-status-adapter-rejects-no-pr-url})

(fn test-apply-patch-rollback-on-post-apply-failure []
  (local env (setup-test-env))
  (local app env.app)
  (local adapters env.adapters)
  (local data-dir env.data-dir)
  (local repo-data env.repo-data)
  (local ws env.ws)
  (local task (create-task-via-adapter app adapters repo-data.id))
  (local full-task (ws:get-task task.id))
  (local readme-hash (compute-readme-hash-via-adapter app adapters task.id))
  (local tasks-dir (fs.join-path data-dir "repositories" "tasks"))
  (local Process (require :process))
  (Process.run {:args ["chmod" "-w" tasks-dir] :timeout 10 :merge-stderr true})
  (local patch "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-# readme\n+# modified readme\n")
  (local def (adapters:resolve "repo.apply-patch" app))
  (local (ok err) (pcall def.run {:task-id task.id
                                   :patch patch
                                   :expected-hashes {"README.md" readme-hash}}))
  (Process.run {:args ["chmod" "+w" tasks-dir] :timeout 10 :merge-stderr true})
  (assert (not ok) "apply-patch should fail when post-apply update-task fails")
  (assert (string.find (tostring err) "post%-apply validation failed %(rolled back%)") "error should indicate rollback")
  (local readfile-def (adapters:resolve "repo.read-file" app))
  (local readfile-result (json.loads (readfile-def.run {:task-id task.id :path "README.md"})))
  (assert (= readfile-result.sha256 readme-hash) "README should be rolled back to original content")
  (teardown-test-env data-dir))
(table.insert tests {:name "repo presets: apply-patch rollback on post-apply failure" :fn test-apply-patch-rollback-on-post-apply-failure})

(local main
  (fn []
    (when skip-module
      (print "Skipping repo presets tests: git 2.54 incompatibility on CI or Windows platform")
      (lua "return true"))
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-presets"
                       :tests tests})))

(local module-tests (if skip-module [] tests))

{:name "repo-presets"
 :tests module-tests
 :main main}
