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

(fn parse-tree-returns-bounded-summary []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "tree.fnl" "(fn hello [name]\n  (print name))\n{:hello hello}\n"))
      (local service (new-service))
      (local result (service:parse-tree {:file path :max-chars 24}))
      (assert result.ok)
      (assert (= result.file (fs.absolute path)))
      (assert (= (type result.root-type) :string))
      (assert (= (type result.sexpr) :string))
      (assert (<= (# result.sexpr) 24))
      (assert result.truncated?)
      (assert (= (type result.diagnostics) :table))
      (assert (= (# result.diagnostics) 0)))))

(fn parse-tree-degrades-on-invalid-fennel []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "broken-tree.fnl" "(fn broken [item]\n  (print item)\n"))
      (local service (new-service))
      (local result (service:parse-tree {:file path}))
      (assert (not result.ok))
      (assert (= result.file (fs.absolute path)))
      (assert (= (type result.root-type) :string))
      (assert (= (type result.sexpr) :string))
      (assert (= result.truncated? false))
      (assert (> (# result.diagnostics) 0))
      (assert (= (. (. result.diagnostics 1) :kind) :parse)))))

(fn enclosing-form-finds-smallest-delimited-form []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "form.fnl" "(fn outer [item]\n  (let [wrapped item]\n    (print item)\n    wrapped))\n"))
      (local service (new-service))
      (local result (service:enclosing-form {:file path :line 3 :column 12}))
      (assert result.ok)
      (assert (= result.file (fs.absolute path)))
      (assert (= result.form "(print item)"))
      (assert (= (type result.node-type) :string))
      (assert (= (type result.start) :table))
      (assert (= (type result.end) :table))
      (assert (= result.start.line 3))
      (assert (= (type result.diagnostics) :table))
      (assert (= (# result.diagnostics) 0)))))

(fn enclosing-form-at-opening-delimiter-returns-whole-form []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "opening.fnl" "(fn outer [item]\n  (let [wrapped item]\n    (print item)\n    wrapped))\n"))
      (local service (new-service))
      (local result (service:enclosing-form {:file path :line 3 :column 5}))
      (assert result.ok)
      (assert (= result.form "(print item)")))))

(fn enclosing-form-rejects-column-past-line-end []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "outside-column.fnl" "(fn outer [item]\n  (print item))\n"))
      (local service (new-service))
      (local result (service:enclosing-form {:file path :line 1 :column 24}))
      (assert (not result.ok))
      (assert (= result.file (fs.absolute path)))
      (assert (> (# result.diagnostics) 0))
      (local diagnostic (. result.diagnostics 1))
      (assert (= diagnostic.kind :input))
      (assert (string.find diagnostic.message "outside the file" 1 true)))))

(fn structure-metrics-return-module-and-function-data []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "metrics.fnl" "(fn outer [item]\n  (if item\n    (print item)\n    nil))\n{:outer outer}\n"))
      (local service (new-service))
      (local result (service:structure-metrics {:file path}))
      (assert result.ok)
      (assert (= result.file (fs.absolute path)))
      (assert (= (type result.metrics) :table))
      (assert (>= result.metrics.module-lines 5))
      (assert (>= result.metrics.max-nesting-depth 1))
      (assert (= (type result.metrics.functions) :table))
      (assert (> (# result.metrics.functions) 0))
      (local fn-info (. result.metrics.functions 1))
      (assert (= fn-info.name "outer"))
      (assert (= fn-info.line 1))
      (assert (= (type result.diagnostics) :table)))))

(fn constraints-files-wrapper-returns-runner-status []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "constraints.fnl" "{:ok true}\n"))
      (local service (new-service))
      (local result (service:check-constraints-files {:files [path]}))
      (assert (= result.status :pass))
      (assert (= (type result.counts) :table))
      (assert (= (type result.diagnostics) :table)))))

(table.insert tests {:name "valid file compile succeeds"
                     :fn valid-file-compile-succeeds})
(table.insert tests {:name "malformed delimiter fails with diagnostic"
                     :fn malformed-delimiter-fails-with-diagnostic})
(table.insert tests {:name "file target checks only requested files"
                     :fn file-target-checks-only-requested-files})
(table.insert tests {:name "non-Fennel file is rejected"
                      :fn non-fennel-file-is-rejected})
(table.insert tests {:name "parse-tree-returns-bounded-summary"
                     :fn parse-tree-returns-bounded-summary})
(table.insert tests {:name "parse-tree-degrades-on-invalid-fennel"
                     :fn parse-tree-degrades-on-invalid-fennel})
(table.insert tests {:name "enclosing-form-finds-smallest-delimited-form"
                     :fn enclosing-form-finds-smallest-delimited-form})
(table.insert tests {:name "enclosing-form-at-opening-delimiter-returns-whole-form"
                     :fn enclosing-form-at-opening-delimiter-returns-whole-form})
(table.insert tests {:name "enclosing-form-rejects-column-past-line-end"
                     :fn enclosing-form-rejects-column-past-line-end})
(table.insert tests {:name "structure-metrics-return-module-and-function-data"
                     :fn structure-metrics-return-module-and-function-data})
(table.insert tests {:name "constraints-files-wrapper-returns-runner-status"
                     :fn constraints-files-wrapper-returns-runner-status})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fennel-validation"
                       :tests tests})))

{:name "fennel-validation"
 :tests tests
 :main main}
