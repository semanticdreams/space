(local zmq (require :zmq))

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
                nil)))
    (set i (+ i 1)))
  {:endpoint endpoint
   :code code
   :file file})

(fn read-source [opts]
  (if opts.code
      opts.code
      (if opts.file
          (read-file opts.file)
          (io.read "*a"))))

(fn main []
  (local args (parse-args _G.arg))
  (assert (and args.endpoint (> (length args.endpoint) 0))
          "remote-control-client requires --endpoint")
  (local source (read-source args))
  (assert (and source (> (length source) 0))
          "remote-control-client requires code via -c, -f, or stdin")
  (local socket-types (. zmq :socket-types))
  (local ctx (zmq.Context 1))
  (local socket (ctx:socket socket-types.REQ))
  (socket:connect args.endpoint)
  (socket:send source)
  (local reply (socket:recv))
  (when reply
    (print (reply:to-string)))
  (socket:close)
  (ctx:close))

{:main main}
