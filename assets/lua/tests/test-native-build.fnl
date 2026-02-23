(local tests [])
(local fs (require :fs))
(local native-build (require :native-build))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "native-build-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "native-build-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn trim-line-ending [text]
  (if (and text (> (# text) 0) (= (string.sub text -1) "\n"))
      (string.sub text 1 -2)
      text))

(fn write-sample-cpp-main [path text]
  (fs.write-file path
                 (.. "#include <iostream>\n"
                     "int main() {\n"
                     "    std::cout << \"" text "\";\n"
                     "    return 0;\n"
                     "}\n")))

(fn write-sample-c-main [path text]
  (fs.write-file path
                 (.. "#include <stdio.h>\n"
                     "int main(void) {\n"
                     "    printf(\"" text "\");\n"
                     "    return 0;\n"
                     "}\n")))

(fn test-project-build-and-run-gpp []
  (with-temp-dir
    (fn [dir]
      (local src (fs.join-path dir "main.cpp"))
      (local build-dir (fs.join-path dir "obj"))
      (local output (fs.join-path dir "app-sync"))
      (write-sample-cpp-main src "native-build-sync")

      (local compiler (native-build.Gpp {:verbose false}))
      (local project (native-build.Project {:name output
                                            :compiler compiler
                                            :build-dir build-dir}))
      (project:add-executable src)
      (local binary (project:build))
      (assert (fs.exists binary) "built executable should exist")
      (local run-result (project:run))
      (assert (= (trim-line-ending run-result.stdout) "native-build-sync")
              "project run stdout should match"))))

(fn test-project-build-async []
  (with-temp-dir
    (fn [dir]
      (local src (fs.join-path dir "async.cpp"))
      (local helper-src (fs.join-path dir "helper.cpp"))
      (local helper-hdr (fs.join-path dir "helper.h"))
      (local build-dir (fs.join-path dir "obj"))
      (local output (fs.join-path dir "app-async"))
      (fs.write-file helper-hdr "#pragma once\nint helper_value();\n")
      (fs.write-file helper-src
                     (.. "#include \"helper.h\"\n"
                         "int helper_value() {\n"
                         "    return 77;\n"
                         "}\n"))
      (fs.write-file src
                     (.. "#include <iostream>\n"
                         "#include \"helper.h\"\n"
                         "int main() {\n"
                         "    std::cout << \"native-build-async-\" << helper_value();\n"
                         "    return 0;\n"
                         "}\n"))

      (local compiler (native-build.Gpp {:verbose false :max-parallel 1}))
      (local project (native-build.Project {:name output
                                            :compiler compiler
                                            :build-dir build-dir}))
      (project:add-executable src)
      (project:add-executable helper-src)
      (project:add-include-directory dir)
      (local token (project:build-async {:max-parallel 2}))
      (local binary (token:wait))
      (assert (fs.exists binary) "async built executable should exist")
      (local run-result (project:run))
      (assert (= (trim-line-ending run-result.stdout) "native-build-async-77")
              "async project run stdout should match"))))

(fn test-static-library-linking []
  (with-temp-dir
    (fn [dir]
      (local lib-src (fs.join-path dir "math.cpp"))
      (local lib-hdr (fs.join-path dir "math.h"))
      (local app-src (fs.join-path dir "main.cpp"))

      (fs.write-file lib-hdr
                     "#pragma once\nint add_two_numbers(int a, int b);\n")
      (fs.write-file lib-src
                     (.. "#include \"math.h\"\n"
                         "int add_two_numbers(int a, int b) {\n"
                         "    return a + b;\n"
                         "}\n"))
      (fs.write-file app-src
                     (.. "#include <iostream>\n"
                         "#include \"math.h\"\n"
                         "int main() {\n"
                         "    std::cout << add_two_numbers(2, 5);\n"
                         "    return 0;\n"
                         "}\n"))

      (local compiler (native-build.Gpp {:verbose false}))
      (local archiver (native-build.Ar {:verbose false}))
      (local library (native-build.Library {:name "libmathx"
                                            :compiler compiler
                                            :archiver archiver
                                            :build-dir (fs.join-path dir "lib-obj")}))
      (library:add-source lib-src)
      (library:add-header lib-hdr)
      (library:add-include-directory dir)
      (local archive (library:build))
      (assert (fs.exists archive) "static archive should exist")

      (local project (native-build.Project {:name (fs.join-path dir "use-lib")
                                            :compiler compiler
                                            :build-dir (fs.join-path dir "app-obj")}))
      (project:add-executable app-src)
      (project:add-include-directory dir)
      (project:add-static-lib archive)
      (local binary (project:build))
      (assert (fs.exists binary) "linked executable should exist")
      (local run-result (project:run))
      (assert (= (trim-line-ending run-result.stdout) "7")
              "linked binary output should be 7"))))

(fn test-library-shared-and-package []
  (with-temp-dir
    (fn [dir]
      (local lib-src (fs.join-path dir "pkg.cpp"))
      (local lib-hdr (fs.join-path dir "pkg.h"))
      (local package-dir (fs.join-path dir "libpkg"))

      (fs.write-file lib-hdr
                     "#pragma once\nint pkg_value();\n")
      (fs.write-file lib-src
                     (.. "#include \"pkg.h\"\n"
                         "int pkg_value() {\n"
                         "    return 123;\n"
                         "}\n"))

      (local compiler (native-build.Gpp {:verbose false}))
      (local archiver (native-build.Ar {:verbose false}))
      (local library (native-build.Library {:name "libpkg"
                                            :compiler compiler
                                            :archiver archiver
                                            :build-dir (fs.join-path dir "obj")}))
      (library:add-source lib-src)
      (library:add-header lib-hdr)
      (library:add-include-directory dir)

      (local shared-path (library:build-shared))
      (assert (fs.exists shared-path) "shared library should exist")

      (local package-result (library:package {:dynamic true
                                              :package-dir package-dir}))
      (assert (fs.exists package-result.root) "package root should exist")
      (assert (fs.exists package-result.include) "package include dir should exist")
      (assert (fs.exists package-result.lib) "package lib dir should exist")
      (assert (fs.exists package-result.artifact) "packaged artifact should exist"))))

(fn test-project-build-and-run-gcc []
  (with-temp-dir
    (fn [dir]
      (local src (fs.join-path dir "main.c"))
      (local build-dir (fs.join-path dir "obj"))
      (local output (fs.join-path dir "app-c"))
      (write-sample-c-main src "native-build-gcc")

      (local compiler (native-build.Gcc {:verbose false :standard "c11"}))
      (local project (native-build.Project {:name output
                                            :compiler compiler
                                            :build-dir build-dir}))
      (project:add-executable src)
      (local binary (project:build))
      (assert (fs.exists binary) "built C executable should exist")
      (local run-result (project:run))
      (assert (= (trim-line-ending run-result.stdout) "native-build-gcc")
              "gcc project run stdout should match"))))

(table.insert tests {:name "native-build project g++ sync" :fn test-project-build-and-run-gpp})
(table.insert tests {:name "native-build project g++ async" :fn test-project-build-async})
(table.insert tests {:name "native-build static library linking" :fn test-static-library-linking})
(table.insert tests {:name "native-build shared library package" :fn test-library-shared-and-package})
(table.insert tests {:name "native-build project gcc sync" :fn test-project-build-and-run-gcc})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "native-build"
                       :tests tests})))

{:name "native-build"
 :tests tests
 :main main}
