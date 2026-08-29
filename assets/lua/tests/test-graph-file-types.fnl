(local FileTypes (require :graph/file-types))

(fn assert-text-classification [path extension module-kind module-label module-key-prefix]
  (local info (FileTypes.classify path))
  (assert info.text?)
  (assert info.viewer?)
  (assert (= info.path path))
  (assert (= info.extension extension))
  (assert (= info.module-kind module-kind))
  (assert (= info.module-label module-label))
  (assert (= info.module-key-prefix module-key-prefix)))

(fn graph-file-types-classifies-fennel []
  (assert-text-classification "/tmp/main.fnl"
                              ".fnl"
                              :fnl
                              "Open as Fennel Module"
                              "fnl-module:"))

(fn graph-file-types-classifies-cpp-family []
  (each [_ path (ipairs ["/tmp/main.cpp"
                         "/tmp/main.cc"
                         "/tmp/main.cxx"
                         "/tmp/main.h"
                         "/tmp/main.hpp"
                         "/tmp/main.hh"])]
    (assert-text-classification path
                                (string.match path "(%.[^%.]+)$")
                                :cpp
                                "Open as C++ Module"
                                "cpp-module:")))

(fn graph-file-types-classifies-generic-text []
  (each [_ path (ipairs ["/tmp/README.md"
                         "/tmp/note.txt"
                         "/tmp/config.json"
                         "/tmp/settings.toml"
                         "/tmp/app.lua"
                         "/tmp/script.py"
                         "/tmp/CMakeLists.txt"
                         "/tmp/Makefile"
                         "/tmp/Dockerfile"])]
    (local matched-extension (string.match path "(%.[^%.]+)$"))
    (local expected-extension
      (if matched-extension
          matched-extension
          ""))
    (assert-text-classification path
                                expected-extension
                                :text
                                "Open as Text Module"
                                "text-module:")))

(fn graph-file-types-omits-binary-unknown []
  (each [_ path (ipairs ["/tmp/blob.bin"
                         "/tmp/image.png"
                         "/tmp/archive.zip"
                         "/tmp/no-extension"])]
    (local info (FileTypes.classify path))
    (assert (= info.text? false))
    (assert (= info.viewer? false))
    (assert (= info.module-kind nil))
    (assert (= info.module-label nil))
    (assert (= info.module-key-prefix nil))))

(fn graph-file-types-rejects-invalid-paths []
  (local (ok err) (pcall FileTypes.classify ""))
  (assert (not ok))
  (assert (string.find (tostring err)
                       "graph.file-types classify requires a non-empty path"
                       1
                       true)))

(local tests [{:name "graph file types classifies Fennel"
               :fn graph-file-types-classifies-fennel}
              {:name "graph file types classifies C++ family"
               :fn graph-file-types-classifies-cpp-family}
              {:name "graph file types classifies generic text"
               :fn graph-file-types-classifies-generic-text}
              {:name "graph file types omits binary unknown"
               :fn graph-file-types-omits-binary-unknown}
              {:name "graph file types rejects invalid paths"
               :fn graph-file-types-rejects-invalid-paths}])

(fn main []
  (each [_ test (ipairs tests)]
    (test.fn)))

{:name "test-graph-file-types"
 :tests tests
 :main main}
