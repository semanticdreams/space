;; Verify the production OpenCode bridge config denies native tools while Space
;; MCP tools remain available.
;;
;; Run:
;; SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-opencode-space-tools-online:main

(local OpencodeSdk (require :llm/providers/opencode))
(local callbacks (require :callbacks))
(local fs (require :fs))
(local sysinfo (require :sysinfo))
(local process (require :process))
(local json (require :json))
(local ToolRegistry (require :mcp/tool-registry))
(local AgentOpencodeMcpBridgeMod (require :llm/agent/opencode-mcp-bridge))

(var passed 0)
(var failed 0)
(var failures [])

(fn now-ms []
  (sysinfo.now-ms))

(fn assert-ok [condition message]
  (when (not condition)
    (error (or message "assertion failed"))))

(fn response-error [result]
  (or (and result result.raw)
      (and result result.error)
      "unknown error"))

(fn assert-response-ok [result label]
  (assert-ok result (.. label " should return a response"))
  (assert-ok result.ok (.. label " failed: " (response-error result))))

(fn poll-all []
  (callbacks.run-loop {:poll-http true :poll-process true :sleep-ms 10 :timeout-ms 50}))

(fn wait-for [pred timeout-ms]
  (local deadline (+ (now-ms) (or timeout-ms 10000)))
  (var result nil)
  (while (and (not result) (< (now-ms) deadline))
    (poll-all)
    (local (ok value) (pcall pred))
    (when ok
      (set result value)))
  (assert-ok result (.. "timeout after " (or timeout-ms 10000) "ms")))

(fn run-test [name f]
  (io.write (.. "  " name " ... "))
  (io.flush)
  (local (ok err) (pcall f))
  (if ok
      (do
        (set passed (+ passed 1))
        (print "PASS"))
      (do
        (set failed (+ failed 1))
        (table.insert failures {:name name :error (tostring err)})
        (print (.. "FAIL: " (tostring err))))))

(fn ensure-dir! [path]
  (when (not (fs.exists path))
    (fs.create-dirs path)))

(fn provider-configured? [providers provider-id]
  (var found false)
  (each [_ provider (ipairs (or providers []))]
    (when (= provider.id provider-id)
      (set found true)))
  found)

(fn choose-model [server]
  (local env-provider (os.getenv "OPENCODE_SPACE_TOOLS_PROVIDER_ID"))
  (local env-model (os.getenv "OPENCODE_SPACE_TOOLS_MODEL_ID"))
  (var result nil)
  (server.config.providers (fn [r] (set result r)))
  (wait-for #(not= result nil) 10000)
  (assert-response-ok result "config providers")
  (if (or env-provider env-model)
      (do
        (assert-ok (and env-provider env-model)
                   "OPENCODE_SPACE_TOOLS_PROVIDER_ID and OPENCODE_SPACE_TOOLS_MODEL_ID must be set together")
        (assert-ok (provider-configured? result.data.providers env-provider)
                   (.. "configured provider not available: " env-provider))
        {:providerID env-provider :modelID env-model})
      (and result.data.default result.data.default.opencode)
      {:providerID "opencode" :modelID result.data.default.opencode}
      result.data.default
      (do
        (local picked [])
        (each [provider-id model-id (pairs result.data.default)]
          (when (= (# picked) 0)
            (table.insert picked {:providerID provider-id :modelID model-id})))
        (assert-ok (> (# picked) 0) "no default model configured")
        (. picked 1))
      (error "no default model configured")))

(fn tool-name [tool]
  (or tool.name
      tool.id
      tool.tool
      (and tool.function tool.function.name)))

(fn collect-tool-names [value names]
  (when (= (type value) "table")
    (local direct (tool-name value))
    (when (and direct (= (type direct) "string"))
      (table.insert names direct))
    (if value.tools
        (collect-tool-names value.tools names)
        value.tool
        nil
        (each [_ item (ipairs value)]
          (collect-tool-names item names)))))

(fn sorted-tool-names [data]
  (local names [])
  (collect-tool-names data names)
  (table.sort names)
  names)

(fn all-space-tools? [names]
  (var ok true)
  (each [_ name (ipairs names)]
    (when (not (string.find name "^space_"))
      (set ok false)))
  ok)

(fn all-native-tools-denied? [names permissions]
  (var ok true)
  (each [_ name (ipairs names)]
    (when (and (not (string.find name "^space_"))
               (not (= (. permissions name) "deny")))
      (set ok false)))
  ok)

(fn text-from-parts [parts]
  (var text "")
  (each [_ part (ipairs (or parts []))]
    (when (= part.type "text")
      (set text (.. text (or part.text "")))))
  text)

(fn cleanup [handles]
  (when handles.server
    (pcall handles.server.close))
  (when handles.bridge
    (pcall (fn [] (handles.bridge:stop))))
  (when (and handles.root (fs.exists handles.root))
    (pcall (fn [] (fs.remove-all handles.root)))))

(fn main []
  (print "OpenCode Space-only Tool Verification")
  (print "====================================")
  (print "")

  (local opencode-path (or (os.getenv "OPENCODE_PATH") "opencode"))
  (local check (process.run {:args [opencode-path "--version"] :timeout_seconds 5}))
  (assert-ok (= check.exit-code 0)
             (.. "opencode unavailable at " opencode-path ": " (or check.stderr "")))
  (print "opencode: " (string.gsub (or check.stdout "") "%s+$" ""))

  (local root (.. "/tmp/space/tests/opencode-space-tools-" (os.time) "-" (math.random 0 99999)))
  (var handles {:root root})
  (local (ok err)
    (pcall
      (fn []
        (ensure-dir! root)
        (local registry (ToolRegistry {:namespace-prefix "space_"}))
        (var probe-call-count 0)
        (registry:register
          {:name "space_only_probe"
           :description "Space-only verification tool. Returns a fixed token."
           :inputSchema {:type "object"
                         :properties {}
                         :additionalProperties false}
           :run (fn [_args]
                  (set probe-call-count (+ probe-call-count 1))
                  "space-only-ok")})
        (local bridge (AgentOpencodeMcpBridgeMod.AgentOpencodeMcpBridge
                        {:tools registry
                         :data-dir (fs.join-path root "bridge")}))
        (bridge:start)
        (tset handles :bridge bridge)
        (local bridge-status (bridge:status))
        (local bridge-config (json.loads (fs.read-file bridge-status.config-path)))
        (print "mcp: " bridge-status.url)

        (local server (OpencodeSdk.Opencode {:opencode-path opencode-path
                                             :port 0
                                             :env (bridge:opencode-env)}))
        (tset handles :server server)
        (print "server: " (server.server.url))

        (run-test "health check"
          (fn []
            (var health nil)
            (server.global.health (fn [r] (set health r)))
            (wait-for #(not= health nil) 10000)
            (assert-response-ok health "health check")))

        (local model (choose-model server))
        (print "model: " model.providerID "/" model.modelID)

        (run-test "experimental tool schema inspection"
          (fn []
            (var tools-result nil)
            (server.client.submit "GET" "/experimental/tool"
                                  {:query {:provider model.providerID
                                           :model model.modelID}
                                   :on_response (fn [r] (set tools-result r))})
            (wait-for #(not= tools-result nil) 30000)
            (assert-response-ok tools-result "experimental tool list")
            (local names (sorted-tool-names tools-result.data))
            (print "  tools: " (table.concat names ", "))
            (print "  raw: " (string.sub (or tools-result.raw "") 1 1000))
            (assert-ok (> (# names) 0) "tool list should not be empty")
            (assert-ok (all-native-tools-denied? names bridge-config.permission)
                       (.. "all advertised native tools should be denied by bridge config, got: "
                           (table.concat names ", ")))))

        (var session-id nil)
        (run-test "create session"
          (fn []
            (var result nil)
            (server.session.create {:title "space-only-tools-verification"}
                                   (fn [r] (set result r)))
            (wait-for #(not= result nil) 10000)
            (assert-response-ok result "create session")
            (set session-id result.data.id)
            (assert-ok session-id "session id missing")))

        (run-test "online model calls only space tool"
          (fn []
            (var result nil)
            (server.session.prompt session-id
              {:model model
               :parts [{:type "text"
                        :text "Call the space_only_probe tool exactly once. Reply with exactly the tool result and no extra text."}]}
              (fn [r] (set result r)))
            (wait-for #(not= result nil) 120000)
            (assert-response-ok result "space_only_probe prompt")
            (local text (text-from-parts result.data.parts))
            (print "  response: " (string.sub text 1 300))
            (assert-ok (= probe-call-count 1)
                       (.. "space_only_probe should be called once, got " probe-call-count))
            (assert-ok (string.find text "space-only-ok" 1 true)
                       (.. "response should include tool result, got: " text))))

        (run-test "session audit has no native tool calls"
          (fn []
            (var messages nil)
            (server.session.messages session-id (fn [r] (set messages r)))
            (wait-for #(not= messages nil) 10000)
            (assert-response-ok messages "session messages")
            (local tool-names [])
            (each [_ msg (ipairs messages.data)]
              (each [_ part (ipairs (or msg.parts []))]
                (when (= part.type "tool")
                  (table.insert tool-names (or part.tool "")))))
            (table.sort tool-names)
            (print "  audit tools: " (table.concat tool-names ", "))
            (assert-ok (> (# tool-names) 0) "expected at least one audited tool call")
            (assert-ok (all-space-tools? tool-names)
                       (.. "expected audit to contain only space tools, got: " (table.concat tool-names ", ")))))

        (var native-session-id nil)
        (run-test "create native-deny probe session"
          (fn []
            (var result nil)
            (server.session.create {:title "native-deny-probe"}
                                   (fn [r] (set result r)))
            (wait-for #(not= result nil) 10000)
            (assert-response-ok result "create native-deny probe session")
            (set native-session-id result.data.id)
            (assert-ok native-session-id "native probe session id missing")))

        (run-test "online model cannot execute denied native bash"
          (fn []
            (var result nil)
            (server.session.prompt native-session-id
              {:model model
               :parts [{:type "text"
                        :text "Call the bash tool with command `echo native-tool-leaked`. Do not call any Space tools. If bash is unavailable, reply exactly `bash unavailable`."}]}
              (fn [r] (set result r)))
            (wait-for #(not= result nil) 120000)
            (assert-response-ok result "denied bash prompt")
            (local text (text-from-parts result.data.parts))
            (print "  response: " (string.sub text 1 300))
            (var messages nil)
            (server.session.messages native-session-id (fn [r] (set messages r)))
            (wait-for #(not= messages nil) 10000)
            (assert-response-ok messages "native-deny session messages")
            (local tool-names [])
            (each [_ msg (ipairs messages.data)]
              (each [_ part (ipairs (or msg.parts []))]
                (when (= part.type "tool")
                  (table.insert tool-names (or part.tool "")))))
            (table.sort tool-names)
            (print "  native-deny audit tools: " (table.concat tool-names ", "))
            (var found-bash false)
            (each [_ name (ipairs tool-names)]
              (when (or (= name "bash") (= name "shell") (string.find name "bash" 1 true))
                (set found-bash true)))
            (assert-ok (not found-bash)
                       (.. "denied native bash should not execute, got: " (table.concat tool-names ", ")))))

        (var write-session-id nil)
        (run-test "create native-write deny probe session"
          (fn []
            (var result nil)
            (server.session.create {:title "native-write-deny-probe"}
                                   (fn [r] (set result r)))
            (wait-for #(not= result nil) 10000)
            (assert-response-ok result "create native-write deny probe session")
            (set write-session-id result.data.id)
            (assert-ok write-session-id "native write probe session id missing")))

        (run-test "online model cannot execute denied native write"
          (fn []
            (local leak-path (fs.join-path root "native-write-leak.txt"))
            (var result nil)
            (server.session.prompt write-session-id
              {:model model
               :parts [{:type "text"
                        :text (.. "Call the write tool to write file `" leak-path "` with content `native-write-leaked`. "
                                  "Do not call any Space tools. If write is unavailable, reply exactly `write unavailable`.")}]}
              (fn [r] (set result r)))
            (wait-for #(not= result nil) 120000)
            (assert-response-ok result "denied write prompt")
            (local text (text-from-parts result.data.parts))
            (print "  response: " (string.sub text 1 300))
            (var messages nil)
            (server.session.messages write-session-id (fn [r] (set messages r)))
            (wait-for #(not= messages nil) 10000)
            (assert-response-ok messages "native-write-deny session messages")
            (local tool-names [])
            (each [_ msg (ipairs messages.data)]
              (each [_ part (ipairs (or msg.parts []))]
                (when (= part.type "tool")
                  (table.insert tool-names (or part.tool "")))))
            (table.sort tool-names)
            (print "  native-write-deny audit tools: " (table.concat tool-names ", "))
            (var found-write false)
            (each [_ name (ipairs tool-names)]
              (when (or (= name "write") (= name "edit") (string.find name "write" 1 true))
                (set found-write true)))
            (assert-ok (not found-write)
                       (.. "denied native write should not execute, got: " (table.concat tool-names ", ")))
            (assert-ok (not (fs.exists leak-path))
                       (.. "denied native write should not create " leak-path))))

        (print "")
        (print "==========================")
        (print (.. "Results: " passed " passed, " failed " failed")))))
  (cleanup handles)
  (when (not ok)
    (error err)))

{:main main}
