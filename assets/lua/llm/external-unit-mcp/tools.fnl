;; External Unit MCP Tools — wraps ExternalUnitService operations in an MCP ToolRegistry
;; for external OpenCode sessions.

(local ToolRegistry (require :mcp/tool-registry))
(local json (require :json))

(fn make-tool-registry [opts]
  (ToolRegistry {:namespace-prefix "space_"}))

(fn def-tool [name description input-properties risk run]
  {:name name
   :description description
   :inputSchema {:type "object"
                 :properties input-properties}
   :risk risk
   :run run})

(local tool-risks {})

(fn get-tool-risks []
  tool-risks)

(fn register-tools [registry service]
  ;; space_unit_list — list all external units
  (tset tool-risks "space_unit_list" "normal")
  (registry:register
    (def-tool "space_unit_list"
      "List all external units with loader-neutral handles."
      {}
      "normal"
      (fn [args]
        (json.dumps (service:list (or args {}))))))

  ;; space_unit_inspect — inspect a specific unit
  (tset tool-risks "space_unit_inspect" "normal")
  (registry:register
    (def-tool "space_unit_inspect"
      "Inspect a unit by id and report its loader, source artifacts, and lifecycle exports."
      {:unit_id {:type "string" :description "The unit identifier."}}
      "normal"
      (fn [args]
        (json.dumps (service:inspect args)))))

  ;; space_unit_resolve — resolve a unit by description
  (tset tool-risks "space_unit_resolve" "normal")
  (registry:register
    (def-tool "space_unit_resolve"
      "Resolve a unit from a natural-language description with ranked candidates."
      {:description {:type "string" :description "Natural-language description of the unit to find."}
       :limit {:type "integer" :description "Maximum number of candidates to return (default 20)."}}
      "normal"
      (fn [args]
        (json.dumps (service:resolve args)))))

  ;; space_unit_read_source — read a source artifact
  (tset tool-risks "space_unit_read_source" "filesystem-read")
  (registry:register
    (def-tool "space_unit_read_source"
      "Read the content of a unit source artifact and its current hash."
      {:unit_id {:type "string" :description "The unit identifier."}
       :source_id {:type "string" :description "The source artifact identifier."}}
      "filesystem-read"
      (fn [args]
        (json.dumps (service:read-source args)))))

  ;; space_unit_apply_patch — apply a patch to a unit source
  (tset tool-risks "space_unit_apply_patch" "filesystem-write")
  (registry:register
    (def-tool "space_unit_apply_patch"
      "Apply an edit (exact replacement or unified diff patch) to a unit source file. Supports stale-content detection via expected_hash."
      {:unit_id {:type "string" :description "The unit identifier."}
       :source_id {:type "string" :description "The source artifact identifier."}
       :patch {:type "string" :description "A unified diff patch to apply."}
       :old {:type "string" :description "Exact text to find and replace."}
       :new {:type "string" :description "New text to replace the old text."}
       :expected_hash {:type "string" :description "Expected current hash of the source (sha256: prefix). Rejects the patch if the file no longer matches."}}
      "filesystem-write"
      (fn [args]
        (json.dumps (service:apply-patch args)))))

  ;; space_unit_create_source — create a new source artifact in a directory unit
  (tset tool-risks "space_unit_create_source" "filesystem-write")
  (registry:register
    (def-tool "space_unit_create_source"
      "Create a new source file inside a directory-based unit."
      {:unit_id {:type "string" :description "The unit identifier."}
       :source_id {:type "string" :description "The new source file name (relative to unit root)."}
       :source {:type "string" :description "The source content to write."}}
      "filesystem-write"
      (fn [args]
        (json.dumps (service:create-source args)))))

  ;; space_unit_run_tests — run unit tests
  (tset tool-risks "space_unit_run_tests" "shell")
  (registry:register
    (def-tool "space_unit_run_tests"
      "Run tests for a unit by executing its test module."
      {:unit_id {:type "string" :description "The unit identifier."}
       :test_name {:type "string" :description "The test suffix name (default: 'init')."}}
      "shell"
      (fn [args]
        (json.dumps (service:run-tests args)))))

  ;; space_unit_reload — reload a unit
  (tset tool-risks "space_unit_reload" "normal")
  (registry:register
    (def-tool "space_unit_reload"
      "Reload a unit to reflect its current source state, returning active activity before/after state and reactivation evidence when applicable."
      {:unit_id {:type "string" :description "The unit identifier."}}
      "normal"
      (fn [args]
        (json.dumps (service:reload args)))))

  ;; space_unit_read_log — read application log
  (tset tool-risks "space_unit_read_log" "filesystem-read")
  (registry:register
    (def-tool "space_unit_read_log"
      "Read recent lines from the application log with optional filtering and pagination."
      {:grep {:type "string" :description "Filter lines containing this substring."}
       :lines {:type "integer" :description "Number of recent lines to return."}
       :offset {:type "integer" :description "Line offset from the beginning."}
       :limit {:type "integer" :description "Maximum number of lines to return."}}
      "filesystem-read"
      (fn [args]
        (local result (service:read-log args))
        ;; Do not expose the raw native log-path through the external API
        (tset result :log-path nil)
        (json.dumps result))))

  ;; space_unit_snapshot — snapshot a unit's state
  (tset tool-risks "space_unit_snapshot" "normal")
  (registry:register
    (def-tool "space_unit_snapshot"
      "Capture a snapshot of a unit's current state for later restoration."
      {:unit_id {:type "string" :description "The unit identifier."}}
      "normal"
      (fn [args]
        (json.dumps (service:snapshot args)))))

  registry)

{: make-tool-registry
 : register-tools
 : get-tool-risks}
