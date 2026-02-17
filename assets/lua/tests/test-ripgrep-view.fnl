(local fs (require :fs))
(local callbacks (require :callbacks))
(local BuildContext (require :build-context))
(local RipgrepView (require :ripgrep-view))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "ripgrep-view-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "rg-view-test-" (os.time) "-" temp-counter)))
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

(fn make-ctx []
  (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                 :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn wait-until [pred timeout-ms]
  (callbacks.run-loop {:poll-jobs false
                       :poll-http false
                       :poll-process true
                       :sleep-ms 0
                       :timeout-ms (or timeout-ms 3000)
                       :until pred}))

(fn ripgrep-view-prefills-from-runtime-options []
  (local ctx (make-ctx))
  (local builder (RipgrepView {:path "/default-path"
                               :query "default-query"}))
  (local view (builder ctx {:path "/runtime-path"
                            :query "runtime-query"}))
  (assert (= view.path "/runtime-path") "runtime :path should override constructor :path")
  (assert (= view.query "runtime-query") "runtime :query should override constructor :query")
  (assert (= (view.path-input:get-text) "/runtime-path") "path input should be prefilled")
  (assert (= (view.query-input:get-text) "runtime-query") "query input should be prefilled")
  (view:drop))

(fn ripgrep-view-search-populates-list-results []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "a.txt") "alpha needle\n")
      (fs.write-file (fs.join-path dir "b.txt") "beta\n")
      (local ctx (make-ctx))
      (local view ((RipgrepView {:path dir :query "needle"}) ctx))
      (assert (view:run-search) "run-search should start when query is non-empty")
      (assert (wait-until (fn [] (> (length view.results) 0)) 5000)
              "search should eventually produce results")
      (assert (> (length view.results) 0) "results should contain matches")
      (assert (> (length view.results-list.items) 0) "list-view should receive result items")
      (view:drop))))

(fn ripgrep-view-empty-query-does-not-search []
  (local ctx (make-ctx))
  (local view ((RipgrepView {:path "." :query ""}) ctx))
  (assert (not (view:run-search)) "run-search should return false for empty query")
  (assert (= (length view.results) 0) "empty query should keep results empty")
  (view:drop))

(fn ripgrep-view-cancels-previous-search-before-starting-next []
  (with-temp-dir
    (fn [dir]
      (fs.write-file (fs.join-path dir "a.txt") "alpha needle\n")
      (local ctx (make-ctx))
      (local view ((RipgrepView {:path dir :query "needle"}) ctx))
      (assert (view:run-search {:program "sh"
                                :program-args ["-c" "sleep 2"]})
              "slow test search should start")
      (assert (view:run-search {:query "needle" :path dir})
              "second search should start and cancel previous")
      (assert (wait-until (fn [] (> (length view.results) 0)) 5000)
              "second search should produce results")
      (assert (> (length view.results) 0) "second search should keep results")
      (view:drop))))

(fn ripgrep-view-trims-large-result-sets []
  (with-temp-dir
    (fn [dir]
      (for [idx 1 15]
        (fs.write-file (fs.join-path dir (.. "file-" idx ".txt")) "needle value\n"))
      (local ctx (make-ctx))
      (local view ((RipgrepView {:path dir
                                 :query "needle"
                                 :max-results 5}) ctx))
      (assert (view:run-search {:max-count 1}) "search should start")
      (assert (wait-until (fn [] (or view.results-truncated (> (length view.results) 0))) 5000)
              "search should finish")
      (assert (= (length view.results) 5) "results should be capped by :max-results")
      (assert (= view.results-truncated true) "view should mark that results were truncated")
      (assert (= view.last-shown-results 5) "view should track number of shown results")
      (assert (> view.last-total-results 5) "view should track original total result count")
      (view:drop))))

(table.insert tests {:name "ripgrep view prefills runtime options"
                     :fn ripgrep-view-prefills-from-runtime-options})
(table.insert tests {:name "ripgrep view search populates list results"
                     :fn ripgrep-view-search-populates-list-results})
(table.insert tests {:name "ripgrep view empty query does not search"
                     :fn ripgrep-view-empty-query-does-not-search})
(table.insert tests {:name "ripgrep view cancels previous search"
                     :fn ripgrep-view-cancels-previous-search-before-starting-next})
(table.insert tests {:name "ripgrep view trims large result sets"
                     :fn ripgrep-view-trims-large-result-sets})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ripgrep-view"
                       :tests tests})))

{:name "ripgrep-view"
 :tests tests
 :main main}
