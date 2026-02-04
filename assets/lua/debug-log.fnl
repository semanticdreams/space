(local fs (require :fs))
(local appdirs (require :appdirs))

(assert appdirs "appdirs module is required for debug logging")
(local log-dir (appdirs.user-log-dir "space"))
(local log-path (if (and app.engine fs.join-path)
                    (fs.join-path log-dir "debug.log")
                    (.. log-dir "/debug.log")))

(fn safe-string [value]
  (local packed (table.pack (pcall tostring value)))
  (local ok (. packed 1))
  (local result (. packed 2))
  (if ok result "<tostring failed>"))

(fn ensure-log-dir []
(when (and fs fs.create-dirs)
    (pcall (fn []
             (local parent (and fs.parent (fs.parent log-path)))
             (fs.create-dirs (or parent log-dir))))))

(fn reset-log! []
  (ensure-log-dir)
  (pcall (fn []
           (local handle (io.open log-path "w"))
           (when handle
             (handle:write (string.format "[debug-log] reset %s\n" (os.date "%c")))
             (handle:close)))))

(fn append-lines [lines]
  (ensure-log-dir)
  (pcall (fn []
           (local handle (io.open log-path "a"))
           (when handle
             (each [_ line (ipairs lines)]
               (handle:write line "\n"))
             (handle:close)))))

(fn log-lines [label lines]
  (local clock (os.clock))
  (local header (string.format "[%s][%.4f]" label clock))
  (local all-lines [header])
  (each [_ line (ipairs lines)]
    (table.insert all-lines line))
  (append-lines all-lines))

(fn log-next-error [message tbl key traceback]
  (local lines
    [(string.format "error=%s" message)
     (string.format "table-type=%s" (type tbl))
     (string.format "table=%s" (safe-string tbl))
     (string.format "key-type=%s" (type key))
     (string.format "key=%s" (safe-string key))
     (string.format "frame-id=%s" (and app.engine app.engine.frame-id))
     (string.format "traceback=%s" traceback)])
  (log-lines "next-error" lines))

(fn log [label message]
  (append-lines [(string.format "[%s][%.4f] %s" label (os.clock) message)]))

{:log-next-error log-next-error
 :reset-log! reset-log!
 :log-path log-path
 :log log}
