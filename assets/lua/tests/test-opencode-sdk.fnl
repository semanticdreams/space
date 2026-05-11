(local OpencodeSdk (require :llm/providers/opencode))
(local Session (require :llm/providers/opencode/session))
(local Config (require :llm/providers/opencode/config))
(local Project (require :llm/providers/opencode/project))
(local File (require :llm/providers/opencode/file))
(local Find (require :llm/providers/opencode/find))
(local Global (require :llm/providers/opencode/global))
(local Sse (require :llm/providers/opencode/sse))
(local Client (require :llm/providers/opencode/client))
(local fixtures (require :tests/http-fixtures))
(local json (require :json))

(var fixture nil)

(fn get-fixture []
  (when (not fixture)
    (local fixture-path (app.engine.get-asset-path "lua/tests/data/opencode-fixture.json"))
    (set fixture (fixtures.read-json fixture-path)))
  fixture)

(fn with-client [cb]
  (local install (fixtures.install-mock (get-fixture)))
  (let [(ok result) (pcall #(cb install.mock.binding))]
    (install.restore)
    (if ok result (error result))))

(fn test-client-creation []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (assert client "client should be created")
      (assert client.submit "client should have submit")
      (assert client.base-url "client should have base-url"))))

(fn test-opencode-client-factory []
  (with-client
    (fn [mock-http]
      (local oc (OpencodeSdk.OpencodeClient {:base-url "http://127.0.0.1:4096"
                                              :http mock-http}))
      (assert oc.client "should have client")
      (assert oc.session "should have session")
      (assert oc.events "should have events")
      (assert oc.config "should have config")
      (assert oc.project "should have project")
      (assert oc.file "should have file")
      (assert oc.find "should have find")
      (assert oc.global "should have global"))))

(fn test-global-health []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local g (Global client))
      (var result nil)
      (g.health (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "health should be ok")
      (assert (= result.data.healthy true) "healthy should be true")
      (assert (= result.data.version "1.0.0-test") "version should match"))))

(fn test-session-list []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.list (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "list should be ok")
      (assert (= (# result.data) 2) "should have 2 sessions")
      (assert (= (. result.data 1 :id) "ses-1") "first session id"))))

(fn test-session-get []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.get "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "get should be ok")
      (assert (= result.data.id "ses-1") "session id match")
      (assert (= result.data.agent "primary") "agent match"))))

(fn test-session-create []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.create {:title "New session"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "create should be ok")
      (assert (= result.data.id "ses-new") "new session id"))))

(fn test-session-delete []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.delete "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "delete should be ok"))))

(fn test-session-update []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.update "ses-1" {:title "Updated title"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "update should be ok")
      (assert (= result.data.title "Updated title") "title updated"))))

(fn test-session-prompt []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.prompt "ses-1"
                {:model {:providerID "anthropic" :modelID "claude-3-5-sonnet-20241022"}
                 :parts [{:type "text" :text "Hello"}]}
                (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "prompt should be ok")
      (assert (= result.data.info.role "assistant") "response role")
      (assert (= (# result.data.parts) 1) "should have 1 part")
      (assert (= (. result.data.parts 1 :text) "Hello! How can I help?") "response text"))))

(fn test-session-abort []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.abort "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "abort should be ok"))))

(fn test-session-shell []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.shell "ses-1" {:command "echo test"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "shell should be ok")
      (assert (= (. result.data.parts 1 :text) "$ echo test")))))

(fn test-session-command []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.command "ses-1" {:command "tool"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "command should be ok")
      (assert (= (. result.data.parts 1 :text) "Command executed")))))

(fn test-session-messages []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.messages "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "messages should be ok")
      (assert (= (# result.data) 1) "should have 1 message")
      (assert (= (. result.data 1 :info :role) "user")))))

(fn test-session-children []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.children "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "children should be ok")
      (assert (= (# result.data) 1) "should have 1 child"))))

(fn test-session-summarize []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.summarize "ses-1" {} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "summarize should be ok"))))

(fn test-session-init []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.init "ses-1" {} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "init should be ok"))))

(fn test-session-share []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.share "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "share should be ok"))))

(fn test-session-unshare []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.unshare "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "unshare should be ok"))))

(fn test-session-revert []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.revert "ses-1" {:messageId "msg-1"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "revert should be ok"))))

(fn test-session-unrevert []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.unrevert "ses-1" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "unrevert should be ok"))))

(fn test-session-permissions []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.permissions "ses-1" "perm-1" {:action "allow"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "permissions should be ok"))))

(fn test-session-requires-callback []
  (let [client (Client {:base-url "http://127.0.0.1:4096"
                                :http {:request (fn [opts] (opts.callback {:ok true :status 200 :body "{}" :headers [] :id 1}))}})
        s (Session client)]
    (let [(ok err) (pcall #(s.list 42))]
      (assert (not ok) "should error when on_response is not a function")
      (assert err "should produce an error"))))

(fn test-config-get []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local c (Config client))
      (var result nil)
      (c.get (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "config get should be ok")
      (assert (= result.data.theme "dark") "theme should be dark"))))

(fn test-config-update []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local c (Config client))
      (var result nil)
      (c.update {:theme "light"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "config update should be ok")
      (assert (= result.data.theme "light") "theme should be light"))))

(fn test-config-providers []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local c (Config client))
      (var result nil)
      (c.providers (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "providers should be ok")
      (assert (= (# result.data.providers) 2) "should have 2 providers"))))

(fn test-project-list []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local p (Project client))
      (var result nil)
      (p.list (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "project list should be ok")
      (assert (= (# result.data) 1) "should have 1 project"))))

(fn test-project-current []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local p (Project client))
      (var result nil)
      (p.current (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "project current should be ok")
      (assert (= result.data.id "proj-1") "project id match"))))

(fn test-file-read []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local f (File client))
      (var result nil)
      (f.read "README.md" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "file read should be ok")
      (assert (= result.data.type "raw") "type should be raw")
      (assert (string.find result.data.content "Hello") "content should contain Hello"))))

(fn test-file-status []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local f (File client))
      (var result nil)
      (f.status nil (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "file status should be ok")
      (assert (= (# result.data) 1) "should have 1 file")
      (assert (= (. result.data 1 :status) "M") "status should be M"))))

(fn test-find-text []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local f (Find client))
      (var result nil)
      (f.text "hello" (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "find text should be ok")
      (assert (= (# result.data) 1) "should have 1 match")
      (assert (= (. result.data 1 :path) "src/main.cpp")))))

(fn test-find-files []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local f (Find client))
      (var result nil)
      (f.files {:query "*.fnl"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "find files should be ok")
      (assert (= (# result.data) 2) "should have 2 files"))))

(fn test-find-symbols []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local f (Find client))
      (var result nil)
      (f.symbols {:query "main"} (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "find symbols should be ok")
      (assert (= (# result.data) 1) "should have 1 symbol")
      (assert (= (. result.data 1 :name) "main")))))

(fn test-sse-parser []
  (local http-binding
    {:request (fn [opts] (tset opts :request-id 99) 99)
     :cancel (fn [id] true)})
  (local sse-handle (Sse http-binding "http://localhost/event" {}
                        (fn [event] nil)))
  (assert sse-handle "SSE connect should return a handle")
  (assert sse-handle.close "handle should have close method")
  (assert (= (sse-handle.request-id) 99) "should track request id"))

(fn test-sse-event-parsing []
  (var stream-callback nil)
  (local http-binding
    {:request (fn [opts]
                (set stream-callback opts.callback)
                1)
     :cancel (fn [id] true)})
  (var events [])
  (local handle (Sse http-binding "http://localhost/event" {}
                    (fn [event] (table.insert events event))))
  (assert handle "should create handle")
  (assert stream-callback "should capture stream callback")

  ;; Feed SSE chunks and verify parsed events
  (local simple-event (.. "event: message\n" "data: {\"key\":\"val\"}\n" "\n"))
  (stream-callback {:chunk simple-event})
  (assert (= (# events) 1) "should have parsed one event")
  (assert (= (. events 1 :event) "message") "event type should be message")
  (assert (string.find (. events 1 :data) "key") "data should contain key")
  (assert (string.find (. events 1 :data) "val") "data should contain val")

  ;; Feed fragmented chunks across buffer boundaries
  (stream-callback {:chunk (.. "event: update\n" "da")})
  (stream-callback {:chunk (.. "ta: {\"x\":1}\n" "\n")})
  (assert (= (# events) 2) "should have parsed fragmented event")
  (assert (string.find (. events 2 :data) "x") "fragmented event data should have x")

  ;; Error in stream should emit error event
  (stream-callback {:error "connection lost"})
  (assert (= (# events) 3) "error should produce an event")
  (assert (= (. events 3 :event) "error") "error event type"))

(fn test-client-stream-submit []
  (local http-binding
    {:request (fn [opts] (assert opts.callback "stream requires callback") 1)
     :cancel (fn [id] true)})
  (local client (Client {:base-url "http://localhost:4096" :http http-binding}))
  (let [(ok err) (pcall #(client.submit-stream "/event" {} (fn [_] nil)))]
    (assert ok "stream submit should succeed with callback")))

(fn test-client-requires-callback []
  (local http-binding
    {:request (fn [opts] (opts.callback {:ok true :status 200 :body "{}" :headers [] :id 1}) 1)
     :cancel (fn [id] true)})
  (local client (Client {:base-url "http://localhost:4096" :http http-binding}))
  (let [(ok err) (pcall #(client.submit "GET" "/test" {:on_response 42}))]
    (assert (not ok) "should error when on_response is not a function")
    (assert err "should produce an error")))

(fn test-file-read-requires-path []
  (let [client (Client {:base-url "http://127.0.0.1:4096"
                        :http {:request (fn [] 1)}})
        f (File client)]
    (let [(ok err) (pcall #(f.read nil (fn [])))]
      (assert (not ok) "should error without path")
      (assert err "should produce an error"))))

(fn test-events-subscribe-json-parse []
  ;; Test that Events.subscribe properly JSON-parses data and sets _event_type
  (local Events (require :llm/providers/opencode/events))
  (var sse-stream-cb nil)
  (var subscribe-events [])
  (local mock-client
    {:base-url (fn [] "http://localhost")
     :http-binding (fn []
       {:request (fn [opts]
                   (set sse-stream-cb opts.callback)
                   1)
        :cancel (fn [id] true)})})
  (local ev (Events mock-client))
  (local handle (ev.subscribe
                  (fn [event]
                    (table.insert subscribe-events event))))
  (assert handle "subscribe should return handle")
  (assert sse-stream-cb "should capture SSE stream callback")

  ;; Valid JSON data event
  (sse-stream-cb {:chunk (.. "event: message\n" "data: {\"key\":\"val\"}\n" "\n")})
  (assert (= (# subscribe-events) 1) "should have one event")
  (assert (= (. subscribe-events 1 :_event_type) "message") "should set _event_type from event field")
  (assert (= (. subscribe-events 1 :key) "val") "should parse JSON data")

  ;; Error event should pass through without JSON parsing
  (sse-stream-cb {:error "connection lost"})
  (assert (= (# subscribe-events) 2) "error should produce an event")
  (assert (= (. subscribe-events 2 :_event_type) "error") "error events should have _event_type error")
  (assert (= (. subscribe-events 2 :error) "connection lost") "error data should be raw string")

  ;; Malformed JSON in data event should be silently dropped
  (sse-stream-cb {:chunk (.. "event: update\n" "data: not-valid-json\n" "\n")})
  (assert (= (# subscribe-events) 2) "malformed JSON should not produce an event")

  (handle.unsubscribe))

(fn test-no-reply-prompt []
  (with-client
    (fn [mock-http]
      (local client (Client {:base-url "http://127.0.0.1:4096"
                                     :http mock-http}))
      (local s (Session client))
      (var result nil)
      (s.prompt "ses-1"
                {:noReply true
                 :parts [{:type "text" :text "context"}]}
                (fn [r] (set result r)))
      (mock-http.poll 1)
      (assert result.ok "noReply prompt should be ok")
      (assert result.data "noReply prompt should return data")
      (assert result.data.info "noReply prompt should have info")
      (assert result.data.parts "noReply prompt should have parts"))))

(local tests
  [{:name "client creation" :fn test-client-creation}
   {:name "opencode client factory" :fn test-opencode-client-factory}
   {:name "global health" :fn test-global-health}
   {:name "session list" :fn test-session-list}
   {:name "session get" :fn test-session-get}
   {:name "session create" :fn test-session-create}
   {:name "session delete" :fn test-session-delete}
   {:name "session update" :fn test-session-update}
   {:name "session prompt" :fn test-session-prompt}
   {:name "session abort" :fn test-session-abort}
   {:name "session shell" :fn test-session-shell}
   {:name "session command" :fn test-session-command}
   {:name "session messages" :fn test-session-messages}
   {:name "session children" :fn test-session-children}
   {:name "session summarize" :fn test-session-summarize}
   {:name "session init" :fn test-session-init}
   {:name "session share" :fn test-session-share}
   {:name "session unshare" :fn test-session-unshare}
   {:name "session revert" :fn test-session-revert}
   {:name "session unrevert" :fn test-session-unrevert}
   {:name "session permissions" :fn test-session-permissions}
   {:name "session requires callback" :fn test-session-requires-callback}
   {:name "config get" :fn test-config-get}
   {:name "config update" :fn test-config-update}
   {:name "config providers" :fn test-config-providers}
   {:name "project list" :fn test-project-list}
   {:name "project current" :fn test-project-current}
   {:name "file read" :fn test-file-read}
   {:name "file status" :fn test-file-status}
   {:name "find text" :fn test-find-text}
   {:name "find files" :fn test-find-files}
   {:name "find symbols" :fn test-find-symbols}
   {:name "sse parser" :fn test-sse-parser}
   {:name "sse event parsing" :fn test-sse-event-parsing}
   {:name "client requires callback" :fn test-client-requires-callback}
   {:name "client stream submit" :fn test-client-stream-submit}
   {:name "file read requires path" :fn test-file-read-requires-path}
   {:name "events subscribe json parse" :fn test-events-subscribe-json-parse}
   {:name "no-reply prompt" :fn test-no-reply-prompt}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "opencode-sdk"
                       :tests tests})))

{:name "opencode-sdk"
 :tests tests
 :main main}
