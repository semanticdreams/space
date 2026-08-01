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

(fn run-main-capturing-global-argv [argv]
  (local previous _G.arg)
  (var printed nil)
  (var exit-code nil)
  (local print-fn (fn [msg] (set printed msg)))
  (local exit-fn (fn [code] (set exit-code code)))
  (set _G.arg argv)
  (FennelCheck.main {:print print-fn
                     :exit exit-fn})
  (set _G.arg previous)
  {:printed printed :exit-code exit-code})

(fn parse-result [captured]
  (assert captured.printed "fennel-check should print a JSON result")
  (json.loads captured.printed))

(fn validation-output-strips-output-flag []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--output" "summary" "--target" "repo"] :json))
  (assert (not parsed.error) (.. "unexpected parse error: " (tostring parsed.error)))
  (assert (= parsed.output :summary))
  (assert (= (# parsed.argv) 2))
  (assert (= (. parsed.argv 1) "--target"))
  (assert (= (. parsed.argv 2) "repo")))

(fn validation-output-defaults-when-flag-absent []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--target" "repo"] :json))
  (assert (not parsed.error) (.. "unexpected parse error: " (tostring parsed.error)))
  (assert (= parsed.output :json))
  (assert (= (# parsed.argv) 2))
  (assert (= (. parsed.argv 1) "--target"))
  (assert (= (. parsed.argv 2) "repo")))

(fn validation-output-rejects-invalid-mode []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--output" "xml" "--target" "repo"] :json))
  (assert parsed.error "invalid mode should produce an error")
  (assert (string.find parsed.error "--output must be json or summary" 1 true)
          (.. "unexpected error: " parsed.error)))

(fn validation-output-invalid-mode-resets-prior-output []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--output" "summary" "--output" "xml"] :json))
  (assert parsed.error "invalid mode should produce an error")
  (assert (= parsed.output :json)))

(fn validation-output-invalid-mode-keeps-default-after-later-valid []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--output" "xml" "--output" "summary"] :json))
  (assert parsed.error "invalid mode should produce an error")
  (assert (= parsed.output :json)))

(fn validation-output-rejects-missing-mode []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--target" "repo" "--output"] :json))
  (assert parsed.error "missing mode should produce an error")
  (assert (string.find parsed.error "--output requires" 1 true)
          (.. "unexpected error: " parsed.error)))

(fn validation-output-missing-mode-resets-prior-output []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--output" "summary" "--output"] :json))
  (assert parsed.error "missing mode should produce an error")
  (assert (= parsed.output :json)))

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

(fn real-entrypoint-global-argv-checks-explicit-file []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "broken.fnl" "(fn broken [x]\n"))
      (local captured (run-main-capturing-global-argv ["--" "--target" "files" "--file" path]))
      (local result (parse-result captured))
      (assert (= captured.exit-code 1))
      (assert (not result.ok))
      (assert (= result.status "fail"))
      (assert (= result.summary.checked 1))
      (assert (= (. result.checked 1) (fs.absolute path)))
      (local diagnostic (. result.diagnostics 1))
      (assert diagnostic)
      (assert (= diagnostic.kind "compile"))
      (assert (= diagnostic.file (fs.absolute path))))))

(fn summary-output-valid-file-is-concise []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "valid.fnl" "{:ok true}\n"))
      (local captured (run-main-capturing ["--output" "summary" "--target" "files" "--file" path]))
      (assert (= captured.exit-code 0))
      (assert (= captured.printed "fennel-check: pass (checked 1 file)")))))

(fn json-output-remains-default []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "valid.fnl" "{:ok true}\n"))
      (local captured (run-main-capturing ["--target" "files" "--file" path]))
      (local result (parse-result captured))
      (assert (= captured.exit-code 0))
      (assert result.ok)
      (assert (= result.status "pass")))))

(fn summary-output-broken-file-includes-diagnostic-and-rerun []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "broken.fnl" "(fn broken [x]\n"))
      (local captured (run-main-capturing ["--output" "summary" "--target" "files" "--file" path]))
      (assert (= captured.exit-code 1))
      (assert (string.find captured.printed "fennel-check: fail (checked 1 file, 1 failed)" 1 true))
      (assert (string.find captured.printed (fs.absolute path) 1 true))
      (assert (string.find captured.printed "rerun with --output json" 1 true)))))

(fn invalid-output-mode-exits-one []
  (local captured (run-main-capturing ["--output" "xml" "--target" "repo"]))
  (assert (= captured.exit-code 1))
  (assert (string.find captured.printed "fennel-check: fail" 1 true))
  (assert (string.find captured.printed "--output must be json or summary" 1 true)))

(table.insert tests {:name "valid explicit file exits 0"
                     :fn valid-explicit-file-exits-zero})
(table.insert tests {:name "broken explicit file exits 1"
                     :fn broken-explicit-file-exits-one})
(table.insert tests {:name "valid explicit file ignores broken sibling"
                     :fn valid-explicit-file-ignores-broken-sibling})
(table.insert tests {:name "non-Fennel file exits 1"
                     :fn non-fennel-file-exits-one})
(table.insert tests {:name "real entrypoint global argv checks explicit file"
                      :fn real-entrypoint-global-argv-checks-explicit-file})
(table.insert tests {:name "summary output valid file is concise"
                     :fn summary-output-valid-file-is-concise})
(table.insert tests {:name "JSON output remains default"
                     :fn json-output-remains-default})
(table.insert tests {:name "summary output broken file includes diagnostic and rerun"
                     :fn summary-output-broken-file-includes-diagnostic-and-rerun})
(table.insert tests {:name "invalid output mode exits one"
                     :fn invalid-output-mode-exits-one})
(table.insert tests {:name "validation output strips output flag"
                     :fn validation-output-strips-output-flag})
(table.insert tests {:name "validation output defaults when flag absent"
                     :fn validation-output-defaults-when-flag-absent})
(table.insert tests {:name "validation output rejects invalid mode"
                     :fn validation-output-rejects-invalid-mode})
(table.insert tests {:name "validation output invalid mode resets prior output"
                     :fn validation-output-invalid-mode-resets-prior-output})
(table.insert tests {:name "validation output invalid mode keeps default after later valid"
                     :fn validation-output-invalid-mode-keeps-default-after-later-valid})
(table.insert tests {:name "validation output rejects missing mode"
                     :fn validation-output-rejects-missing-mode})
(table.insert tests {:name "validation output missing mode resets prior output"
                     :fn validation-output-missing-mode-resets-prior-output})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fennel-check-cli"
                       :tests tests})))

{:name "fennel-check-cli"
 :tests tests
 :main main}
