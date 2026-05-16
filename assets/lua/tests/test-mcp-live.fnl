;; MCP + OpenCode live integration test.
;; Starts opencode serve, configures the MCP server, and verifies tool calls through LLM prompts.
;; Requires: opencode binary, API keys configured.
;; Gated behind MCP_LIVE_TESTS=1.
;; Run: MCP_LIVE_TESTS=1 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-mcp-live:main

(local OpencodeSdk (require :llm/providers/opencode))
(local callbacks (require :callbacks))
(local fs (require :fs))
(local json (require :json))
(local sysinfo (require :sysinfo))
(local http-server-mod (require :http_server))
(local ToolRegistry (require :mcp/tool-registry))
(local MCPHTTPServer (require :mcp/server-http))

(var tools nil)    ;; set by main() for runtime tool changes
(var mcp-srv nil)  ;; set by main() for cleanup

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

(fn space-ping-tool-part? [part]
  (and (= part.type "tool")
       (string.find (or part.tool "") "space_ping" 1 true)))

(fn completed-space-ping-part? [part]
  (and (space-ping-tool-part? part)
       part.state
       (= part.state.status "completed")
       (string.find (or part.state.output "") "space-pong" 1 true)))

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
  (print "MCP + OpenCode Live Integration Tests")
  (print "=====================================")
  (print "")

  ;; Gate: skip if env var not set
  (when (not= (os.getenv "MCP_LIVE_TESTS") "1")
    (print "SKIP: Set MCP_LIVE_TESTS=1 to run live tests.")
    (os.exit 0))

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
      (print "  version check: OK"))

  (math.randomseed (math.floor (sysinfo.now-ms)))
  (local port (+ 20000 (math.random 0 20000)))
  (print "Using opencode port: " port)

  (var srv nil)
  (var session-id nil)
  (local xdg-config (.. "/tmp/space/tests/opencode-mcp-live-" (tostring (os.time))))
  (var mcp-port nil)

  ;; ── Start MCP HTTP server ──
  (print "")
  (print "MCP HTTP server:")

  (run-test "start MCP HTTP server"
    (fn []
      (set tools (ToolRegistry {:namespace-prefix "space_"}))
      (tools:register {:name "space_ping"
                       :description "Space test ping tool. Responds with space-pong."
                       :inputSchema {:type "object" :properties {}}
                       :run (fn [] "space-pong")})
      (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                                 :tools tools
                                 :force-sse true}))
      (set mcp-port (srv:start "127.0.0.1" 0))
      (set mcp-srv srv)
      (assert-ok (> mcp-port 0) "should get valid port")
      (print "  MCP server on port " mcp-port)))

  ;; ── Write isolated opencode config with remote MCP URL ──
  (print "")
  (print "Config preparation:")

  (run-test "add remote MCP to isolated opencode config"
    (fn []
      (local config-dir (fs.join-path xdg-config "opencode"))
      (local config-path (fs.join-path config-dir "opencode.json"))
      (when (fs.exists xdg-config)
        (fs.remove-all xdg-config))
      (fs.create-dirs config-dir)

      (var config {})
      (tset config :mcp {:space {:type "remote"
                                  :url (.. "http://127.0.0.1:" mcp-port "/mcp")
                                  :enabled true}})
      (fs.write-file config-path (json.dumps config))
      (print "  remote MCP URL: http://127.0.0.1:" mcp-port "/mcp")))

  ;; ── Start opencode server ──
  (print "")
  (print "Server setup:")

  (run-test "start opencode server"
    (fn []
      (local sv (OpencodeSdk.Opencode {:opencode-path opencode-path
                                        :port port
                                        :env {:XDG_CONFIG_HOME xdg-config}}))
      (assert-ok sv "should create opencode instance")
      (assert-ok sv.client "should have client")
      (set srv sv)
      (print " (url: " (sv.server.url) ")")))

  (when (not srv)
    (print "ERROR: opencode server failed to start")
    (os.exit 1))

  (local server srv)

  (run-test "health check"
    (fn []
      (var result nil)
      (server.global.health (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "health check")
      (assert-ok result.data.healthy "server should be healthy")
      (print "  version: " (or result.data.version "unknown"))))

  ;; ── Create session ──
  (print "")
  (print "Session & Prompt:")

  (run-test "create session"
    (fn []
      (var result nil)
      (server.session.create {:title "mcp-live-test"}
                             (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "create session")
      (assert-ok result.data.id "session should have an id")
      (set session-id result.data.id)
      (print "  id: " result.data.id)))

  ;; ── Find an available model ──
  (var model nil)

  (run-test "get providers"
    (fn []
      (var result nil)
      (server.config.providers (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "get providers")
      (assert-ok result.data.providers "should have providers")
      (assert-ok (> (# result.data.providers) 0) "should have at least one")
      (local env-provider (os.getenv "MCP_LIVE_PROVIDER_ID"))
      (local env-model (os.getenv "MCP_LIVE_MODEL_ID"))
      (if (or env-provider env-model)
          (do
            (assert-ok (and env-provider env-model)
                       "MCP_LIVE_PROVIDER_ID and MCP_LIVE_MODEL_ID must be set together")
            (set model {:providerID env-provider :modelID env-model}))
          (and result.data.default result.data.default.opencode)
          (set model {:providerID "opencode" :modelID result.data.default.opencode})
          result.data.default
          (each [provider-id model-id (pairs result.data.default)]
            (when (not model)
              (set model {:providerID provider-id :modelID model-id}))))
      (assert-ok model "should choose a model from opencode defaults")
      (print "  using model: " model.providerID "/" model.modelID)))

  ;; ── Send prompt that should trigger ping tool ──
  (run-test "prompt triggers ping tool"
    (fn []
      (var result nil)
      (server.session.prompt session-id
        {:model model
         :parts [{:type "text"
                  :text (.. "Use the space_ping tool and tell me exactly what it returns. "
                            "Do not say anything else — just the tool result.")}]}
        (fn [r] (set result r)))
      (wait-for #(not= result nil) 120000)
      (assert-ok result "prompt should return a result")
      (print "  status: " (tostring result.status) " ok: " (tostring result.ok) " error: " (tostring result.error))
      (assert-response-ok result "ping prompt")
      (print "  data type: " (type result.data))
      (when (= (type result.data) "string")
        (print "  raw body: " (string.sub result.data 1 500)))
      (assert-ok result.data "prompt should return data")
      (assert-ok (= (type result.data) "table") "prompt data should be a table")
      (print "  response role: " (or result.data.info.role "?"))

      ;; Collect the response text
      (var text-parts [])
      (each [_ part (ipairs (or result.data.parts []))]
        (when (= part.type "text")
          (table.insert text-parts part.text)))
      (local full-text (table.concat text-parts " "))
      (print "  response: " (string.sub full-text 1 300))
      (assert-ok (string.find full-text "space-pong" 1 true)
                 (.. "response should include space_ping result, got: " full-text))))

  ;; ── Verify messages include tool interactions ──
  (run-test "verify tool was called in messages"
    (fn []
      (var result nil)
      (server.session.messages session-id (fn [r] (set result r)))
      (wait-for #(not= result nil) 5000)
      (assert-response-ok result "session messages")
      (assert-ok result.data "messages should return data")
      (assert-ok (> (# result.data) 0) "should have at least 1 message")
      (print "  message count: " (# result.data))

      ;; Current opencode represents tool calls as type="tool" parts.
      (var found-tool false)
      (var found-tool-result false)
      (each [_ msg (ipairs result.data)]
        (when msg.parts
          (each [_ part (ipairs msg.parts)]
            (when (space-ping-tool-part? part)
              (set found-tool true)
              (when (completed-space-ping-part? part)
                (set found-tool-result true))))))
      (print (.. "  space_ping tool part found: " (tostring found-tool)))
      (print (.. "  space_ping result found: " (tostring found-tool-result)))
      (assert-ok found-tool "messages should include a space_ping tool part")
      (assert-ok found-tool-result "messages should include completed space_ping output")))

  ;; ── Runtime tool change ──
  ;; Uses SSE transport (2024-11-05) where list_changed flows through the
  ;; same SSE stream as responses. This avoids MCP SDK issue #1771.
  (print "")
  (print "Runtime tool change:")

  (run-test "register runtime tool"
    (fn []
      (tools:register {:name "space_echo"
                       :description "Echoes back the provided message."
                       :inputSchema {:type "object"
                                     :properties {:msg {:type "string"
                                                        :description "Text to echo"}}
                                     :required [:msg]}
                       :run (fn [args] (or args.msg ""))})
      ;; Give opencode time to process list_changed via SSE.
      (poll-events 2000)
      (assert-ok true "tool registered")))

  (run-test "prompt triggers runtime tool"
    (fn []
      (var result nil)
      (server.session.prompt session-id
        {:model model
         :parts [{:type "text"
                  :text "Use the space_echo tool with msg=\"runtime-works\" and tell me exactly what it returns."}]}
        (fn [r] (set result r)))
      (wait-for #(not= result nil) 120000)
      (assert-response-ok result "runtime tool prompt")

      (var text "")
      (each [_ part (ipairs (or result.data.parts []))]
        (when (= part.type "text")
          (set text (.. text part.text))))
      (print "  response: " (string.sub text 1 200))
      (assert-ok (string.find text "runtime-works" 1 true)
                 (.. "LLM should echo input, got: " text))))

  (print "")
  (print "Cleanup:")

  (run-test "remove isolated opencode config"
    (fn []
      (when (fs.exists xdg-config)
        (fs.remove-all xdg-config))
      (assert-ok true "config removed")))

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
      (when mcp-srv (mcp-srv:stop))
      (assert-ok true "server closed")))

  ;; ── Summary ──
  (print "")
  (print "==========================")
  (print (.. "Results: " passed " passed, " failed " failed, " skipped " skipped"))
  (when (> (# failures) 0)
    (print "")
    (print "Failures:")
    (each [_ f (ipairs failures)]
      (print (.. "  " f.name ": " f.error))))
  (print "")

  (when (> failed 0)
    (os.exit 1)))

{:main main}
