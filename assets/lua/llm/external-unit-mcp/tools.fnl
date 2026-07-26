;; External Unit MCP Tools — wraps ExternalUnitService operations in an MCP ToolRegistry
;; for external OpenCode sessions.

(local ToolRegistry (require :mcp/tool-registry))
(local json (require :json))

(fn make-tool-registry [opts]
  (ToolRegistry {:namespace-prefix "space_"}))

(fn def-tool [name description input-properties run]
  {:name name
   :description description
   :inputSchema {:type "object"
                 :properties input-properties}
   :run run})

(fn register-tools [registry service]
  ;; space_unit_list — list all external units
  (registry:register
    (def-tool "space_unit_list"
      "List all external units with loader-neutral handles."
      {}
      (fn [args]
        (json.dumps (service:list (or args {}))))))

  ;; space_unit_inspect — inspect a specific unit
  (registry:register
    (def-tool "space_unit_inspect"
      "Inspect a unit by id and report its loader, source artifacts, and lifecycle exports."
      {:unit_id {:type "string" :description "The unit identifier."}}
      (fn [args]
        (json.dumps (service:inspect args)))))

  ;; space_unit_resolve — resolve a unit by description
  (registry:register
    (def-tool "space_unit_resolve"
      "Resolve a unit from a natural-language description with ranked candidates."
      {:description {:type "string" :description "Natural-language description of the unit to find."}
       :limit {:type "integer" :description "Maximum number of candidates to return (default 20)."}}
      (fn [args]
        (json.dumps (service:resolve args)))))

  ;; space_unit_read_source — read a source artifact
  (registry:register
    (def-tool "space_unit_read_source"
      "Read the content of a unit source artifact and its current hash."
      {:unit_id {:type "string" :description "The unit identifier."}
       :source_id {:type "string" :description "The source artifact identifier."}}
      (fn [args]
        (json.dumps (service:read-source args)))))

  ;; space_unit_apply_patch — apply a patch to a unit source
  (registry:register
    (def-tool "space_unit_apply_patch"
      "Apply an edit (exact replacement or unified diff patch) to a unit source file. Supports stale-content detection via expected_hash."
      {:unit_id {:type "string" :description "The unit identifier."}
       :source_id {:type "string" :description "The source artifact identifier."}
       :patch {:type "string" :description "A unified diff patch to apply."}
       :old {:type "string" :description "Exact text to find and replace."}
       :new {:type "string" :description "New text to replace the old text."}
       :expected_hash {:type "string" :description "Expected current hash of the source (sha256: prefix). Rejects the patch if the file no longer matches."}}
      (fn [args]
        (json.dumps (service:apply-patch args)))))

  ;; space_unit_create_source — create a new source artifact in a directory unit
  (registry:register
    (def-tool "space_unit_create_source"
      "Create a new source file inside a directory-based unit."
      {:unit_id {:type "string" :description "The unit identifier."}
       :source_id {:type "string" :description "The new source file name (relative to unit root)."}
       :source {:type "string" :description "The source content to write."}}
      (fn [args]
        (json.dumps (service:create-source args)))))

  ;; space_unit_run_tests — run unit tests
  (registry:register
    (def-tool "space_unit_run_tests"
      "Run tests for a unit by executing its test module."
      {:unit_id {:type "string" :description "The unit identifier."}
       :test_name {:type "string" :description "The test suffix name (default: 'init')."}}
      (fn [args]
        (json.dumps (service:run-tests args)))))

  ;; space_unit_reload — reload a unit
  (registry:register
    (def-tool "space_unit_reload"
      "Reload a unit to reflect its current source state."
      {:unit_id {:type "string" :description "The unit identifier."}}
      (fn [args]
        (json.dumps (service:reload args)))))

  ;; space_unit_read_log — read application log
  (registry:register
    (def-tool "space_unit_read_log"
      "Read recent lines from the application log with optional filtering and pagination."
      {:grep {:type "string" :description "Filter lines containing this substring."}
       :lines {:type "integer" :description "Number of recent lines to return."}
       :offset {:type "integer" :description "Line offset from the beginning."}
       :limit {:type "integer" :description "Maximum number of lines to return."}}
      (fn [args]
        (json.dumps (service:read-log args)))))

  ;; space_unit_snapshot — snapshot a unit's state
  (registry:register
    (def-tool "space_unit_snapshot"
      "Capture a snapshot of a unit's current state for later restoration."
      {:unit_id {:type "string" :description "The unit identifier."}}
      (fn [args]
        (json.dumps (service:snapshot args)))))

  registry)

{:make-tool-registry make-tool-registry
 :register-tools register-tools}
