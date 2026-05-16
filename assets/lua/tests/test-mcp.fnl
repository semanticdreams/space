;; MCP offline tests — protocol, tool registry, and server integration.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-mcp:main

(local tests [])
(local protocol (require :mcp/protocol))
(local ToolRegistry (require :mcp/tool-registry))
(local json (require :json))

;; ── Protocol Tests ──

(fn test-parse-valid-request []
  (local msg (protocol.parse-message "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}"))
  (assert msg "should parse a valid request")
  (assert (= msg.jsonrpc "2.0") "jsonrpc should be 2.0")
  (assert (= msg.id 1) "id should be 1")
  (assert (= msg.method "tools/list") "method should be tools/list"))

(table.insert tests {:name "protocol: parse valid request" :fn test-parse-valid-request})

(fn test-parse-valid-notification []
  (local msg (protocol.parse-message "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"))
  (assert msg "should parse a valid notification")
  (assert (= msg.method "notifications/initialized") "method should match")
  (assert (= msg.id nil) "notification should have no id"))

(table.insert tests {:name "protocol: parse valid notification" :fn test-parse-valid-notification})

(fn test-parse-invalid-json []
  (local (msg err) (protocol.parse-message "not json"))
  (assert (= msg nil) "should return nil for invalid JSON")
  (assert err "should return error message"))

(table.insert tests {:name "protocol: parse invalid JSON" :fn test-parse-invalid-json})

(fn test-parse-missing-jsonrpc []
  (local (msg err) (protocol.parse-message "{\"id\":1,\"method\":\"test\"}"))
  (assert (= msg nil) "should reject missing jsonrpc")
  (assert err "should return error"))

(table.insert tests {:name "protocol: parse missing jsonrpc" :fn test-parse-missing-jsonrpc})

(fn test-response-format []
  (local r (protocol.response 5 {:tools []}))
  (assert (= r.jsonrpc "2.0"))
  (assert (= r.id 5))
  (assert (= (type r.result) "table"))
  (assert (= (type r.result.tools) "table")))

(table.insert tests {:name "protocol: response format" :fn test-response-format})

(fn test-error-response-format []
  (local e (protocol.error-response 3 -32601 "Method not found"))
  (assert (= e.jsonrpc "2.0"))
  (assert (= e.id 3))
  (assert (= e.error.code -32601))
  (assert (= e.error.message "Method not found")))

(table.insert tests {:name "protocol: error response format" :fn test-error-response-format})

(fn test-error-response-with-data []
  (local e (protocol.error-response 7 -32602 "Invalid params" {:detail "missing name"}))
  (assert (= e.error.data.detail "missing name")))

(table.insert tests {:name "protocol: error response with data" :fn test-error-response-with-data})

(fn test-notification-format []
  (local n (protocol.notification "notifications/initialized"))
  (assert (= n.jsonrpc "2.0"))
  (assert (= n.method "notifications/initialized"))
  (assert (= n.id nil) "notifications must have no id")
  (assert (= n.params nil) "params should be nil when not provided"))

(table.insert tests {:name "protocol: notification format" :fn test-notification-format})

(fn test-notification-with-params []
  (local n (protocol.notification "notifications/tools/list_changed" {:reason "updated"}))
  (assert (= n.params.reason "updated")))

(table.insert tests {:name "protocol: notification with params" :fn test-notification-with-params})

(fn test-is-request []
  (assert (protocol.is-request {:jsonrpc "2.0" :id 1 :method "test"}))
  (assert (not (protocol.is-request {:jsonrpc "2.0" :method "test"})) "no id = notification")
  (assert (not (protocol.is-request {:jsonrpc "2.0" :id 1 "result" {}})) "has result = response"))

(table.insert tests {:name "protocol: is-request" :fn test-is-request})

(fn test-is-notification []
  (assert (protocol.is-notification {:jsonrpc "2.0" :method "test"}))
  (assert (not (protocol.is-notification {:jsonrpc "2.0" :id 1 :method "test"})) "has id = request"))

(table.insert tests {:name "protocol: is-notification" :fn test-is-notification})

(fn test-is-response []
  (assert (protocol.is-response {:jsonrpc "2.0" :id 1 :result {}}))
  (assert (not (protocol.is-response {:jsonrpc "2.0" :id 1 :method "test"})) "has method = request"))

(table.insert tests {:name "protocol: is-response" :fn test-is-response})

(fn test-format-message-roundtrip []
  (local original {:jsonrpc "2.0" :id 42 :result {:tools [{:name "ping" :description "test"}]}})
  (local line (protocol.format-message original))
  (local parsed (json.loads line))
  (assert (= parsed.jsonrpc "2.0"))
  (assert (= parsed.id 42))
  (assert (= (. parsed :result :tools 1 :name) "ping"))
  (assert (not (string.find line "\n")) "message must not contain embedded newlines"))

(table.insert tests {:name "protocol: format-message roundtrip no embedded newlines"
                     :fn test-format-message-roundtrip})

(fn test-error-codes []
  (assert (= protocol.error-codes.PARSE_ERROR -32700))
  (assert (= protocol.error-codes.METHOD_NOT_FOUND -32601))
  (assert (= protocol.error-codes.INVALID_PARAMS -32602))
  (assert (= protocol.error-codes.INTERNAL_ERROR -32603)))

(table.insert tests {:name "protocol: error codes defined" :fn test-error-codes})

;; ── Tool Registry Tests ──

(fn test-registry-create []
  (local reg (ToolRegistry))
  (assert reg "registry should be created"))

(table.insert tests {:name "tool-registry: create" :fn test-registry-create})

(fn test-registry-register-and-list []
  (local reg (ToolRegistry))
  (reg:register {:name "test-tool"
                 :description "A test tool"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "ok")})
  (local tools (reg:list))
  (assert (= (# tools) 1) "should list 1 tool")
  (assert (= (. tools 1 :name) "test-tool") "tool name should match")
  (assert (= (. tools 1 :description) "A test tool") "tool description should match")
  (assert (= (type (. tools 1 :inputSchema)) "table") "inputSchema should be a table")
  (assert (= (. tools 1 :run) nil) "run function should not be in list output"))

(table.insert tests {:name "tool-registry: register and list" :fn test-registry-register-and-list})

(fn test-registry-call-success []
  (local reg (ToolRegistry))
  (reg:register {:name "echo"
                 :description "Echo"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [args] (or args.message "no message"))})
  (local result (reg:call "echo" {:message "hello"}))
  (assert (= result.isError false) "should not be an error")
  (assert (= (# result.content) 1) "should have 1 content item")
  (assert (= (. result.content 1 :type) "text") "content should be text")
  (assert (= (. result.content 1 :text) "hello") "content should match"))

(table.insert tests {:name "tool-registry: call success" :fn test-registry-call-success})

(fn test-registry-call-no-args []
  (local reg (ToolRegistry))
  (reg:register {:name "ping"
                 :description "Ping"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "pong")})
  (local result (reg:call "ping"))
  (assert (= result.isError false))
  (assert (= (. result.content 1 :text) "pong")))

(table.insert tests {:name "tool-registry: call with no args" :fn test-registry-call-no-args})

(fn test-registry-call-unknown-tool []
  (local reg (ToolRegistry))
  (local (ok err) (pcall reg.call reg "nonexistent"))
  (assert (not ok) "should fail for unknown tool")
  (assert (string.find (tostring err) "Unknown tool") "error should mention unknown tool"))

(table.insert tests {:name "tool-registry: call unknown tool" :fn test-registry-call-unknown-tool})

(fn test-registry-call-tool-error []
  (local reg (ToolRegistry))
  (reg:register {:name "oops"
                 :description "Always fails"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] (error "something went wrong"))})
  (local result (reg:call "oops"))
  (assert (= result.isError true) "should be an error")
  (assert (string.find (. result.content 1 :text) "something went wrong")
          "should contain the error message"))

(table.insert tests {:name "tool-registry: call with tool error" :fn test-registry-call-tool-error})

(fn test-registry-unregister []
  (local reg (ToolRegistry))
  (reg:register {:name "temp"
                 :description "Temporary"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "bye")})
  (assert (= (# (reg:list)) 1) "should have 1 tool before unregister")
  (reg:unregister "temp")
  (assert (= (# (reg:list)) 0) "should have 0 tools after unregister"))

(table.insert tests {:name "tool-registry: unregister" :fn test-registry-unregister})

(fn test-registry-on-change []
  (local reg (ToolRegistry))
  (var called 0)
  (reg:add-on-change (fn [] (set called (+ called 1))))
  (reg:register {:name "a"
                 :description "A"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "ok")})
  (assert (= called 1) "on-change should fire on register")
  (reg:unregister "a")
  (assert (= called 2) "on-change should fire on unregister"))

(table.insert tests {:name "tool-registry: on-change callback" :fn test-registry-on-change})

(fn test-registry-multiple-on-change []
  (local reg (ToolRegistry))
  (var a 0)
  (var b 0)
  (reg:add-on-change (fn [] (set a (+ a 1))))
  (reg:add-on-change (fn [] (set b (+ b 1))))
  (reg:register {:name "x"
                 :description "X"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "ok")})
  (assert (= a 1) "first listener should fire")
  (assert (= b 1) "second listener should fire"))

(table.insert tests {:name "tool-registry: multiple on-change listeners"
                     :fn test-registry-multiple-on-change})

(fn test-registry-remove-on-change []
  (local reg (ToolRegistry))
  (var a 0)
  (var b 0)
  (local token (reg:add-on-change (fn [] (set a (+ a 1)))))
  (reg:add-on-change (fn [] (set b (+ b 1))))
  (reg:register {:name "y"
                 :description "Y"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "ok")})
  (assert (= a 1) "should fire before removal")
  (assert (= b 1) "second listener also fires")
  (reg:remove-on-change token)
  (reg:register {:name "z"
                 :description "Z"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "ok")})
  (assert (= a 1) "removed listener should not fire again")
  (assert (= b 2) "remaining listener should still fire"))

(table.insert tests {:name "tool-registry: remove on-change listener"
                     :fn test-registry-remove-on-change})

(fn test-registry-validate-name []
  (local reg (ToolRegistry))
  (local (ok err) (pcall reg.register reg
                          {:description "missing name"
                           :inputSchema {:type "object"}
                           :run (fn [] "ok")}))
  (assert (not ok) "should fail without name")
  (assert (string.find (tostring err) "name") "error should mention name"))

(table.insert tests {:name "tool-registry: validate requires name" :fn test-registry-validate-name})

(fn test-registry-validate-description []
  (local reg (ToolRegistry))
  (local (ok err) (pcall reg.register reg
                          {:name "x"
                           :inputSchema {:type "object"}
                           :run (fn [] "ok")}))
  (assert (not ok) "should fail without description")
  (assert (string.find (tostring err) "description") "error should mention description"))

(table.insert tests {:name "tool-registry: validate requires description"
                     :fn test-registry-validate-description})

(fn test-registry-validate-input-schema []
  (local reg (ToolRegistry))
  (local (ok err) (pcall reg.register reg
                          {:name "x"
                           :description "desc"
                           :run (fn [] "ok")}))
  (assert (not ok) "should fail without inputSchema")
  (assert (string.find (tostring err) "inputSchema") "error should mention inputSchema"))

(table.insert tests {:name "tool-registry: validate requires inputSchema"
                     :fn test-registry-validate-input-schema})

(fn test-registry-validate-run []
  (local reg (ToolRegistry))
  (local (ok err) (pcall reg.register reg
                          {:name "x"
                           :description "desc"
                           :inputSchema {:type "object"}}))
  (assert (not ok) "should fail without run function")
  (assert (string.find (tostring err) "run") "error should mention run"))

(table.insert tests {:name "tool-registry: validate requires run function"
                     :fn test-registry-validate-run})

(fn test-registry-validate-name-characters []
  (local reg (ToolRegistry))
  (local (ok err) (pcall reg.register reg
                          {:name "bad name"
                           :description "desc"
                           :inputSchema {:type "object"}
                           :run (fn [] "ok")}))
  (assert (not ok) "should fail for invalid name characters")
  (assert (string.find (tostring err) "letters") "error should mention allowed characters"))

(table.insert tests {:name "tool-registry: validate name characters"
                     :fn test-registry-validate-name-characters})

(fn test-registry-validate-namespace-prefix []
  (local reg (ToolRegistry {:namespace-prefix "space_"}))
  (local (ok err) (pcall reg.register reg
                          {:name "echo"
                           :description "desc"
                           :inputSchema {:type "object"}
                           :run (fn [] "ok")}))
  (assert (not ok) "should fail without namespace prefix")
  (assert (string.find (tostring err) "space_" 1 true) "error should mention prefix")
  (reg:register {:name "space_echo"
                 :description "desc"
                 :inputSchema {:type "object"}
                 :run (fn [] "ok")})
  (assert (= (. (reg:list) 1 :name) "space_echo") "prefixed tool should register"))

(table.insert tests {:name "tool-registry: namespace prefix is enforced"
                     :fn test-registry-validate-namespace-prefix})

(fn test-registry-validate-schema-type []
  (local reg (ToolRegistry))
  (local (ok err) (pcall reg.register reg
                          {:name "space_bad_schema"
                           :description "desc"
                           :inputSchema {:type "array"}
                           :run (fn [] "ok")}))
  (assert (not ok) "should fail for non-object schema type")
  (assert (string.find (tostring err) "inputSchema.type") "error should mention schema type"))

(table.insert tests {:name "tool-registry: schema type must be object"
                     :fn test-registry-validate-schema-type})

(fn test-registry-status []
  (local reg (ToolRegistry {:namespace-prefix "space_"}))
  (local status0 (reg:status))
  (assert (= status0.tool-count 0) "status should start with zero tools")
  (assert (= status0.namespace-prefix "space_") "status should expose namespace prefix")
  (reg:register {:name "space_status"
                 :description "desc"
                 :inputSchema {:type "object"}
                 :run (fn [] "ok")})
  (local status1 (reg:status))
  (assert (= status1.tool-count 1) "status should count tools")
  (assert (= status1.change-count 1) "status should count changes")
  (assert status1.last-change "status should expose last change time"))

(table.insert tests {:name "tool-registry: status reports contract metadata"
                     :fn test-registry-status})

(fn test-registry-multiple-tools []
  (local reg (ToolRegistry))
  (reg:register {:name "a"
                 :description "A"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "a")})
  (reg:register {:name "b"
                 :description "B"
                 :inputSchema {:type "object" :properties {}}
                 :run (fn [] "b")})
  (local tools (reg:list))
  (assert (= (# tools) 2) "should have 2 tools")
  (assert (= (. tools 1 :name) "a") "tools should be sorted by name")
  (assert (= (. tools 2 :name) "b") "tools should be sorted by name"))

(table.insert tests {:name "tool-registry: multiple tools" :fn test-registry-multiple-tools})

(fn test-registry-tool-with-parameters []
  (local reg (ToolRegistry))
  (reg:register {:name "add"
                 :description "Add two numbers"
                 :inputSchema {:type "object"
                               :properties {:a {:type "number" :description "First number"}
                                            :b {:type "number" :description "Second number"}}
                               :required [:a :b]}
                 :run (fn [args] (tostring (+ (or args.a 0) (or args.b 0))))})
  (local result (reg:call "add" {:a 3 :b 4}))
  (assert (= result.isError false))
  (assert (= (. result.content 1 :text) "7")))

(table.insert tests {:name "tool-registry: tool with parameters" :fn test-registry-tool-with-parameters})

;; ── Main for stand-alone run ──

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "mcp" :tests tests}))

{:tests tests
 :main main}
