(local tests [])
(local fs (require :fs))
(local tempfile (require :tempfile))
(local ServiceModule (require :llm/fennel-validation/service))

(fn write-temp-file [dir name content]
  (local path (fs.join-path dir name))
  (fs.write-file path content)
  path)

(fn new-service []
  (ServiceModule.FennelValidationService {}))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "fennel-validation-test-"}))
  (local (ok result) (pcall f handle.path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn valid-file-compile-succeeds []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "valid.fnl" "(fn hello [name]\n  (print name))\n{:hello hello}\n"))
      (local service (new-service))
      (local result (service:check-files {:files [path]}))
      (assert result.ok)
      (assert (= result.status :pass))
      (assert (= (# result.checked) 1))
      (assert (= (. result.checked 1) (fs.absolute path)))
      (assert (= result.summary.checked 1))
      (assert (= result.summary.failed 0))
      (assert (= (# result.diagnostics) 0)))))

(fn malformed-delimiter-fails-with-diagnostic []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "broken.fnl" "(fn broken [name]\n  (print name)\n"))
      (local service (new-service))
      (local result (service:check-files {:files [path]}))
      (assert (not result.ok))
      (assert (= result.status :fail))
      (assert (= result.summary.checked 1))
      (assert (= result.summary.failed 1))
      (local diagnostic (. result.diagnostics 1))
      (assert diagnostic)
      (assert (= diagnostic.kind :compile))
      (assert (= diagnostic.file (fs.absolute path)))
      (assert (> (# diagnostic.message) 0))
      (assert (if (string.find diagnostic.hint "enclosing form" 1 true)
                  true
                  (string.find diagnostic.hint "delimiter" 1 true)
                  true
                  false)))))

(fn file-target-checks-only-requested-files []
  (with-temp-dir
    (fn [dir]
      (local good (write-temp-file dir "good.fnl" "{:ok true}\n"))
      (write-temp-file dir "bad.fnl" "(fn bad [x]\n")
      (local service (new-service))
      (local result (service:check-files {:files [good]}))
      (assert result.ok)
      (assert (= result.status :pass))
      (assert (= (# result.checked) 1))
      (assert (= (. result.checked 1) (fs.absolute good)))
      (assert (= result.summary.checked 1))
      (assert (= result.summary.failed 0)))))

(fn non-fennel-file-is-rejected []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "README.md" "# docs\n"))
      (local service (new-service))
      (local result (service:check-files {:files [path]}))
      (assert (not result.ok))
      (assert (= result.status :fail))
      (assert (= result.summary.checked 0))
      (local diagnostic (. result.diagnostics 1))
      (assert diagnostic)
      (assert (= diagnostic.kind :input))
      (assert (string.find diagnostic.message ".fnl" 1 true)))))

(table.insert tests {:name "valid file compile succeeds"
                     :fn valid-file-compile-succeeds})
(table.insert tests {:name "malformed delimiter fails with diagnostic"
                     :fn malformed-delimiter-fails-with-diagnostic})
(table.insert tests {:name "file target checks only requested files"
                     :fn file-target-checks-only-requested-files})
(table.insert tests {:name "non-Fennel file is rejected"
                     :fn non-fennel-file-is-rejected})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fennel-validation"
                       :tests tests})))

{:name "fennel-validation"
 :tests tests
 :main main}
