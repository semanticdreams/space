(local fs (require :fs))
(local appdirs (require :appdirs))

(assert appdirs "appdirs module is required for terrain issue logging")

(local log-dir
  (or (os.getenv "SPACE_LOG_DIR")
      (appdirs.user-log-dir "space")))
(local log-path (if (and fs fs.join-path)
                    (fs.join-path log-dir "terrain-issue.log")
                    (.. log-dir "/terrain-issue.log")))

(fn ensure-log-dir []
  (when (and fs fs.create-dirs)
    (pcall
      (fn []
        (local parent (and fs.parent (fs.parent log-path)))
        (fs.create-dirs (or parent log-dir))))))

(fn append-line [line]
  (ensure-log-dir)
  (pcall
    (fn []
      (local handle (io.open log-path "a"))
      (when handle
        (handle:write line "\n")
        (handle:close)))))

(fn write [level message]
  (append-line
    (string.format
      "ts=%s level=%s frame=%s msg=%s"
      (os.date "!%Y-%m-%dT%H:%M:%SZ")
      level
      (tostring (and app app.engine app.engine.frame-id))
      message)))

(fn start-session! [label]
  (write "session" (or label "terrain issue log session")))

{:log-path log-path
 :start-session! start-session!
 :info (fn [message] (write "info" message))
 :warn (fn [message] (write "warn" message))
 :error (fn [message] (write "error" message))}
