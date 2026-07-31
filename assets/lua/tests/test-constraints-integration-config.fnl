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

(fn constraints-target-recipe [makefile]
  (local (start) (string.find makefile "\nconstraints:" 1 true))
  (local target-start (if start (+ start 1) 1))
  (assert (= (string.sub makefile target-start (+ target-start 11)) "constraints:")
          "Makefile should contain a constraints target")
  (local (next-target) (string.find makefile "\n%S[^\n]-:" (+ target-start 12)))
  (if next-target
      (string.sub makefile target-start (- next-target 1))
      (string.sub makefile target-start)))

(fn test-constraints-target-recipe-is-isolated []
  (local makefile (table.concat [".PHONY: constraints test"
                                 "constraints: build"
                                 "\t./build/space -m constraints.runner:main -- --target repo"
                                 ""
                                 "test: constraints"
                                 "\tSPACE_DISABLE_AUDIO=1 FENNEL_PATH=assets/lua/?.fnl ./build/space -m tests.fast:main"]
                                "\n"))
  (local recipe (constraints-target-recipe makefile))
  (assert (not (string.find recipe "FENNEL_PATH" 1 true))
          "constraints recipe slice should not include later make targets"))

(fn test-makefile-wires-constraints-target []
  (local makefile (read-repo-file "Makefile"))
  (local recipe (constraints-target-recipe makefile))
  (assert (string.find makefile "^.PHONY:.*constraints")
          "Makefile .PHONY declaration should include constraints")
  (assert-contains makefile "test: constraints"
                   "make test should depend on constraints")
  (assert-contains recipe "constraints: build"
                   "Makefile should declare a constraints target")
  (assert-contains recipe "SPACE_DISABLE_AUDIO=1"
                   "constraints command should disable audio")
  (assert-contains recipe "SPACE_ASSETS_PATH=$(shell pwd)/assets"
                   "constraints command should use absolute SPACE_ASSETS_PATH")
  (assert-contains recipe "FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\\;$(shell pwd)/assets/lua/?/init.fnl"
                   "constraints command should configure FENNEL_PATH")
  (assert-contains recipe "FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\\;$(shell pwd)/assets/lua/?/init.fnl"
                   "constraints command should configure FENNEL_MACRO_PATH")
  (assert-contains recipe "./build/space -m constraints.runner:main -- --target repo"
                   "constraints target should run the repo constraints command"))

(fn ctest-block-has-fixture? [cmake test-name]
  (local (start) (string.find cmake test-name 1 true))
  (assert start (.. "CMake should configure " test-name))
  (local (fixture-pos) (string.find cmake "FIXTURES_REQUIRED space_experimental_constraints" start true))
  (local (next-test-pos) (string.find cmake "add_test(NAME" (+ start 1) true))
  (if next-test-pos
      (and fixture-pos (< fixture-pos next-test-pos))
      fixture-pos))

(fn ctest-test-block [cmake test-name]
  (local (start) (string.find cmake test-name 1 true))
  (assert start (.. "CMake should configure " test-name))
  (local (next-test-pos) (string.find cmake "add_test(NAME" (+ start 1) true))
  (if next-test-pos
      (string.sub cmake start (- next-test-pos 1))
      (string.sub cmake start)))

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

(fn test-cmake-preserves-fennel-test-display-backend []
  (local cmake (read-repo-file "CMakeLists.txt"))
  (local fast-block (ctest-test-block cmake "${PROJECT_NAME}_fnl_tests"))
  (local integration-block (ctest-test-block cmake "${PROJECT_NAME}_fnl_tests_integration"))
  (assert (not (string.find fast-block "SDL_VIDEODRIVER=dummy" 1 true))
          "space_fnl_tests should not force SDL_VIDEODRIVER=dummy")
  (assert (not (string.find integration-block "SDL_VIDEODRIVER=dummy" 1 true))
          "space_fnl_tests_integration should not force SDL_VIDEODRIVER=dummy"))

(table.insert tests {:name "Makefile wires blocking constraints target"
                     :fn test-makefile-wires-constraints-target})
(table.insert tests {:name "Makefile constraints target recipe is isolated"
                     :fn test-constraints-target-recipe-is-isolated})
(table.insert tests {:name "CMake wires experimental constraints fixture"
                     :fn test-cmake-wires-experimental-constraints-fixture})
(table.insert tests {:name "CMake preserves Fennel test display backend"
                     :fn test-cmake-preserves-fennel-test-display-backend})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-integration-config"
                       :tests tests})))

{:name "constraints-integration-config"
 :tests tests
 :main main}
