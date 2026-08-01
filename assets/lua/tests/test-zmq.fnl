(local tests [])
(local zmq (require :zmq))
(local fs (require :fs))

(fn msg->string [msg]
  ((. msg :to-string) msg))

(fn cleanup-zmq [records ctx]
  (each [_ record (ipairs records)]
    (when (and record.socket record.endpoint)
      (record.socket:disconnect record.endpoint))
    (when record.socket
      (record.socket:close)))
  (when ctx
    (ctx:close)))

(fn rethrow-after-zmq-cleanup [ok result records ctx]
  (local (cleanup-ok cleanup-result) (pcall cleanup-zmq records ctx))
  (if (not ok)
      (error result)
      (not cleanup-ok)
      (error cleanup-result)))

(fn zmq-version []
  (local version (zmq.version))
  (assert (and version.major version.minor version.patch))
  true)

(fn req-rep-roundtrip []
  (local socket-types (. zmq :socket-types))
  (local ctx (zmq.Context 1))
  (local rep (ctx:socket socket-types.REP))
  (local req (ctx:socket socket-types.REQ))
  (local endpoint "inproc://req-rep")
  (rep:bind "inproc://req-rep")
  (req:connect endpoint)
  (local (ok result) (pcall (fn []
                              (req:send "ping")
                              (local msg (rep:recv))
                              (assert (= (msg->string msg) "ping"))
                              (rep:send "pong")
                              (local reply (req:recv))
                              (assert (= (msg->string reply) "pong")))))
  (rethrow-after-zmq-cleanup ok result [{:socket req :endpoint endpoint}
                                        {:socket rep}]
                             ctx)
  true)

(fn multipart-send-recv []
  (local socket-types (. zmq :socket-types))
  (local ctx (zmq.Context 1))
  (local sender (ctx:socket socket-types.PAIR))
  (local receiver (ctx:socket socket-types.PAIR))
  (local endpoint "inproc://multipart")
  (sender:bind "inproc://multipart")
  (receiver:connect endpoint)
  (local (ok result) (pcall (fn []
                              (sender:send ["alpha" "beta" "gamma"])
                              (local parts (receiver:recv-multipart))
                              (assert (= (length parts) 3))
                              (assert (= (msg->string (. parts 1)) "alpha"))
                              (assert (= (msg->string (. parts 2)) "beta"))
                              (assert (= (msg->string (. parts 3)) "gamma")))))
  (rethrow-after-zmq-cleanup ok result [{:socket receiver :endpoint endpoint}
                                        {:socket sender}]
                             ctx)
  true)

(fn nonblocking-and-poll []
  (local socket-types (. zmq :socket-types))
  (local recv-flags (. zmq :recv-flags))
  (local poll-events (. zmq :poll-events))
  (local ctx (zmq.Context 1))
  (local sender (ctx:socket socket-types.PAIR))
  (local receiver (ctx:socket socket-types.PAIR))
  (local endpoint "inproc://poll")
  (sender:bind "inproc://poll")
  (receiver:connect endpoint)
  (local (ok result) (pcall (fn []
                              (assert (= (receiver:recv recv-flags.DONTWAIT) nil))
                              (sender:send "ready")
                              (local polled (zmq.poll [{:socket receiver :events poll-events.IN}] 10))
                              (local revents (. (. polled 1) "revents"))
                              (assert (> revents 0))
                              (local msg (receiver:recv))
                              (assert (= (msg->string msg) "ready")))))
  (rethrow-after-zmq-cleanup ok result [{:socket receiver :endpoint endpoint}
                                        {:socket sender}]
                             ctx)
  true)

(fn socket-options []
  (local socket-types (. zmq :socket-types))
  (local ctx (zmq.Context 1))
  (local dealer (ctx:socket socket-types.DEALER))
  (dealer:set-option-int "linger" 0)
  (assert (= (dealer:get-option-int "linger") 0))
  (dealer:set-option-string "identity" "unit-test")
  (assert (= (dealer:get-option-string "identity") "unit-test"))
  (dealer:close)
  (ctx:close)
  true)

(fn ipc-req-rep-roundtrip []
  (local socket-types (. zmq :socket-types))
  (local ctx (zmq.Context 1))
  (local rep (ctx:socket socket-types.REP))
  (local req (ctx:socket socket-types.REQ))
  (local suffix (.. (os.time) "-" (math.floor (* (os.clock) 1000000))))
  (local path (fs.join-path "/tmp" (.. "space-zmq-" suffix ".sock")))
  (local endpoint (.. "ipc://" path))
  (when (fs.exists path)
    (fs.remove path))
  (local (ok err) (pcall (fn [] (rep:bind endpoint))))
  (when (not ok)
    (when (or (string.find err "Operation not permitted" 1 true)
              (string.find err "Permission denied" 1 true)
              (string.find err "Protocol not supported" 1 true))
      (print "Skipping ZMQ ipc req/rep test: ipc bind not permitted")
      (rep:close)
      (req:close)
      (ctx:close)
      (when (fs.exists path)
        (fs.remove path))
      (lua "return true"))
    (error err))
  (req:connect endpoint)
  (local (ok-roundtrip result) (pcall (fn []
                                        (req:send "hello")
                                        (local msg (rep:recv))
                                        (assert (= (msg->string msg) "hello"))
                                        (rep:send "world")
                                        (local reply (req:recv))
                                        (assert (= (msg->string reply) "world")))))
  (rethrow-after-zmq-cleanup ok-roundtrip result [{:socket req :endpoint endpoint}
                                                  {:socket rep}]
                             ctx)
  (when (fs.exists path)
    (fs.remove path))
  true)

(table.insert tests {:name "ZMQ version reports major/minor/patch" :fn zmq-version})
(table.insert tests {:name "ZMQ req/rep roundtrip" :fn req-rep-roundtrip})
(table.insert tests {:name "ZMQ multipart send/recv" :fn multipart-send-recv})
(table.insert tests {:name "ZMQ nonblocking recv and poll" :fn nonblocking-and-poll})
(table.insert tests {:name "ZMQ socket options roundtrip" :fn socket-options})
(table.insert tests {:name "ZMQ ipc req/rep roundtrip" :fn ipc-req-rep-roundtrip})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "zmq"
                       :tests tests})))

{:name "zmq"
 :tests tests
 :main main}
