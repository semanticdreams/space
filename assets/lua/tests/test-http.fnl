(fn test-requires-url []
  (let [binding (require :http)]
    (assert binding "http binding missing")
    (let [(ok err) (pcall binding.request {})]
      (assert (not ok) "http.request without url should fail")
      (assert (string.find err "requires" 1 true) err))))

(fn test-cancel-unknown []
  (let [binding (require :http)]
    (assert binding "http binding missing")
    (assert (not (binding.cancel 999999)) "unknown cancel should return false")))

(local tests [{ :name "http missing url throws" :fn test-requires-url}
 { :name "http cancel unknown id" :fn test-cancel-unknown}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "http"
                       :tests tests})))

{:name "http"
 :tests tests
 :main main}
