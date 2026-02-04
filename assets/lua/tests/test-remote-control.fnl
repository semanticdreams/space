(local tests [])
(local fs (require :fs))
(local zmq (require :zmq))
(local RemoteControl (require :remote-control))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "remote-control"))

(fn next-path []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "rc-" (os.time) "-" temp-counter ".sock")))

(fn with-endpoint [f]
  (when (not (fs.exists temp-root))
    (fs.create-dirs temp-root))
  (local path (next-path))
  (when (fs.exists path)
    (fs.remove path))
  (local endpoint (.. "ipc://" path))
  (local (ok result) (pcall f endpoint path))
  (when (fs.exists path)
    (fs.remove path))
  (if ok
      result
      (error result)))

(fn read-reply [client rc tries]
  (local recv-flags (. zmq :recv-flags))
  (var reply nil)
  (var count 0)
  (while (and (not reply) (< count tries))
    (rc:tick)
    (set reply (client:recv recv-flags.DONTWAIT))
    (set count (+ count 1)))
  reply)

(fn remote-control-ok []
  (with-endpoint
    (fn [endpoint _path]
      (local socket-types (. zmq :socket-types))
      (local (ok rc-or-error) (pcall (fn [] (RemoteControl {:endpoint endpoint}))))
      (when (not ok)
        (when (or (string.find rc-or-error "Operation not permitted" 1 true)
                  (string.find rc-or-error "Permission denied" 1 true))
          (print "Skipping remote control test: ipc bind not permitted")
          (lua "return true"))
        (error rc-or-error))
      (local rc rc-or-error)
      (local ctx (zmq.Context 1))
      (local client (ctx:socket socket-types.REQ))
      (client:connect endpoint)
      (client:send "(+ 1 2)")
      (local reply (read-reply client rc 200))
      (assert reply "expected reply")
      (assert (= (reply:to-string) "ok 3"))
      (client:close)
      (ctx:close)
      (rc:drop))))

(fn remote-control-error []
  (with-endpoint
    (fn [endpoint _path]
      (local socket-types (. zmq :socket-types))
      (local (ok rc-or-error) (pcall (fn [] (RemoteControl {:endpoint endpoint}))))
      (when (not ok)
        (when (or (string.find rc-or-error "Operation not permitted" 1 true)
                  (string.find rc-or-error "Permission denied" 1 true))
          (print "Skipping remote control test: ipc bind not permitted")
          (lua "return true"))
        (error rc-or-error))
      (local rc rc-or-error)
      (local ctx (zmq.Context 1))
      (local client (ctx:socket socket-types.REQ))
      (client:connect endpoint)
      (client:send "(error \"boom\")")
      (local reply (read-reply client rc 200))
      (assert reply "expected reply")
      (local reply-text (reply:to-string))
      (assert (= (string.sub reply-text 1 6) "error "))
      (client:close)
      (ctx:close)
      (rc:drop))))

(table.insert tests {:name "remote control executes code" :fn remote-control-ok})
(table.insert tests {:name "remote control reports errors" :fn remote-control-error})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "remote-control"
                       :tests tests})))

{:name "remote-control"
 :tests tests
 :main main}
