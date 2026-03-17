(local tests [])
(local process (require :process))
(local fs (require :fs))
(local sysinfo (require :sysinfo))

(local platform-os (. (sysinfo.platform) :os))
(local is-windows (= platform-os "windows"))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "process-test-tmp"))

(fn normalize-eol [s]
  (if s
      (string.gsub s "\r\n" "\n")
      ""))

(fn shell-args [script]
  (if is-windows
      ["cmd" "/d" "/s" "/c" script]
      ["sh" "-c" script]))

(fn stdin-echo-args []
  (if is-windows
      (shell-args "more")
      ["cat"]))

(fn short-delay []
  (if is-windows
      (os.execute "ping -n 2 127.0.0.1 > nul")
      (os.execute "sleep 0.05")))

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

(fn test-run-simple-command []
  (local result (process.run {:args (if is-windows
                                        (shell-args "echo hello world")
                                        ["echo" "hello world"])}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (local out (normalize-eol result.stdout))
  (assert (= out "hello world\n") "stdout should match")
  (assert (= result.stderr "") "stderr should be empty")
  (assert (not result.timed-out) "should not time out")
  (assert (= result.signal nil) "should have no signal"))

(fn test-run-exit-code []
  (local result (process.run {:args (if is-windows
                                        (shell-args "exit /b 42")
                                        (shell-args "exit 42"))}))
  (assert (= result.exit-code 42) "exit code should be 42"))

(fn test-run-stderr []
  (local result (process.run {:args (if is-windows
                                        (shell-args "echo error 1>&2 & exit /b 0")
                                        (shell-args "echo error >&2"))}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= (normalize-eol result.stdout) "") "stdout should be empty")
  (assert (string.find (normalize-eol result.stderr) "error") "stderr should include error"))

(fn test-run-stdout-and-stderr []
  (local result (process.run {:args (if is-windows
                                        (shell-args "echo out & echo err 1>&2")
                                        (shell-args "echo out; echo err >&2"))}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (string.find (normalize-eol result.stdout) "out") "stdout should contain out")
  (assert (string.find (normalize-eol result.stderr) "err") "stderr should contain err"))

(fn test-run-merge-stderr []
  (local result (process.run {:args (if is-windows
                                        (shell-args "echo out & echo err 1>&2")
                                        (shell-args "echo out; echo err >&2"))
                              :merge-stderr true}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (local out (normalize-eol result.stdout))
  (assert (string.find out "out") "stdout should contain out")
  (assert (string.find out "err") "stdout should contain err")
  (assert (= result.stderr "") "stderr should be empty when merged"))

(fn test-run-stdin []
  (local result (process.run {:args (stdin-echo-args)
                              :stdin "hello from stdin"}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (string.find (normalize-eol result.stdout) "hello from stdin") "stdout should contain stdin"))

(fn test-run-stdin-multiline []
  (local input "line1\nline2\nline3\n")
  (local result (process.run {:args (stdin-echo-args)
                              :stdin input}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (local out (normalize-eol result.stdout))
  (assert (string.find out "line1") "stdout should contain line1")
  (assert (string.find out "line2") "stdout should contain line2")
  (assert (string.find out "line3") "stdout should contain line3"))

(fn test-run-cwd []
  (with-temp-dir
    (fn [dir]
      (local result (process.run {:args (if is-windows
                                            (shell-args "cd")
                                            ["pwd"])
                                  :cwd dir}))
      (assert (= result.exit-code 0) "exit code should be 0")
      (local output (string.lower (normalize-eol result.stdout)))
      (local tail (string.lower (or (string.match dir "([^/]+)$") "")))
      (assert (string.find output tail 1 true)
              (.. "cwd output should contain temp dir tail " tail)))))

(fn test-run-env []
  (local result (process.run {:args (if is-windows
                                        (shell-args "echo %MY_TEST_VAR%")
                                        (shell-args "echo $MY_TEST_VAR"))
                              :env {:MY_TEST_VAR "test_value"}}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= (normalize-eol result.stdout) "test_value\n") "env var should be set"))

(fn test-run-env-multiple []
  (local result (process.run {:args (if is-windows
                                        (shell-args "echo %VAR1%-%VAR2%")
                                        (shell-args "echo $VAR1-$VAR2"))
                              :env {:VAR1 "foo" :VAR2 "bar"}}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= (normalize-eol result.stdout) "foo-bar\n") "multiple env vars should work"))

(fn test-run-clear-env []
  (local result (process.run {:args (if is-windows
                                        (shell-args "if defined HOME (echo set) else (echo empty)")
                                        ["/bin/sh" "-c" "echo ${HOME:-empty}"])
                              :clear-env true}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= (normalize-eol result.stdout) "empty\n") "HOME should be cleared"))

(fn test-run-timeout []
  (local result (process.run {:args (if is-windows
                                        (shell-args "ping -n 8 127.0.0.1 > nul")
                                        ["sleep" "10"])
                              :timeout 0.1}))
  (assert result.timed-out "should time out"))

(fn test-run-timeout-not-triggered []
  (local result (process.run {:args (if is-windows
                                        (shell-args "echo fast")
                                        ["echo" "fast"])
                              :timeout 5}))
  (assert (not result.timed-out) "should not time out")
  (assert (= result.exit-code 0) "exit code should be 0"))

(fn test-run-command-not-found []
  (local result (process.run {:args ["nonexistent_command_xyz"]}))
  (assert (= result.exit-code 127) "exit code should be 127 for command not found"))

(fn test-run-duration []
  (local result (process.run {:args (if is-windows
                                        (shell-args "ping -n 2 127.0.0.1 > nul")
                                        ["sleep" "0.1"])}))
  (assert (>= result.duration-ms 50) "duration should be at least 50ms")
  (assert (<= result.duration-ms (if is-windows 20000 5000)) "duration should be bounded"))

(fn test-run-large-output []
  (local result (process.run {:args (if is-windows
                                        (shell-args "for /L %i in (1,1,2000) do @echo %i")
                                        (shell-args "seq 1 2000"))}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (local lines (icollect [line (string.gmatch (normalize-eol result.stdout) "[^\n]+")] line))
  (assert (= (length lines) 2000) "should have expected line count"))

(fn test-spawn-and-wait []
  (local id (process.spawn {:args (if is-windows
                                     (shell-args "echo async hello")
                                     ["echo" "async hello"])}))
  (assert (> id 0) "should return positive id")
  (local result (process.wait id))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (= (normalize-eol result.stdout) "async hello\n") "stdout should match"))

(fn test-spawn-running-and-kill []
  (local id (process.spawn {:args (if is-windows
                                     (shell-args "ping -n 8 127.0.0.1 > nul")
                                     ["sleep" "10"])}))
  (assert (process.running id) "process should be running")
  (short-delay)
  (local killed (process.kill id))
  (local result (process.wait id))
  (assert killed "kill should report success")
  (assert (not (process.running id)) "process should not be running after wait")
  (assert (or result.timed-out (not (= result.exit-code 0))) "killed process should not exit cleanly"))

(fn test-spawn-write-and-close-stdin []
  (local id (process.spawn {:args (stdin-echo-args)}))
  (process.write id "hello ")
  (process.write id "world")
  (assert (process.close-stdin id) "first close should succeed")
  (assert (not (process.close-stdin id)) "second close should return false")
  (local result (process.wait id))
  (assert (= result.exit-code 0) "exit code should be 0")
  (assert (string.find (normalize-eol result.stdout) "hello world") "stdout should contain written data"))

(fn test-spawn-poll []
  (process.spawn {:args (if is-windows (shell-args "echo one") ["echo" "one"])})
  (process.spawn {:args (if is-windows (shell-args "echo two") ["echo" "two"])})
  (short-delay)
  (local results (process.poll))
  (assert (>= (length results) 2) "should have at least 2 completed results"))

(fn test-spawn-poll-max-results []
  (process.spawn {:args (if is-windows (shell-args "echo a") ["echo" "a"])})
  (process.spawn {:args (if is-windows (shell-args "echo b") ["echo" "b"])})
  (process.spawn {:args (if is-windows (shell-args "echo c") ["echo" "c"])})
  (short-delay)
  (local results (process.poll 1))
  (assert (<= (length results) 1) "should have at most 1 result"))

(fn test-spawn-timeout []
  (local id (process.spawn {:args (if is-windows
                                     (shell-args "ping -n 8 127.0.0.1 > nul")
                                     ["sleep" "10"])
                            :timeout 0.1}))
  (local result (process.wait id))
  (assert result.timed-out "should time out"))

(fn test-spawn-cwd-and-env []
  (with-temp-dir
    (fn [dir]
      (local cwd-id (process.spawn {:args (if is-windows (shell-args "cd") ["pwd"]) :cwd dir}))
      (local cwd-result (process.wait cwd-id))
      (assert (= cwd-result.exit-code 0) "cwd spawn should succeed")

      (local env-id (process.spawn {:args (if is-windows
                                            (shell-args "echo %SPAWN_TEST_VAR%")
                                            (shell-args "echo $SPAWN_TEST_VAR"))
                                    :env {:SPAWN_TEST_VAR "spawn_value"}}))
      (local env-result (process.wait env-id))
      (assert (= env-result.exit-code 0) "env spawn should succeed")
      (assert (= (normalize-eol env-result.stdout) "spawn_value\n") "spawn env var should be set"))))

(fn test-edge-cases []
  (local (ok-empty _err-empty) (pcall process.run {:args []}))
  (assert (not ok-empty) "should error on empty args")

  (local (ok-no-args _err-no-args) (pcall process.run {}))
  (assert (not ok-no-args) "should error on missing args")

  (local (ok-wait _err-wait) (pcall process.wait 999999))
  (assert (not ok-wait) "should error on invalid wait id")

  (local (ok-write _err-write) (pcall process.write 999999 "data"))
  (assert (not ok-write) "should error on invalid write id"))

(fn test-run-three-bytes-output []
  (local result (process.run {:args (if is-windows
                                        ["cmd" "/d" "/c" "<nul set /p=ABC&exit /b 0"]
                                        ["printf" "\\x00\\x01\\x02"])}))
  (assert (= result.exit-code 0) "exit code should be 0")
  (if is-windows
      (assert (= (length result.stdout) 3) "should have 3 bytes")
      (assert (= (length result.stdout) 3) "should have 3 bytes")))

(fn test-spawn-multiple-concurrent []
  (local ids [])
  (for [i 1 5]
    (table.insert ids (process.spawn {:args (if is-windows
                                                (shell-args (.. "echo " i))
                                                ["echo" (tostring i)])})))
  (each [_ id (ipairs ids)]
    (local result (process.wait id))
    (assert (= result.exit-code 0) "all concurrent processes should succeed")))

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
(table.insert tests {:name "spawn running and kill" :fn test-spawn-running-and-kill})
(table.insert tests {:name "spawn write and close stdin" :fn test-spawn-write-and-close-stdin})
(table.insert tests {:name "spawn poll" :fn test-spawn-poll})
(table.insert tests {:name "spawn poll max results" :fn test-spawn-poll-max-results})
(table.insert tests {:name "spawn timeout" :fn test-spawn-timeout})
(table.insert tests {:name "spawn cwd and env" :fn test-spawn-cwd-and-env})
(table.insert tests {:name "edge cases" :fn test-edge-cases})
(table.insert tests {:name "run three bytes output" :fn test-run-three-bytes-output})
(table.insert tests {:name "spawn multiple concurrent" :fn test-spawn-multiple-concurrent})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "process"
                       :tests tests})))

{:name "process"
 :tests tests
 :main main}
