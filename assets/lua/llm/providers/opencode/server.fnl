(local Process (require :process))
(local sysinfo (require :sysinfo))
(local callbacks (require :callbacks))
(local logging (require :logging))

(local default-hostname "127.0.0.1")
(local default-port 0)
(local default-timeout-ms 10000)

(fn now-ms []
  (sysinfo.now-ms))

(fn Server [opts]
  (local options (or opts {}))
  (local process (or options.process Process))
  (assert process "opencode server requires the process module")

  (local hostname (or options.hostname default-hostname))
  (local port (or options.port default-port))
  (local timeout-ms (or options.timeout-ms default-timeout-ms))
  (local stop-timeout-ms (or options.stop-timeout-ms 2000))
  (local opencode-path (or options.opencode-path "opencode"))

  (fn build-env []
    (local env {})
    (each [k v (pairs (or options.env {}))]
      (tset env k v))
    env)

  (fn build-args []
    (local args [opencode-path "serve" (.. "--hostname=" hostname) (.. "--port=" (tostring port))])
    args)

  (var process-id nil)
  (var server-url nil)
  (var closed false)

  (fn read-url-from-stdout []
    (local started (now-ms))
    (var line-buffer "")
    (while (and (not server-url) (< (- (now-ms) started) timeout-ms))
      (local output (process.read process-id))
      (when (and output output.stdout (> (# output.stdout) 0))
        (set line-buffer (.. line-buffer output.stdout))
        (while (string.find line-buffer "\n")
          (local nl (string.find line-buffer "\n"))
          (local line (string.sub line-buffer 1 (- nl 1)))
          (set line-buffer (string.sub line-buffer (+ nl 1)))
          (local idx (string.find line "listening on "))
          (when idx
            (set server-url (string.gsub (string.sub line (+ idx 13)) "%s+$" ""))
            (logging.info "[opencode] server listening on " server-url))))
      (when output.finished
        (local detail (if (> (# (or output.stderr "")) 0) output.stderr output.stdout))
        (error (.. "opencode server exited early: " (or detail ""))))
      (process.poll 0)
      (callbacks.run-loop {:poll-http true :poll-process false :sleep-ms 0 :timeout-ms 1})
      (sysinfo.sleep 0.05))
    (when (not server-url)
      (error (.. "opencode server did not start within " timeout-ms "ms"))))

  (fn start []
    (when process-id
      (error "opencode server already started"))
    (when closed
      (error "opencode server has been closed"))
    (set process-id
      (process.spawn {:args (build-args)
                      :cwd options.cwd
                      :env (build-env)
                      :clear-env (if (= options.clear-env nil) false options.clear-env)}))
    (read-url-from-stdout)
    true)

  (fn get-url []
    server-url)

  (fn get-process-id []
    process-id)

  (fn stop []
    (when process-id
      (when (process.running process-id)
        (process.kill process-id)
        (local deadline (+ (now-ms) stop-timeout-ms))
        (var finished false)
        (while (and (not finished) (< (now-ms) deadline))
          (local (ok output) (pcall process.read process-id))
          (if (not ok)
              (set finished true)
              (and output output.finished)
              (set finished true)
              (do
                (process.poll 0)
                (sysinfo.sleep 0.05))))
        (when (not finished)
          (process.kill process-id 9))
        (process.wait process-id))
      (set process-id nil)
      (set server-url nil))
    (set closed true))

  {:start start
   :stop stop
   :url get-url
   :hostname (fn [] hostname)
   :port (fn [] port)
   :process-id get-process-id})

Server
