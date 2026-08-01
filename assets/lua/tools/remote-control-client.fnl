(local zmq (require :zmq))

(local default-timeout-ms 2000)

(fn read-file [path]
  (local file (io.open path "rb"))
  (if file
      (do
        (local content (file:read "*a"))
        (file:close)
        content)
      (error (.. "Could not open file: " path))))

(fn parse-args [args]
  (var endpoint nil)
  (var code nil)
  (var file nil)
  (var timeout-ms default-timeout-ms)
  (var i 1)
  (while (<= i (# args))
    (local arg (. args i))
    (if (= arg "--endpoint")
        (do
          (set i (+ i 1))
          (set endpoint (. args i)))
        (if (or (= arg "-c") (= arg "--code"))
            (do
              (set i (+ i 1))
              (set code (. args i)))
            (if (or (= arg "-f") (= arg "--file"))
                (do
                  (set i (+ i 1))
                  (set file (. args i)))
                (if (= arg "--timeout-ms")
                    (do
                      (set i (+ i 1))
                      (set timeout-ms (tonumber (. args i))))
                    nil)
                nil)))
    (set i (+ i 1)))
  {:endpoint endpoint
   :code code
   :file file
   :timeout-ms timeout-ms})

(fn read-source [opts]
  (if opts.code
      opts.code
      (if opts.file
          (read-file opts.file)
          (io.read "*a"))))

(fn request-reply [socket poll-events source timeout-ms endpoint]
  (socket:send source)
  (local ready (zmq.poll [{:socket socket :events poll-events.IN}] timeout-ms))
  (local entry (. ready 1))
  (local revents (and entry entry.revents))
  (if (and revents (> revents 0))
      (do
        (local reply (socket:recv))
        (when reply
          (print (reply:to-string))))
      (error (.. "remote-control-client timed out after "
                 (tostring timeout-ms)
                  "ms waiting for reply from "
                  endpoint))))

(fn cleanup-zmq [socket ctx endpoint connected?]
  (when (and socket connected?)
    (socket:disconnect endpoint))
  (when socket
    (socket:close))
  (when ctx
    (ctx:close)))

(fn main []
  (local args (parse-args _G.arg))
  (assert (and args.endpoint (> (length args.endpoint) 0))
          "remote-control-client requires --endpoint")
  (local source (read-source args))
  (assert (and source (> (length source) 0))
          "remote-control-client requires code via -c, -f, or stdin")
  (local socket-types (. zmq :socket-types))
  (local poll-events (. zmq :poll-events))
  (local ctx (zmq.Context 1))
  (var socket nil)
  (var connected? false)
  (local (ok err)
    (pcall
      (fn []
        (set socket (ctx:socket socket-types.REQ))
        (socket:set-option-int "linger" 0)
        (socket:set-option-int "rcvtimeo" args.timeout-ms)
        (socket:set-option-int "sndtimeo" args.timeout-ms)
        (socket:connect args.endpoint)
        (set connected? true)
        (request-reply socket poll-events source args.timeout-ms args.endpoint))))
  (local (cleanup-ok cleanup-err)
    (pcall cleanup-zmq socket ctx args.endpoint connected?))
  (when (or (not ok) (not cleanup-ok))
    (io.stderr:write (tostring (if ok cleanup-err err)) "\n")
    (os.exit 1)))

{:main main}
