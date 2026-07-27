(local tests [])
(local ts (require :tree-sitter))

(fn fennel-parser-produces-root-and-locations []
  (local source "(fn hello [name]\n  (print name))\n")
  (local tree (ts.parse source {:language :fennel}))
  (local root (tree:root))
  (assert (not (root:is-null)))
  (assert (> (root:child-count) 0))
  (assert (string.find (root:sexpr) "fn" 1 true))
  (local start (root:start-point))
  (local finish (root:end-point))
  (assert (= start.row 0))
  (assert (= start.column 0))
  (assert (>= finish.row 1))
  (assert (>= (root:end-byte) (root:start-byte))))

(fn default-cpp-parser-still-works []
  (local tree (ts.parse "int main() { return 0; }"))
  (local root (tree:root))
  (assert (not (root:is-null)))
  (assert (= (root:type) "translation_unit")))

(fn unknown-language-fails-loudly []
  (local (ok err) (pcall (fn []
                           (ts.parse "(print :x)" {:language :unknown}))))
  (assert (not ok))
  (assert (string.find (tostring err) "tree-sitter.parse unsupported language" 1 true)))

(table.insert tests {:name "tree-sitter parses Fennel with locations"
                     :fn fennel-parser-produces-root-and-locations})
(table.insert tests {:name "tree-sitter default C++ parser remains compatible"
                     :fn default-cpp-parser-still-works})
(table.insert tests {:name "tree-sitter rejects unknown languages"
                     :fn unknown-language-fails-loudly})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "tree-sitter-fennel"
                       :tests tests})))

{:name "tree-sitter-fennel"
 :tests tests
 :main main}
