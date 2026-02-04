(local FlamegraphProfiler (require :flamegraph-profiler))

(local fs (require :fs))
(local io io)
(local os os)
(local tests [])

(fn delete-file-if-exists [path]
  (when path
    (local handle (io.open path "r"))
    (when handle
      (handle:close)
      (local removal (table.pack (os.remove path)))
      (local ok (. removal 1))
      (local err (. removal 2))
      (when (not ok)
        (error (.. "Failed to delete " path ": " err))))))

(fn with-output-path [suffix run]
  (local path (.. "space-flamegraph-test-" suffix ".folded"))
  (delete-file-if-exists path)
  (local outcome (table.pack (pcall run path)))
  (delete-file-if-exists path)
  (local ok (. outcome 1))
  (local result (. outcome 2))
  (if ok
      result
      (error result)))

(fn busy-leaf []
  (var acc 0)
  (for [i 1 1000]
    (set acc (+ acc i)))
  acc)

(fn fan-out []
  (busy-leaf)
  (busy-leaf)
  (busy-leaf))

(fn call-c-function []
  (local arr [])
  (table.insert arr 42)
  arr)

(fn call-main-chunk []
  (local chunk
    (load "local acc = 0\nfor i = 1, 25000 do\n  acc = acc + i\nend\nreturn acc"
          "test-chunk"))
  (chunk))

(fn contains? [haystack needle]
  (not (= (string.find haystack needle 1 true) nil)))

(table.insert tests
  {:name "flamegraph profiler collapses stacks"
   :fn (fn []
         (var captured nil)
         (local profiler (FlamegraphProfiler {:writer (fn [rows] (set captured rows))
                                              :output-path nil}))
         (profiler.start)
         (fan-out)
         (profiler.stop)
         (local rows (profiler.flush))
         (assert (= captured rows) "writer should receive sorted rows")
         (assert (> (# rows) 0) "expected profiler rows")
         (var saw-source false)
         (var saw-stack false)
         (each [_ row (ipairs rows)]
           (when (contains? row.stack "test-flamegraph.fnl")
             (set saw-source true)
             (assert (>= row.samples 1) "leaf stack should record samples"))
           (when (and (contains? row.stack "test-flamegraph.fnl")
                      (contains? row.stack ";"))
             (set saw-stack true)))
         (assert saw-source "missing profiler entry for source file")
         (assert saw-stack "missing collapsed stack entry"))})

(table.insert tests
  {:name "flamegraph profiler records C and main frames"
   :fn (fn []
         (with-output-path "c-main-frames"
           (fn [path]
             (local profiler (FlamegraphProfiler {:output-path path}))
             (profiler.start)
             (call-c-function)
             (call-main-chunk)
             (profiler.stop)
             (local rows (profiler.flush))
             (assert (> (# rows) 0) "expected profiler rows")
             (var saw-c false)
             (var saw-main false)
             (each [_ row (ipairs rows)]
               (when (contains? row.stack "[C]")
                 (set saw-c true))
               (when (contains? row.stack "[string \"test-chunk\"]")
                 (set saw-main true)))
             (assert saw-c "expected collapsed C frame")
             (assert saw-main "expected collapsed main chunk"))))})

(table.insert tests
  {:name "flamegraph profiler can be restarted"
   :fn (fn []
         (with-output-path "restartable"
           (fn [path]
             (local profiler (FlamegraphProfiler {:output-path path}))
             (profiler.start)
             (busy-leaf)
             (profiler.stop)
             (local first (profiler.flush))
             (assert (> (# first) 0))
             (profiler.reset)
             (profiler.start)
             (busy-leaf)
             (profiler.stop)
             (local second (profiler.flush))
             (assert (> (# second) 0))
             (assert (> (# (profiler.rows)) 0) "rows should remain after flush"))))})

(table.insert tests
  {:name "default flamegraph output lives under prof"
   :fn (fn []
         (local prof-dir "prof")
         (local default-path (.. prof-dir "/space-fennel-flamegraph.folded"))
         (local fs-available? (and fs fs.exists))
         (local existing-dir? (and fs-available? (fs.exists prof-dir)))
         (delete-file-if-exists default-path)
         (local profiler (FlamegraphProfiler {}))
         (profiler.start)
         (busy-leaf)
         (profiler.stop)
         (profiler.flush)
         (local handle (io.open default-path "r"))
         (assert handle "expected default flamegraph output file")
         (handle:close)
         (when fs-available?
           (assert (fs.exists prof-dir) "prof directory should exist after default run")
           (when (not existing-dir?)
             (delete-file-if-exists default-path)
             (fs.remove-all prof-dir)))
         (when (or (not fs-available?) existing-dir?)
           (delete-file-if-exists default-path)))})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "flamegraph"
                       :tests tests})))

{:name "flamegraph"
 :tests tests
 :main main}
