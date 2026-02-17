(local fs (require :fs))
(local Ripgrep (require :ripgrep))
(local callbacks (require :callbacks))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "ripgrep-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "rg-test-" (os.time) "-" temp-counter)))
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

(fn wait-until [pred timeout-ms]
  (callbacks.run-loop {:poll-jobs false
                       :poll-http false
                       :poll-process true
                       :sleep-ms 0
                       :timeout-ms (or timeout-ms 2000)
                       :until pred}))

(fn write-sample-tree [dir]
  (local src-dir (fs.join-path dir "src"))
  (local docs-dir (fs.join-path dir "docs"))
  (fs.create-dirs src-dir)
  (fs.create-dirs docs-dir)
  (fs.write-file (fs.join-path src-dir "alpha.txt")
                 "alpha needle\nbeta\nNEEDLE upper\n")
  (fs.write-file (fs.join-path src-dir "beta.txt")
                 "gamma\nneedle beta\n")
  (fs.write-file (fs.join-path docs-dir "guide.md")
                 "needle docs\n")
  (fs.write-file (fs.join-path docs-dir "ignore.log")
                 "needle log\n")
  true)

(fn matches-in-path [matches suffix]
  (accumulate [count 0 _ entry (ipairs (or matches []))]
    (if (and entry entry.path (string.find entry.path suffix 1 true))
        (+ count 1)
        count)))

(fn ripgrep-available-check []
  (assert (Ripgrep.available?) "ripgrep binary should be available"))

(fn ripgrep-basic-search-returns-matches []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (local result (Ripgrep.search {:query "needle"
                                     :cwd dir
                                     :paths ["src" "docs"]}))
      (assert result.ok "search should succeed")
      (assert (= result.exit-code 0) "search should exit 0 when matches exist")
      (assert (> (length result.matches) 0) "search should produce matches")
      (local first (. result.matches 1))
      (assert first.path "match should include path")
      (assert (> first.line 0) "match should include line number")
      (assert (> first.column 0) "match should include column")
      (assert (string.find first.text "needle") "match should include line text"))))

(fn ripgrep-no-matches-is-not-error []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (local result (Ripgrep.search {:query "zzzz-not-present"
                                     :cwd dir
                                     :paths ["src" "docs"]}))
      (assert result.ok "no-match search should still be ok")
      (assert (= result.exit-code 1) "no-match should exit with code 1")
      (assert (= (length result.matches) 0) "no-match should produce empty matches"))))

(fn ripgrep-glob-filters-results []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (local result (Ripgrep.search {:query "needle"
                                     :cwd dir
                                     :paths ["docs"]
                                     :globs ["*.md"]}))
      (assert result.ok "glob search should succeed")
      (assert (= (matches-in-path result.matches "guide.md") 1)
              "glob should include guide.md")
      (assert (= (matches-in-path result.matches "ignore.log") 0)
              "glob should exclude ignore.log"))))

(fn ripgrep-case-modes-work []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (local ignore-result (Ripgrep.search {:query "needle"
                                            :cwd dir
                                            :paths ["src"]
                                            :case :ignore}))
      (local sensitive-result (Ripgrep.search {:query "needle"
                                               :cwd dir
                                               :paths ["src"]
                                               :case :sensitive}))
      (assert ignore-result.ok "ignore-case should succeed")
      (assert sensitive-result.ok "sensitive-case should succeed")
      (assert (> (length ignore-result.matches) (length sensitive-result.matches))
              "ignore-case should return more matches when uppercase variants exist"))))

(fn ripgrep-literal-mode-works []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "pattern.txt") "a+b\naab\n")
      (local regex-result (Ripgrep.search {:query "a+b"
                                           :cwd dir
                                           :paths ["."]}))
      (local literal-result (Ripgrep.search {:query "a+b"
                                             :cwd dir
                                             :paths ["."]
                                             :literal true}))
      (assert regex-result.ok "regex search should succeed")
      (assert literal-result.ok "literal search should succeed")
      (assert (= (length literal-result.matches) 1)
              "literal mode should match only literal a+b text")
      (assert (>= (length regex-result.matches) (length literal-result.matches))
              "regex mode should not yield fewer matches than literal for this input"))))

(fn ripgrep-invalid-regex-returns-error []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (local result (Ripgrep.search {:query "[unterminated"
                                     :cwd dir
                                     :paths ["src"]}))
      (assert (not result.ok) "invalid regex should fail")
      (assert (= result.exit-code 2) "invalid regex should exit with code 2")
      (assert (> (# result.stderr) 0) "invalid regex should include stderr"))))

(fn ripgrep-missing-binary-returns-error []
  (local available (Ripgrep.available? {:program "definitely-not-rg"}))
  (assert (not available) "available? should be false for missing program")
  (local result (Ripgrep.search {:program "definitely-not-rg"
                                 :query "needle"
                                 :paths ["."]}))
  (assert (not result.ok) "search should fail when binary is missing")
  (assert (= result.exit-code 127) "missing binary should report exit 127"))

(fn ripgrep-validates-input []
  (local (ok1 err1) (pcall (fn [] (Ripgrep.search {:query "" :paths ["."]}))))
  (assert (not ok1) "empty query should raise")
  (assert (string.find (tostring err1) "query") "error should mention query")

  (local (ok2 err2) (pcall (fn [] (Ripgrep.search {:query "x" :paths "not-array"}))))
  (assert (not ok2) "non-array paths should raise")
  (assert (string.find (tostring err2) "array") "error should mention array"))

(fn ripgrep-async-success-callback []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (var received nil)
      (local token
        (Ripgrep.search-async {:query "needle"
                               :cwd dir
                               :paths ["src" "docs"]}
                              (fn [result]
                                (set received result))))
      (assert token.id "search-async should return token with process id")
      (assert (wait-until (fn [] received) 4000) "async callback should fire")
      (assert received.ok "async result should be ok")
      (assert (= received.cancelled false) "async result should not be cancelled")
      (assert (> (length received.matches) 0) "async search should return matches"))))

(fn ripgrep-async-no-match-callback []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (var received nil)
      (Ripgrep.search-async {:query "zzzz-not-present"
                             :cwd dir
                             :paths ["src"]}
                            (fn [result]
                              (set received result)))
      (assert (wait-until (fn [] received) 4000) "async no-match callback should fire")
      (assert received.ok "no-match async search should still be ok")
      (assert (= received.exit-code 1) "no-match async should exit 1")
      (assert (= (length received.matches) 0) "no-match async should have empty matches"))))

(fn ripgrep-async-invalid-regex-callback []
  (with-temp-dir
    (fn [dir]
      (write-sample-tree dir)
      (var received nil)
      (Ripgrep.search-async {:query "[unterminated"
                             :cwd dir
                             :paths ["src"]}
                            (fn [result]
                              (set received result)))
      (assert (wait-until (fn [] received) 4000) "async invalid regex callback should fire")
      (assert (not received.ok) "invalid regex async should fail")
      (assert (= received.exit-code 2) "invalid regex async should exit 2"))))

(fn ripgrep-async-cancel-flags-result []
  (var received nil)
  (local token
    (Ripgrep.search-async {:program "sh"
                           :program-args ["-c" "sleep 2"]
                           :query "needle"
                           :paths ["."]}
                          (fn [result]
                            (set received result))))
  (assert token.id "cancel test should get process id")
  (token:cancel)
  (assert (wait-until (fn [] received) 4000) "cancelled async callback should fire")
  (assert (= received.cancelled true) "cancelled async result should set :cancelled")
  (assert (not received.ok) "cancelled async result should not be ok"))

(fn ripgrep-async-cancel-suppress-callback []
  (var received false)
  (local token
    (Ripgrep.search-async {:program "sh"
                           :program-args ["-c" "sleep 1"]
                           :query "needle"
                           :paths ["."]}
                          (fn [_result]
                            (set received true))))
  (assert token.id "suppress-callback cancel should get process id")
  (token:cancel {:suppress-callback true})
  (callbacks.run-loop {:poll-jobs false
                       :poll-http false
                       :poll-process true
                       :sleep-ms 0
                       :timeout-ms 1400
                       :until (fn [] false)})
  (assert (not received) "suppress-callback cancel should prevent callback invocation"))

(table.insert tests {:name "ripgrep availability check" :fn ripgrep-available-check})
(table.insert tests {:name "ripgrep basic search returns matches" :fn ripgrep-basic-search-returns-matches})
(table.insert tests {:name "ripgrep no matches is not an error" :fn ripgrep-no-matches-is-not-error})
(table.insert tests {:name "ripgrep glob filters results" :fn ripgrep-glob-filters-results})
(table.insert tests {:name "ripgrep case modes work" :fn ripgrep-case-modes-work})
(table.insert tests {:name "ripgrep literal mode works" :fn ripgrep-literal-mode-works})
(table.insert tests {:name "ripgrep invalid regex returns error" :fn ripgrep-invalid-regex-returns-error})
(table.insert tests {:name "ripgrep missing binary returns error" :fn ripgrep-missing-binary-returns-error})
(table.insert tests {:name "ripgrep validates input" :fn ripgrep-validates-input})
(table.insert tests {:name "ripgrep async success callback" :fn ripgrep-async-success-callback})
(table.insert tests {:name "ripgrep async no-match callback" :fn ripgrep-async-no-match-callback})
(table.insert tests {:name "ripgrep async invalid regex callback" :fn ripgrep-async-invalid-regex-callback})
(table.insert tests {:name "ripgrep async cancel flags result" :fn ripgrep-async-cancel-flags-result})
(table.insert tests {:name "ripgrep async cancel suppresses callback" :fn ripgrep-async-cancel-suppress-callback})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ripgrep"
                       :tests tests})))

{:name "ripgrep"
 :tests tests
 :main main}
