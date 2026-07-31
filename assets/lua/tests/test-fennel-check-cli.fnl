(local tests [])
(local fs (require :fs))
(local json (require :json))
(local tempfile (require :tempfile))
(local FennelCheck (require :tools/fennel-check))

(fn write-temp-file [dir name content]
  (local path (fs.join-path dir name))
  (fs.write-file path content)
  path)

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "fennel-check-cli-test-"}))
  (local (ok result) (pcall f handle.path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn run-main-capturing [argv]
  (var printed nil)
  (var exit-code nil)
  (FennelCheck.main {:argv argv
                     :print (fn [msg] (set printed msg))
                     :exit (fn [code] (set exit-code code))})
  {:printed printed :exit-code exit-code})

(fn parse-result [captured]
  (assert captured.printed "fennel-check should print a JSON result")
  (json.loads captured.printed))

(fn valid-explicit-file-exits-zero []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "valid.fnl" "{:ok true}\n"))
      (local captured (run-main-capturing ["--target" "files" "--file" path]))
      (local result (parse-result captured))
      (assert (= captured.exit-code 0))
      (assert result.ok)
      (assert (= result.status "pass"))
      (assert (= result.summary.checked 1))
      (assert (= result.summary.failed 0))
      (assert (= (# result.checked) 1))
      (assert (= (. result.checked 1) (fs.absolute path)))
      (assert (= (# result.diagnostics) 0)))))

(fn broken-explicit-file-exits-one []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "broken.fnl" "(fn broken [x]\n"))
      (local captured (run-main-capturing ["--target" "files" "--file" path]))
      (local result (parse-result captured))
      (assert (= captured.exit-code 1))
      (assert (not result.ok))
      (assert (= result.status "fail"))
      (assert (= result.summary.checked 1))
      (assert (= result.summary.failed 1))
      (local diagnostic (. result.diagnostics 1))
      (assert diagnostic)
      (assert (= diagnostic.kind "compile"))
      (assert (= diagnostic.file (fs.absolute path)))
      (assert (> (# diagnostic.message) 0)))))

(fn valid-explicit-file-ignores-broken-sibling []
  (with-temp-dir
    (fn [dir]
      (local good (write-temp-file dir "good.fnl" "{:ok true}\n"))
      (write-temp-file dir "bad.fnl" "(fn bad [x]\n")
      (local captured (run-main-capturing ["--target" "files" "--file" good]))
      (local result (parse-result captured))
      (assert (= captured.exit-code 0))
      (assert result.ok)
      (assert (= result.status "pass"))
      (assert (= result.summary.checked 1))
      (assert (= result.summary.failed 0))
      (assert (= (# result.checked) 1))
      (assert (= (. result.checked 1) (fs.absolute good)))
      (assert (= (# result.diagnostics) 0)))))

(fn non-fennel-file-exits-one []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "README.md" "# docs\n"))
      (local captured (run-main-capturing ["--target" "files" "--file" path]))
      (local result (parse-result captured))
      (assert (= captured.exit-code 1))
      (assert (not result.ok))
      (assert (= result.status "fail"))
      (assert (= result.summary.checked 0))
      (assert (= result.summary.failed 1))
      (local diagnostic (. result.diagnostics 1))
      (assert diagnostic)
      (assert (= diagnostic.kind "input"))
      (assert (= diagnostic.file (fs.absolute path)))
      (assert (string.find diagnostic.message ".fnl" 1 true)))))

(table.insert tests {:name "valid explicit file exits 0"
                     :fn valid-explicit-file-exits-zero})
(table.insert tests {:name "broken explicit file exits 1"
                     :fn broken-explicit-file-exits-one})
(table.insert tests {:name "valid explicit file ignores broken sibling"
                     :fn valid-explicit-file-ignores-broken-sibling})
(table.insert tests {:name "non-Fennel file exits 1"
                     :fn non-fennel-file-exits-one})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fennel-check-cli"
                       :tests tests})))

{:name "fennel-check-cli"
 :tests tests
 :main main}
