;; Integration configuration checks for the experimental constraints gate.

(local tests [])
(local fs (require :fs))

(fn repo-root []
  (if (fs.exists "CMakeLists.txt")
      "."
      (do
        (assert (fs.exists "../CMakeLists.txt")
                "expected to run from the repository root or build directory")
        "..")))

(fn read-repo-file [path]
  (fs.read-file (.. (repo-root) "/" path)))

(fn assert-contains [contents needle message]
  (assert (string.find contents needle 1 true)
          (.. message " (missing: " needle ")")))

(fn test-makefile-wires-constraints-target []
  (local makefile (read-repo-file "Makefile"))
  (assert (string.find makefile "^.PHONY:.*constraints")
          "Makefile .PHONY declaration should include constraints")
  (assert-contains makefile "test: constraints"
                   "make test should depend on constraints")
  (assert-contains makefile "constraints: build"
                   "Makefile should declare a constraints target")
  (assert-contains makefile "SPACE_DISABLE_AUDIO=1"
                   "constraints command should disable audio")
  (assert-contains makefile "SPACE_ASSETS_PATH=$(shell pwd)/assets"
                   "constraints command should use absolute SPACE_ASSETS_PATH")
  (assert-contains makefile "FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\\;$(shell pwd)/assets/lua/?/init.fnl"
                   "constraints command should configure FENNEL_PATH")
  (assert-contains makefile "FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\\;$(shell pwd)/assets/lua/?/init.fnl"
                   "constraints command should configure FENNEL_MACRO_PATH")
  (assert-contains makefile "./build/space -m constraints.runner:main -- --target repo"
                   "constraints target should run the repo constraints command"))

(fn ctest-block-has-fixture? [cmake test-name]
  (local (start) (string.find cmake test-name 1 true))
  (assert start (.. "CMake should configure " test-name))
  (local (fixture-pos) (string.find cmake "FIXTURES_REQUIRED space_experimental_constraints" start true))
  (local (next-test-pos) (string.find cmake "add_test(NAME" (+ start 1) true))
  (if next-test-pos
      (and fixture-pos (< fixture-pos next-test-pos))
      fixture-pos))

(fn test-cmake-wires-experimental-constraints-fixture []
  (local cmake (read-repo-file "CMakeLists.txt"))
  (assert-contains cmake "add_test(NAME ${PROJECT_NAME}_experimental_constraints"
                   "CMake should declare the experimental constraints test")
  (assert-contains cmake "COMMAND space -m constraints.runner:main -- --target repo"
                   "experimental constraints CTest should run the repo constraints command")
  (assert-contains cmake "FIXTURES_SETUP space_experimental_constraints"
                   "experimental constraints CTest should set up its fixture")
  (assert (ctest-block-has-fixture? cmake "${PROJECT_NAME}_fnl_tests")
          "space_fnl_tests should require the experimental constraints fixture")
  (assert (ctest-block-has-fixture? cmake "${PROJECT_NAME}_fnl_tests_integration")
          "space_fnl_tests_integration should require the experimental constraints fixture"))

(table.insert tests {:name "Makefile wires blocking constraints target"
                     :fn test-makefile-wires-constraints-target})
(table.insert tests {:name "CMake wires experimental constraints fixture"
                     :fn test-cmake-wires-experimental-constraints-fixture})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-integration-config"
                       :tests tests})))

{:name "constraints-integration-config"
 :tests tests
 :main main}
