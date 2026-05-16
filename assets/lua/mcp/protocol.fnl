;; JSON-RPC 2.0 primitives for MCP
;; All functions are pure — no I/O, no state.

(local json (require :json))

(fn parse-message [line]
  "Parse a JSON-RPC message from a string line.
  Returns the deserialized table on success, or nil + error on failure."
  (local (ok parsed-or-error) (pcall json.loads line))
  (if (not ok)
      (values nil (.. "Invalid JSON: " (tostring parsed-or-error)))
      (= (type parsed-or-error) "table")
      (if (not= (. parsed-or-error "jsonrpc") "2.0")
          (values nil "Missing or invalid jsonrpc version")
          (. parsed-or-error "method")
          parsed-or-error
          (and (. parsed-or-error "id") (or (. parsed-or-error "result") (. parsed-or-error "error")))
          parsed-or-error
          (values nil "Message is not a valid JSON-RPC request, notification, or response"))
      (values nil (.. "JSON-RPC message must be an object, got " (type parsed-or-error)))))

(fn format-message [msg]
  "Serialize a message table to a compact JSON string."
  (json.dumps msg))

(fn response [id result]
  "Create a JSON-RPC success response."
  {:jsonrpc "2.0" :id id :result result})

(fn error-response [id code message data]
  "Create a JSON-RPC error response.
  code: integer error code (e.g. -32601 for method not found)
  message: human-readable error description
  data: optional additional error data"
  (local err {:code code :message message})
  (when data (tset err :data data))
  {:jsonrpc "2.0" :id id :error err})

(fn notification [method params]
  "Create a JSON-RPC notification (no id, no response expected)."
  (local msg {:jsonrpc "2.0" :method method})
  (when params (tset msg :params params))
  msg)

(fn is-request [msg]
  "True if msg is a JSON-RPC request (has method + id)."
  (and (= (type msg) "table")
       (= msg.jsonrpc "2.0")
       msg.method
       msg.id))

(fn is-notification [msg]
  "True if msg is a JSON-RPC notification (has method, no id)."
  (and (= (type msg) "table")
       (= msg.jsonrpc "2.0")
       msg.method
       (not msg.id)))

(fn is-response [msg]
  "True if msg is a JSON-RPC response (has id, no method)."
  (and (= (type msg) "table")
       (= msg.jsonrpc "2.0")
       (not msg.method)
       msg.id))

;; JSON-RPC standard error codes
(local error-codes
  {:PARSE_ERROR -32700
   :INVALID_REQUEST -32600
   :METHOD_NOT_FOUND -32601
   :INVALID_PARAMS -32602
   :INTERNAL_ERROR -32603})

{:parse-message parse-message
 :format-message format-message
 :response response
 :error-response error-response
 :notification notification
 :is-request is-request
 :is-notification is-notification
 :is-response is-response
 :error-codes error-codes}
