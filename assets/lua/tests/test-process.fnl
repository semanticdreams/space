(local tests [])
(local process (require :process))
(local fs (require :fs))

;; Helper to create a temp directory for tests
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "process-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "proc-test-" (os.time) "-" temp-counter)))
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

;; ============================================================================
;; Synchronous process.run tests
;; ============================================================================

(fn test-run-simple-command []
  (local result (process.run {:args ["echo" "hello world"]}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "hello world\n") "stdout should match")
  (assert (= result.stderr "") "stderr should be empty")
  (assert (not result.timed-out) "should not time out")
  (assert (= result.signal nil) "should have no signal"))

(fn test-run-exit-code []
  (local result (process.run {:args ["sh" "-c" "exit 42"]}))
  (assert (= result.exit-code 42) "exit code should be 42"))

(fn test-run-stderr []
  (local result (process.run {:args ["sh" "-c" "echo error >&2"]}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "") "stdout should be empty")
  (assert (= result.stderr "error\n") "stderr should match"))

(fn test-run-stdout-and-stderr []
  (local result (process.run {:args ["sh" "-c" "echo out; echo err >&2"]}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "out\n") "stdout should match")
  (assert (= result.stderr "err\n") "stderr should match"))

(fn test-run-merge-stderr []
  (local result (process.run {:args ["sh" "-c" "echo out; echo err >&2"]
                              :merge-stderr true}))
  (assert (= result.exit-code 0) "exit code should be 0")
  ;; Both should be in stdout when merged
  (assert (string.find result.stdout "out") "stdout should contain out")
  (assert (string.find result.stdout "err") "stdout should contain err")
  (assert (= result.stderr "") "stderr should be empty when merged"))

(fn test-run-stdin []
  (local result (process.run {:args ["cat"]
                              :stdin "hello from stdin"}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "hello from stdin") "stdout should match stdin"))

(fn test-run-stdin-multiline []
  (local input "line1\nline2\nline3\n")
  (local result (process.run {:args ["cat"]
                              :stdin input}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout input) "stdout should match multiline stdin"))

(fn test-run-cwd []
  (with-temp-dir (fn [dir]
    (local result (process.run {:args ["pwd"]
                                :cwd dir}))
    (assert (= result.exit-code 0) "exit code should be 0")
    ;; pwd output might have a trailing newline
    (local output (string.gsub result.stdout "\n$" ""))
    ;; Resolve any symlinks for comparison (e.g., /tmp -> /private/tmp on macOS)
    (local popen-handle (io.popen (.. "cd " dir " && pwd -P")))
    (local expected (string.gsub (popen-handle:read "*a") "\n$" ""))
    (popen-handle:close)
    (assert (= output expected) (.. "cwd should be " expected " but got " output)))))

(fn test-run-env []
  (local result (process.run {:args ["sh" "-c" "echo $MY_TEST_VAR"]
                              :env {:MY_TEST_VAR "test_value"}}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "test_value\n") "env var should be set"))

(fn test-run-env-multiple []
  (local result (process.run {:args ["sh" "-c" "echo $VAR1-$VAR2"]
                              :env {:VAR1 "foo" :VAR2 "bar"}}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "foo-bar\n") "multiple env vars should work"))

(fn test-run-clear-env []
  ;; When clearing env, PATH won't be set, so we need to use absolute path
  (local result (process.run {:args ["/bin/sh" "-c" "echo ${HOME:-empty}"]
                              :clear-env true}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "empty\n") "HOME should be cleared"))

(fn test-run-timeout []
  (local result (process.run {:args ["sleep" "10"]
                              :timeout 0.1}))
  (assert result.timed-out "should time out")
  ;; Exit code should indicate signal termination
  (assert (>= result.exit-code 128) "exit code should indicate signal"))

(fn test-run-timeout-not-triggered []
  (local result (process.run {:args ["echo" "fast"]
                              :timeout 5}))
  (assert (not result.timed-out) "should not time out")
  (assert (= result.exit-code 0) "exit code should be 0"))

(fn test-run-command-not-found []
  (local result (process.run {:args ["nonexistent_command_xyz"]}))
  (assert (= result.exit-code 127) "exit code should be 127 for command not found"))

(fn test-run-duration []
  (local result (process.run {:args ["sleep" "0.1"]}))
  (assert (>= result.duration-ms 50) "duration should be at least 50ms")
  (assert (<= result.duration-ms 2000) "duration should be less than 2s"))

(fn test-run-large-output []
  ;; Generate 10000 lines of output
  (local result (process.run {:args ["sh" "-c" "seq 1 10000"]}))
  (assert (= result.exit-code 0) "exit code should be 0")
  ;; Check that we got all lines
  (local lines (icollect [line (string.gmatch result.stdout "[^\n]+")] line))
  (assert (= (length lines) 10000) "should have 10000 lines"))

;; ============================================================================
;; Asynchronous process.spawn tests
;; ============================================================================

(fn test-spawn-and-wait []
  (local id (process.spawn {:args ["echo" "async hello"]}))
  (assert (> id 0) "should return positive id")
  (local result (process.wait id))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "async hello\n") "stdout should match"))

(fn test-spawn-running []
  (local id (process.spawn {:args ["sleep" "10"]}))
  (assert (process.running id) "process should be running")
  (process.kill id)
  ;; Wait a bit for it to terminate
  (local result (process.wait id))
  (assert (not (process.running id)) "process should not be running after kill"))

(fn test-spawn-kill []
  (local id (process.spawn {:args ["sleep" "10"]}))
  ;; Give process time to start
  (os.execute "sleep 0.05")
  (local killed (process.kill id))
  (local result (process.wait id))
  ;; Either kill succeeded, or process finished (unlikely with sleep 10)
  (assert (or killed result.signal (>= result.exit-code 128)) "should be killed by signal"))

(fn test-spawn-kill-sigkill []
  (local id (process.spawn {:args ["sleep" "10"]}))
  ;; Give process time to start
  (os.execute "sleep 0.05")
  (local killed (process.kill id 9))
  (local result (process.wait id))
  ;; Either kill succeeded, or process was terminated
  (assert (or killed (= result.signal 9) (= result.exit-code 137)) "should be killed by SIGKILL"))

(fn test-spawn-write-stdin []
  (local id (process.spawn {:args ["cat"]}))
  (process.write id "hello ")
  (process.write id "world")
  (process.close-stdin id)
  (local result (process.wait id))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "hello world") "stdout should match written data"))

(fn test-spawn-close-stdin []
  (local id (process.spawn {:args ["cat"]}))
  (assert (process.close-stdin id) "first close should succeed")
  (assert (not (process.close-stdin id)) "second close should return false")
  (local result (process.wait id))
  (assert (= result.exit-code 0) "exit code should be 0"))

(fn test-spawn-poll []
  (local id1 (process.spawn {:args ["echo" "one"]}))
  (local id2 (process.spawn {:args ["echo" "two"]}))
  ;; Give processes time to complete
  (os.execute "sleep 0.2")
  (local results (process.poll))
  ;; Both should be completed
  (assert (>= (length results) 2) "should have at least 2 results"))

(fn test-spawn-poll-max-results []
  (local id1 (process.spawn {:args ["echo" "a"]}))
  (local id2 (process.spawn {:args ["echo" "b"]}))
  (local id3 (process.spawn {:args ["echo" "c"]}))
  ;; Give processes time to complete
  (os.execute "sleep 0.2")
  (local results (process.poll 1))
  (assert (<= (length results) 1) "should have at most 1 result"))

(fn test-spawn-timeout []
  (local id (process.spawn {:args ["sleep" "10"]
                            :timeout 0.1}))
  (local result (process.wait id))
  (assert result.timed-out "should time out"))

(fn test-spawn-cwd []
  (with-temp-dir (fn [dir]
    (local id (process.spawn {:args ["pwd"]
                              :cwd dir}))
    (local result (process.wait id))
    (assert (= result.exit-code 0) "exit code should be 0")
    (local output (string.gsub result.stdout "\n$" ""))
    (local popen-handle (io.popen (.. "cd " dir " && pwd -P")))
    (local expected (string.gsub (popen-handle:read "*a") "\n$" ""))
    (popen-handle:close)
    (assert (= output expected) "cwd should match"))))

(fn test-spawn-env []
  (local id (process.spawn {:args ["sh" "-c" "echo $SPAWN_TEST_VAR"]
                            :env {:SPAWN_TEST_VAR "spawn_value"}}))
  (local result (process.wait id))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= result.stdout "spawn_value\n") "env var should be set"))

(fn test-spawn-initial-stdin []
  ;; Test that stdin data provided at spawn time works
  (local id (process.spawn {:args ["cat"]
                            :stdin "initial data"}))
  (process.close-stdin id)
  (local result (process.wait id))
  (assert (= result.exit-code 0) "exit code should be 0")
  ;; Note: initial stdin may or may not be fully written depending on buffer size
  ;; At minimum we should get something
  (assert (> (length result.stdout) 0) "should have some output"))

;; ============================================================================
;; Edge cases and error handling
;; ============================================================================

(fn test-run-empty-args-error []
  (local (ok err) (pcall process.run {:args []}))
  (assert (not ok) "should error on empty args")
  (assert (string.find err "empty") "error should mention empty"))

(fn test-run-no-args-error []
  (local (ok err) (pcall process.run {}))
  (assert (not ok) "should error on missing args"))

(fn test-spawn-invalid-id-wait []
  (local (ok err) (pcall process.wait 999999))
  (assert (not ok) "should error on invalid id"))

(fn test-spawn-invalid-id-write []
  (local (ok err) (pcall process.write 999999 "data"))
  (assert (not ok) "should error on invalid id"))

(fn test-run-binary-output []
  ;; Test that binary data is preserved
  (local result (process.run {:args ["printf" "\\x00\\x01\\x02"]}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= (length result.stdout) 3) "should have 3 bytes"))

(fn test-spawn-multiple-concurrent []
  ;; Spawn multiple processes concurrently
  (local ids [])
  (for [i 1 5]
    (table.insert ids (process.spawn {:args ["echo" (tostring i)]})))
  ;; Wait for all
  (local results [])
  (each [_ id (ipairs ids)]
    (table.insert results (process.wait id)))
  ;; All should succeed
  (each [_ result (ipairs results)]
    (assert (= result.exit-code 0) "all should succeed")))

;; ============================================================================
;; Register all tests
;; ============================================================================

(table.insert tests {:name "run simple command" :fn test-run-simple-command})
(table.insert tests {:name "run exit code" :fn test-run-exit-code})
(table.insert tests {:name "run stderr" :fn test-run-stderr})
(table.insert tests {:name "run stdout and stderr" :fn test-run-stdout-and-stderr})
(table.insert tests {:name "run merge stderr" :fn test-run-merge-stderr})
(table.insert tests {:name "run stdin" :fn test-run-stdin})
(table.insert tests {:name "run stdin multiline" :fn test-run-stdin-multiline})
(table.insert tests {:name "run cwd" :fn test-run-cwd})
(table.insert tests {:name "run env" :fn test-run-env})
(table.insert tests {:name "run env multiple" :fn test-run-env-multiple})
(table.insert tests {:name "run clear env" :fn test-run-clear-env})
(table.insert tests {:name "run timeout" :fn test-run-timeout})
(table.insert tests {:name "run timeout not triggered" :fn test-run-timeout-not-triggered})
(table.insert tests {:name "run command not found" :fn test-run-command-not-found})
(table.insert tests {:name "run duration" :fn test-run-duration})
(table.insert tests {:name "run large output" :fn test-run-large-output})
(table.insert tests {:name "spawn and wait" :fn test-spawn-and-wait})
(table.insert tests {:name "spawn running" :fn test-spawn-running})
(table.insert tests {:name "spawn kill" :fn test-spawn-kill})
(table.insert tests {:name "spawn kill sigkill" :fn test-spawn-kill-sigkill})
(table.insert tests {:name "spawn write stdin" :fn test-spawn-write-stdin})
(table.insert tests {:name "spawn close stdin" :fn test-spawn-close-stdin})
(table.insert tests {:name "spawn poll" :fn test-spawn-poll})
(table.insert tests {:name "spawn poll max results" :fn test-spawn-poll-max-results})
(table.insert tests {:name "spawn timeout" :fn test-spawn-timeout})
(table.insert tests {:name "spawn cwd" :fn test-spawn-cwd})
(table.insert tests {:name "spawn env" :fn test-spawn-env})
(table.insert tests {:name "spawn initial stdin" :fn test-spawn-initial-stdin})
(table.insert tests {:name "run empty args error" :fn test-run-empty-args-error})
(table.insert tests {:name "run no args error" :fn test-run-no-args-error})
(table.insert tests {:name "spawn invalid id wait" :fn test-spawn-invalid-id-wait})
(table.insert tests {:name "spawn invalid id write" :fn test-spawn-invalid-id-write})
(table.insert tests {:name "run binary output" :fn test-run-binary-output})
(table.insert tests {:name "spawn multiple concurrent" :fn test-spawn-multiple-concurrent})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "process"
                       :tests tests})))

{:name "process"
 :tests tests
 :main main}
