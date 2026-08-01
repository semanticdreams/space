;; Read-only MCP tools wrapping the project-native Fennel validation service.

(local ToolRegistry (require :mcp/tool-registry))
(local json (require :json))

(local tool-risks {})

(fn make-tool-registry [_opts]
  (ToolRegistry {:namespace-prefix "space_"}))

(fn get-tool-risks []
  tool-risks)

(fn def-tool [name description input-properties run]
  {:name name
   :description description
   :inputSchema {:type "object"
                 :properties input-properties}
   :risk "filesystem-read"
   :run run})

(fn error-payload [err]
  {:ok false
   :status "error"
   :diagnostics [{:kind "tool-error"
                  :message (tostring err)}]})

(fn json-service-call [thunk]
  (local (ok result-or-err) (pcall thunk))
  (json.dumps (if ok result-or-err (error-payload result-or-err))))

(fn require-string [args key]
  (local value (. args key))
  (assert (= (type value) "string") (.. (tostring key) " is required"))
  value)

(fn register-read-tool [registry name description input-properties run]
  (tset tool-risks name "filesystem-read")
  (registry:register (def-tool name description input-properties run)))

(fn register-tools [registry service]
  (register-read-tool
    registry
    "space_fennel_check_file"
    "Compile-check one Fennel file using the project-native validation service."
    {:file {:type "string" :description "Path to a .fnl file."}}
    (fn [args]
      (json-service-call #(service:check-files {:files [(require-string args :file)]}))))

  (register-read-tool
    registry
    "space_constraints_check_files"
    "Run structural constraints for the provided Fennel files."
    {:files {:type "array"
             :items {:type "string"}
             :description "Fennel files to check."}}
    (fn [args]
      (json-service-call #(service:check-constraints-files args))))

  (register-read-tool
    registry
    "space_fennel_parse_tree"
    "Return a bounded tree-sitter parse summary for a Fennel file."
    {:file {:type "string" :description "Path to a .fnl file."}
     :max-chars {:type "integer" :description "Maximum characters of tree output to return."}}
    (fn [args]
      (json-service-call #(service:parse-tree args))))

  (register-read-tool
    registry
    "space_fennel_enclosing_form"
    "Return the smallest enclosing Fennel form at a line and column."
    {:file {:type "string" :description "Path to a .fnl file."}
     :line {:type "integer" :description "1-based line number."}
     :column {:type "integer" :description "1-based column number."}}
    (fn [args]
      (json-service-call #(service:enclosing-form args))))

  (register-read-tool
    registry
    "space_fennel_structure_metrics"
    "Return structure metrics for a Fennel file."
    {:file {:type "string" :description "Path to a .fnl file."}}
    (fn [args]
      (json-service-call #(service:structure-metrics args))))

  registry)

{:make-tool-registry make-tool-registry
 :register-tools register-tools
 :get-tool-risks get-tool-risks}
