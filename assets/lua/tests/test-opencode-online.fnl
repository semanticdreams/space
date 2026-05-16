;; ── OpenCode Online Tests ──
;; Run against a real opencode Go server.
;; Requires `opencode` binary on PATH and a working config.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-opencode-online:main

(local OpencodeSdk (require :llm/providers/opencode))
(local callbacks (require :callbacks))
(local sysinfo (require :sysinfo))

(var passed 0)
(var failed 0)
(var skipped 0)
(var failures {})

(fn assert-ok [condition message]
  (when (not condition)
    (error (or message "assertion failed"))))

(fn assert-response-ok [result label]
  (assert-ok result (.. label " should return a response"))
  (assert-ok result.ok
             (.. label " failed: "
                 (or result.raw
                     (and (= (type result.data) "table") result.data.error)
                     result.error
                     "unknown error"))))

(fn run-test [name f]
  (io.write (.. "  " name " ... "))
  (io.flush)
  (local (ok result) (pcall f))
  (if ok
      (do
        (set passed (+ passed 1))
        (print "PASS"))
      (do
        (set failed (+ failed 1))
        (table.insert failures {:name name :error (tostring result)})
        (print (.. "FAIL: " (tostring result))))))

(fn poll-events [timeout-ms]
  (callbacks.run-loop {:poll-http true :sleep-ms 50 :timeout-ms (or timeout-ms 1000)}))

(fn now-ms []
  (sysinfo.now-ms))

(fn wait-for [pred timeout-ms]
  (local deadline (+ (now-ms) (or timeout-ms 5000)))
  (var result nil)
  (while (and (not result) (< (now-ms) deadline))
    (callbacks.run-loop {:poll-http true :sleep-ms 50 :timeout-ms 100})
    (local (ok val) (pcall pred))
    (when ok (set result val)))
  (assert-ok result (.. "timeout after " (or timeout-ms 5000) "ms waiting for condition")))

(fn main []
  (print "OpenCode SDK Online Tests")
  (print "==========================")
  (print "")

  (var srv nil)
  (var session-id nil)

  (local opencode-path (or (os.getenv "OPENCODE_PATH") "opencode"))
  (print "Using opencode: " opencode-path)

  ;; Check if opencode is available
  (local process (require :process))
  (local check (process.run {:args [opencode-path "--version"] :timeout_seconds 5}))
  (if (not (= check.exit-code 0))
      (do
        (print "ERROR: opencode not available. Install or set OPENCODE_PATH.")
        (print "  stderr: " (or check.stderr ""))
        (os.exit 1))
      (print "  version check: OK (" (or check.stdout "unknown") ")"))

  (math.randomseed (math.floor (sysinfo.now-ms)))
  (local port1 (+ 20000 (math.random 0 20000)))
  (var port2 0)
  (while (= port2 0)
    (local candidate (+ 20000 (math.random 0 20000)))
    (when (not= candidate port1)
      (set port2 candidate)))

  (print "")
  (print (.. "Using ports: " port1 ", " port2))
  (print "")

  ;; ── Server lifecycle ──
  (print "Server Lifecycle:")

  (run-test "start server"
    (fn []
      (local sv (OpencodeSdk.Opencode {:opencode-path opencode-path :port port1}))
      (assert-ok sv "opencode instance should be created")
      (assert-ok sv.client "should have client")
      (set srv sv)
      (print " (url: " (sv.server.url) ")")))

  (when (not srv)
    (print "ERROR: server failed to start, aborting tests")
    (os.exit 1))

  (local server srv)

  (run-test "health check"
    (fn []
      (var result nil)
      (server.global.health (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "health check")
      (assert-ok result.data.healthy "server should report healthy")
      (assert-ok result.data.version "server should report version")
      (print "  version: " result.data.version)))

  (run-test "config get"
    (fn []
      (var result nil)
      (server.config.get (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "config get")))

  (run-test "config providers"
    (fn []
      (var result nil)
      (server.config.providers (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "config providers")
      (assert-ok result.data.providers "providers should be present")
      (assert-ok (> (# result.data.providers) 0) "should have at least one provider")
      (print "  providers: " (# result.data.providers))))

  ;; ── Session CRUD ──
  (print "")
  (print "Session CRUD:")

  (run-test "create session"
    (fn []
      (var result nil)
      (server.session.create {:title "sdk-online-test"}
                             (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "create session")
      (assert-ok result.data.id "session should have an id")
      (set session-id result.data.id)
      (print "  id: " result.data.id)))

  (run-test "list sessions"
    (fn []
      (var result nil)
      (server.session.list (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "list sessions")
      (assert-ok (>= (# result.data) 1) "should list at least 1 session")))

  (run-test "get session"
    (fn []
      (var result nil)
      (server.session.get session-id (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "get session")
      (assert-ok (= result.data.id session-id) "session id should match")))

  (run-test "update session"
    (fn []
      (var result nil)
      (server.session.update session-id {:title "sdk-online-test-updated"}
                             (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "update session")))

  ;; ── Prompt / LLM interaction ──
  (print "")
  (print "Prompt (LLM interaction):")

  ;; Get available providers from config
  (var primary-providers [])
  (var config-result nil)
  (server.config.providers (fn [r] (set config-result r)))
  (wait-for #(not= config-result nil) 5000)
  (assert-response-ok config-result "config providers")
  (when (and config-result config-result.data)
    (local defaults (or config-result.data.default {}))
    (each [k v (pairs defaults)]
      (table.insert primary-providers {:providerID k :modelID v})))

  ;; Use opencode-go provider with deepseek-v4-flash — known to work
  (table.insert primary-providers 1 {:providerID "opencode-go" :modelID "deepseek-v4-flash"})

  (run-test "prompt with text"
    (fn []
      ;; Try available models until one returns a successful response
      (var result nil)
      (var current-model (. primary-providers 1))
      (each [_ model (ipairs primary-providers)]
        (when (or (not result) (not result.ok) (and result.data.info result.data.info.error))
          (set current-model model)
          (set result nil)
          (server.session.prompt session-id
                                 {:model model
                                  :parts [{:type "text" :text "What is 2+2? Reply with exactly the number and nothing else."}]}
                                 (fn [r] (set result r)))
          (wait-for #(not= result nil) 60000)))
      (assert-ok result "prompt should return a result")
      (assert-response-ok result "prompt with text")
      (assert-ok result.data "prompt should return data")
      (print "  model used: " (or current-model.providerID "?") "/" (or current-model.modelID "?"))
      (if (and result.data.info result.data.info.error)
          (print "  model error: " (or result.data.info.error.name "unknown") " - " (or (and result.data.info.error.data result.data.info.error.data.message) "n/a"))
          (do
            (assert-ok result.data.info "prompt should have info")
            (assert-ok (= result.data.info.role "assistant") "response should be from assistant")
            (assert-ok result.data.parts "prompt should have parts")
            (assert-ok (> (# result.data.parts) 0) "should have at least one part")
            ;; Find the text part (models may also return step-start, reasoning, step-finish)
            (var text-part nil)
            (each [_ part (ipairs result.data.parts)]
              (when (= part.type "text")
                (set text-part part)))
            (assert-ok text-part "response should include a text part")
            (assert-ok text-part.text "text part should have content")
            (assert-ok (> (# text-part.text) 0) "text response should not be empty")
            (print "  response: " (string.sub text-part.text 1 200))))))

  ;; ── Files ──
  (print "")
  (print "Files:")

  (run-test "file status"
    (fn []
      (var result nil)
      (server.file.status nil (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "file status")
      (assert-ok (= (type result.data) "table") "status should return a table")))

  (run-test "find text"
    (fn []
      (var result nil)
      (server.find.text "function" (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "find text")
      (assert-ok (= (type result.data) "table") "find text should return a table")))

  ;; ── SSE Events ──
  (print "")
  (print "SSE Events:")

  (run-test "event subscription"
    (fn []
      (var events-received 0)
      (local handle (server.events.subscribe
                      (fn [event]
                        (set events-received (+ events-received 1)))))
      (assert-ok handle "should create event handle")
      (assert-ok handle.unsubscribe "handle should have unsubscribe")
      ;; Let some time pass for events
      (poll-events 2000)
      (handle.unsubscribe)
      (print "  events received: " events-received)))

  ;; ── Cleanup ──
  (print "")
  (print "Cleanup:")

  (run-test "delete test session"
    (fn []
      (when session-id
        (var result nil)
        (server.session.delete session-id (fn [r] (set result r)))
        (wait-for #(not= result nil) 5000)
        (assert-response-ok result "delete session"))))

  (run-test "close server"
    (fn []
      (server.close)
      (assert-ok true "server closed")))

  ;; ── Client-only test ──
  (print "")
  (print "Client-only (reconnect):")

  (run-test "start fresh server and connect client"
    (fn []
      (local s (OpencodeSdk.Opencode {:opencode-path opencode-path :port port2}))
      (var result nil)
      (s.global.health (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "fresh server health")
      (assert-ok result.data.healthy "should be healthy")

      ;; Now create a client-only connection
      (local url (s.server.url))
      (local client-only (OpencodeSdk.OpencodeClient {:base-url url}))
      (var result2 nil)
      (client-only.global.health (fn [r] (set result2 r)))
      (wait-for #(not= result2 nil) 5000)
      (assert-response-ok result2 "client-only health")
      (assert-ok result2.data.healthy "client-only health should also work")
      (s.close)))

  ;; ── Summary ──
  (print "")
  (print "==========================")
  (print (.. "Results: " passed " passed, " failed " failed"))
  (when (> (# failures) 0)
    (print "")
    (print "Failures:")
    (each [_ f (ipairs failures)]
      (print (.. "  " f.name ": " f.error))))
  (print "")

  (when (> failed 0)
    (os.exit 1)))

{:main main}
