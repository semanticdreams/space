(local debug debug)
(local fs (require :fs))
(local io io)
(local math math)
(local os os)
(local string string)
(local table table)

(local default-output-directory "prof")
(local default-output-path (.. default-output-directory "/space-fennel-flamegraph.folded"))

(fn sanitize-source [src]
  (if (and src (> (string.len src) 0))
      (if (= (string.sub src 1 1) "@")
          (string.sub src 2)
          src)
      "?"))

(fn make-frame-label [info]
  (local src (sanitize-source (or info.short_src info.source)))
  (local lined (or info.linedefined 0))
  (if info.name
      (string.format "%s:%s:%d" src info.name lined)
      (string.format "%s:%d" src lined)))

(fn to-samples [seconds]
  (math.max 1 (math.floor (+ (* seconds 1000000.0) 0.5))))

(fn build-row [stack-label seconds]
  {:stack stack-label
   :seconds seconds
   :samples (to-samples seconds)})

(fn ensure-output-directory [path]
  (when (and path fs fs.parent fs.create-dirs)
    (local parent (fs.parent path))
    (when (and parent (> (string.len parent) 0))
      (local (ok err) (pcall (fn [] (fs.create-dirs parent))))
      (when (not ok)
        (error (.. "Failed to create directory for " path ": " err))))))

(fn make-writer [path]
  (when path
    (fn [rows]
      (ensure-output-directory path)
      (local handle (assert (io.open path "w") (.. "Unable to open flamegraph output " path)))
      (each [_ row (ipairs rows)]
        (handle:write (string.format "%s %d\n" row.stack row.samples)))
      (handle:close))))

(fn FlamegraphProfiler [opts]
  (local options (or opts {}))
  (local hook-mask (or options.hook_mask "cr"))
  (var stack [])
  (var collapsed {})
  (var active false)
  (var previous-hook nil)
  (var previous-mask nil)
  (var previous-count nil)
  (local output-path (or options.output-path default-output-path))
  (var writer (or options.writer (make-writer output-path)))

  (fn record-sample [frame]
    (when (and frame frame.path frame.start)
      (local elapsed (- (os.clock) frame.start))
      (when (> elapsed 0)
        (local current (or (rawget collapsed frame.path) 0.0))
        (rawset collapsed frame.path (+ current elapsed)))))

  (fn hook [event]
    (local info (debug.getinfo 2 "Sln"))
    (local captures-what (and info (or (= info.what "Lua")
                                       (= info.what "C")
                                       (= info.what "main"))))
    (when captures-what
      (local label (make-frame-label info))
      (local is-call (= event "call"))
      (local is-tail (= event "tail call"))
      (local is-return (= event "return"))
      (when (and is-tail (> (# stack) 0))
        (record-sample (table.remove stack)))
      (if (or is-call is-tail)
          (do
            (local parent (. stack (# stack)))
            (local path (if parent (.. parent.path ";" label) label))
            (table.insert stack {:label label :path path :start (os.clock)}))
          (when (and is-return (> (# stack) 0))
            (record-sample (table.remove stack))))))

  (fn start []
    (when (not active)
      (local hook-info (table.pack (debug.gethook)))
      (set previous-hook (. hook-info 1))
      (set previous-mask (. hook-info 2))
      (set previous-count (. hook-info 3))
      (debug.sethook hook hook-mask)
      (set active true)))

  (fn stop []
    (when active
      (debug.sethook previous-hook previous-mask previous-count)
      (set previous-hook nil)
      (set previous-mask nil)
      (set previous-count nil)
      (set active false)))

  (fn rows []
    (local entries [])
    (each [stack-label seconds (pairs collapsed)]
      (table.insert entries (build-row stack-label seconds)))
    (table.sort entries (fn [a b] (> a.seconds b.seconds)))
    entries)

  (fn flush []
    (local entries (rows))
    (when (and writer (> (# entries) 0))
      (writer entries))
    entries)

  (fn reset []
    (set stack [])
    (set collapsed {}))

  (fn stop-and-flush []
    (stop)
    (flush))

  {:start start
   :stop stop
   :flush flush
   :rows rows
   :reset reset
   :stop_and_flush stop-and-flush
   :set_output_path
   (fn [path]
     (set writer (make-writer path)))})

FlamegraphProfiler
