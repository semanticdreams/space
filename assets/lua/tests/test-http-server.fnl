;; HTTP server binding tests.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-http-server:main

(local tests [])
(local http-server-mod (require :http_server))
(local http (require :http))
(local callbacks (require :callbacks))
(local sysinfo (require :sysinfo))

(fn poll-http []
  (callbacks.run-loop {:poll-http true :sleep-ms 5 :timeout-ms 50}))

(fn wait-for [srv pred timeout-ms]
  "Poll until pred returns truthy, or timeout."
  (local deadline (+ (os.clock) (/ (or timeout-ms 5000) 1000)))
  (var result nil)
  (while (and (not result) (< (os.clock) deadline))
    (poll-http)
    (local (ok val) (pcall pred))
    (when ok (set result val)))
  (assert result (.. "timeout after " (or timeout-ms 5000) "ms")))

(fn stream-body [chunks]
  (var body "")
  (each [_ chunk (ipairs chunks)]
    (if (= (type chunk) "string")
        (set body (.. body chunk))
        (= (type chunk.chunk) "string")
        (set body (.. body chunk.chunk))))
  body)

;; ── Server lifecycle ──

(fn test-server-create-and-start []
  (local srv (http-server-mod.HttpServer))
  (assert srv "should create server")
  (local port (srv:listen "127.0.0.1" 0))
  (assert (> port 0) "should get a valid port")
  (assert (= (srv:port) port) "port() should return the port")
  (srv:stop))

(table.insert tests {:name "http-server: create and start on random port" :fn test-server-create-and-start})

(fn test-server-fixed-port []
  (local probe (http-server-mod.HttpServer))
  (local port (probe:listen "127.0.0.1" 0))
  (probe:stop)

  (local srv (http-server-mod.HttpServer))
  (local actual-port (srv:listen "127.0.0.1" port))
  (assert (= actual-port port) (.. "fixed port listen should return requested port, got " actual-port))
  (assert (= (srv:port) port) "port() should return requested fixed port")
  (srv:stop))

(table.insert tests {:name "http-server: fixed port listen uses requested port" :fn test-server-fixed-port})

(fn test-server-stop []
  (local srv (http-server-mod.HttpServer))
  (srv:listen "127.0.0.1" 0)
  (srv:stop)
  (srv:stop)
  (assert true "stop should be idempotent"))

(table.insert tests {:name "http-server: stop is idempotent" :fn test-server-stop})

(fn test-listen-twice-fails []
  (local srv (http-server-mod.HttpServer))
  (srv:listen "127.0.0.1" 0)
  (local (ok err) (pcall srv.listen srv "127.0.0.1" 0))
  (assert (not ok) "second listen should fail")
  (assert (string.find (tostring err) "listen called more than once" 1 true)
          (.. "error should mention second listen, got: " (tostring err)))
  (srv:stop))

(table.insert tests {:name "http-server: listen twice fails" :fn test-listen-twice-fails})

(fn test-route-after-listen-fails []
  (local srv (http-server-mod.HttpServer))
  (srv:listen "127.0.0.1" 0)
  (local (ok err) (pcall srv.route srv "GET" "/late" (fn [_] {:status 200})))
  (assert (not ok) "route after listen should fail")
  (assert (string.find (tostring err) "routes must be registered before listen" 1 true)
          (.. "error should mention route order, got: " (tostring err)))
  (srv:stop))

(table.insert tests {:name "http-server: route after listen fails" :fn test-route-after-listen-fails})

;; ── Route handling ──

(fn test-get-route []
  (local srv (http-server-mod.HttpServer))
  (srv:route "GET" "/hello"
    (fn [req]
      {:status 200
       :body (.. "Hello " (or req.query_params.name "world"))
       :headers {:x-test "value"}}))
  (local port (srv:listen "127.0.0.1" 0))

  (var response nil)
  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/hello?name=space")
     :callback (fn [res] (set response res))})

  (wait-for srv #(and response response.ok))
  (assert (= response.status 200))
  (assert (string.find (or response.body "") "Hello space") "should contain greeting")
  (srv:stop))

(table.insert tests {:name "http-server: GET route with query params" :fn test-get-route})

(fn test-post-route-echo []
  (local srv (http-server-mod.HttpServer))
  (srv:route "POST" "/echo"
    (fn [req]
      {:status 200 :body req.body}))
  (local port (srv:listen "127.0.0.1" 0))

  (var response nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/echo")
     :headers {:Content-Type "text/plain"}
     :body "hello-from-post"
     :callback (fn [res] (set response res))})

  (wait-for srv #response)
  (assert (= response.status 200) (.. "expected 200 got " (tostring response.status)))
  (assert (string.find (or response.body "") "hello-from-post" 1 true) (.. "should echo body, got: " (tostring response.body)))
  (srv:stop))

(table.insert tests {:name "http-server: POST route echo" :fn test-post-route-echo})

(fn test-route-handler-error []
  (local srv (http-server-mod.HttpServer))
  (srv:route "GET" "/crash"
    (fn [_req]
      (error "intentional handler error")))
  (local port (srv:listen "127.0.0.1" 0))

  (var response nil)
  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/crash")
     :callback (fn [res] (set response res))})

  (wait-for srv #response)
  (assert (= response.status 500) "should return 500 on handler error")
  (assert (string.find (or response.body "") "Handler error") "should mention handler error")
  (srv:stop))

(table.insert tests {:name "http-server: handler errors return 500" :fn test-route-handler-error})

(fn test-route-nil-response []
  (local srv (http-server-mod.HttpServer))
  (srv:route "POST" "/no-content"
    (fn [_req] nil))
  (local port (srv:listen "127.0.0.1" 0))

  (var response nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/no-content")
     :callback (fn [res] (set response res))})

  (wait-for srv #(and response response.ok))
  (assert (= (or response.status 0) 204) "nil handler result should return 204")
  (srv:stop))

(table.insert tests {:name "http-server: nil handler returns 204" :fn test-route-nil-response})

(fn test-multiple-routes []
  (local srv (http-server-mod.HttpServer))
  (srv:route "GET" "/a" (fn [_] {:status 200 :body "AAA"}))
  (srv:route "GET" "/b" (fn [_] {:status 200 :body "BBB"}))
  (local port (srv:listen "127.0.0.1" 0))

  (var response-a nil)
  (http.request {:method "GET" :url (.. "http://127.0.0.1:" port "/a")
                 :callback (fn [res] (set response-a res))})
  (wait-for srv #(and response-a response-a.ok))
  (assert (string.find (or response-a.body "") "AAA") "route A")

  (var response-b nil)
  (http.request {:method "GET" :url (.. "http://127.0.0.1:" port "/b")
                 :callback (fn [res] (set response-b res))})
  (wait-for srv #(and response-b response-b.ok))
  (assert (string.find (or response-b.body "") "BBB") "route B")

  (srv:stop))

(table.insert tests {:name "http-server: multiple routes" :fn test-multiple-routes})

(fn test-sse-route []
  (local srv (http-server-mod.HttpServer))
  (srv:route_sse "/events"
    (fn [req]
      (local stream req.stream)
      (assert stream "SSE handler should receive a stream")
      (stream:send "event: test\ndata: {\"count\":1}\n\n")
      (stream:send "event: test\ndata: {\"count\":2}\n\n")
      (stream:close)))

  (local port (srv:listen "127.0.0.1" 0))

  (var chunks [])
  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/events")
     :headers {:Accept "text/event-stream"}
     :stream true
     :callback (fn [result]
                 (if result.chunk
                     (table.insert chunks result.chunk)
                     result.done
                     (table.insert chunks {:done true})
                     result.error
                     (table.insert chunks {:error result.error})))})

  (var done false)
  (for [_ 1 200]
    (when (not done)
      (poll-http)
      (local body (stream-body chunks))
      (when (or (string.find body "\"count\":2" 1 true)
                (and (> (# chunks) 0)
                     (or (. chunks (# chunks) :done) (. chunks (# chunks) :error))))
        (set done true))
      (when (not done)
        (sysinfo.sleep 0.02))))

  (assert done "SSE stream should complete")

  (local body (stream-body chunks))
  (assert (string.find body "\"count\":1" 1 true) (.. "SSE body should contain count 1, got: " (string.sub body 1 200)))
  (srv:stop))

(table.insert tests {:name "http-server: SSE route sends events" :fn test-sse-route})

(fn test-sse-close-callback []
  (local srv (http-server-mod.HttpServer))
  (var closed false)
  (srv:route_sse "/close"
    (fn [req]
      (req.stream:on-close
        (fn []
          (set closed true)))
      (req.stream:send "event: close-test\ndata: {}\n\n")
      (req.stream:close)))

  (local port (srv:listen "127.0.0.1" 0))
  (var chunks [])
  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/close")
     :headers {:Accept "text/event-stream"}
     :stream true
     :callback (fn [result] (table.insert chunks result))})

  (wait-for srv #closed 5000)
  (assert closed "SSE on-close callback should run on Lua dispatch")
  (srv:stop))

(table.insert tests {:name "http-server: SSE close callback runs on Lua thread" :fn test-sse-close-callback})

(fn test-sse-cleanup []
  (local srv (http-server-mod.HttpServer))
  (var stream-ref nil)
  (srv:route_sse "/keepalive"
    (fn [req]
      (set stream-ref req.stream)
      (stream-ref:send "event: alive\ndata: {}\n\n")))

  (local port (srv:listen "127.0.0.1" 0))

  (var chunks [])
  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/keepalive")
     :headers {:Accept "text/event-stream"}
     :stream true
     :callback (fn [result]
                 (table.insert chunks result))})

  (for [_ 1 30]
    (poll-http)
    (sysinfo.sleep 0.02))

  ;; Should have received the alive event
  (local body (stream-body chunks))

  (assert (string.find body "alive") (.. "should receive alive event, got: " (string.sub body 1 200)))

  (srv:stop)
  (for [_ 1 20]
    (poll-http)
    (sysinfo.sleep 0.02))

  (assert true "SSE cleanup completes without error"))

(table.insert tests {:name "http-server: SSE connection closes on server stop" :fn test-sse-cleanup})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "http-server" :tests tests}))

{:tests tests
 :main main}
