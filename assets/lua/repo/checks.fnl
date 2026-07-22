(local Process (require :process))

(fn run-check [check-def worktree-root]
  (assert (= (type check-def) "table") "run-check requires a check definition table")
  (assert check-def.argv "check definition requires :argv")
  (assert (= (type check-def.argv) "table") "check :argv must be a table")
  (assert (> (# check-def.argv) 0) "check :argv must not be empty")
  (local process-opts {:args check-def.argv
                       :timeout (or check-def.timeout 120)
                       :merge-stderr true
                       :cwd worktree-root})
  (when check-def.env
    (set process-opts.env check-def.env))
  (Process.run process-opts))

(fn check-result [result]
  {:exit-code result.exit-code
   :timed-out (or result.timed-out false)
   :signal result.signal
   :stdout (or result.stdout "")
   :stderr (or result.stderr "")
   :duration-ms (or result.duration-ms 0)
   :status (if result.timed-out
               :timeout
               result.signal
               :error
               (not= result.exit-code 0)
               :fail
               :pass)})

{:run-check run-check
 :check-result check-result}
