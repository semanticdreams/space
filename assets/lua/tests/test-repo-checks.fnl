(local tests [])

(fn test-check-result-precedence []
  (local Checks (require :repo/checks))
  ;; timeout must take precedence over nonzero exit
  (local timeout-result {:exit-code 1 :timed-out true :signal nil :stdout "" :stderr "" :duration-ms 5000})
  (local parsed (Checks.check-result timeout-result))
  (assert (= parsed.status :timeout) (.. "timeout should be :timeout, got " (tostring parsed.status)))
  ;; signal must take precedence over nonzero exit
  (local signal-result {:exit-code 1 :timed-out false :signal 9 :stdout "" :stderr "" :duration-ms 100})
  (local parsed2 (Checks.check-result signal-result))
  (assert (= parsed2.status :error) (.. "signal should be :error, got " (tostring parsed2.status)))
  ;; nonzero exit without timeout/signal → :fail
  (local fail-result {:exit-code 1 :timed-out false :signal nil :stdout "err" :stderr "" :duration-ms 50})
  (local parsed3 (Checks.check-result fail-result))
  (assert (= parsed3.status :fail) (.. "nonzero exit should be :fail, got " (tostring parsed3.status)))
  ;; exit 0 → :pass
  (local pass-result {:exit-code 0 :timed-out false :signal nil :stdout "ok" :stderr "" :duration-ms 10})
  (local parsed4 (Checks.check-result pass-result))
  (assert (= parsed4.status :pass) (.. "exit 0 should be :pass, got " (tostring parsed4.status))))

(table.insert tests {:name "check result precedence timeout before exit" :fn test-check-result-precedence})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-checks"
                       :tests tests})))

{:name "repo-checks"
 :tests tests
 :main main}
