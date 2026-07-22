(local fs (require :fs))

(fn detect-space-profile [repo-clone-path]
  (when (not (fs.exists repo-clone-path))
    (lua "return nil"))
  (local cmake-path (fs.join-path repo-clone-path "CMakeLists.txt"))
  (local main-path (fs.join-path repo-clone-path "assets/lua/main.fnl"))
  (local runtime-path (fs.join-path repo-clone-path "src/lua_runtime.cpp"))
  (local agents-path (fs.join-path repo-clone-path "AGENTS.md"))
  (when (and (fs.exists cmake-path) (fs.exists main-path) (fs.exists runtime-path) (fs.exists agents-path))
    (local cmake-content (fs.read-file cmake-path))
    (when (string.find cmake-content "project%(space")
      :space)))

(fn generic-checks []
  [])

(fn space-checks [worktree-root]
  (local assets-path (fs.join-path worktree-root "assets"))
    [{:id :build
      :label "Build"
      :argv ["make" "build"]
      :timeout 600}
     {:id :test
      :label "Test"
      :argv ["make" "test"]
      :env {:SKIP_KEYRING_TESTS "1"
            :XDG_DATA_HOME "/tmp/space/tests/xdg-data"
            :SPACE_DISABLE_AUDIO "1"
            :SPACE_ASSETS_PATH assets-path}
      :timeout 300}
     {:id :e2e
      :label "E2E"
      :argv ["make" "test-e2e"]
      :env {:SPACE_DISABLE_AUDIO "1"
            :SPACE_ASSETS_PATH assets-path}
      :timeout 600}])

(fn profile-checks [profile repo-clone-path worktree-root]
  (if (= profile :space)
      (space-checks worktree-root)
      (generic-checks)))

(fn profile-label [profile]
  (if (= profile :space) "Space"
      "Generic"))

{:detect-space-profile detect-space-profile
 :generic-checks generic-checks
 :space-checks space-checks
 :profile-checks profile-checks
 :profile-label profile-label}
