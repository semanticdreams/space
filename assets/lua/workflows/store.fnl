(local fs (require :fs))
(local json (require :json))
(local appdirs (require :appdirs))
(local Uuid (require :uuid))
(local Signal (require :signal))
(local JsonUtils (require :json-utils))

(fn ensure-dir [path]
  (assert path "ensure-dir requires path")
  (when (not (fs.exists path))
    (fs.create-dirs path))
  path)

(fn now []
  (os.time))

(fn value-or [value default]
  (if (= value nil)
      default
      value))

(fn table-or-empty [value]
  (if (= value nil)
      {}
      value))

(fn array-or-empty [value]
  (if (= value nil)
      []
      value))

(fn prefixed-id [prefix value]
  (assert prefix "prefixed-id requires prefix")
  (if (= value nil)
      (.. prefix (Uuid.v4))
      (tostring value)))

(fn copy-array [items]
  (local source (array-or-empty items))
  (local out [])
  (each [_ item (ipairs source)]
    (table.insert out item))
  out)

(fn table-values [tbl]
  (local source (table-or-empty tbl))
  (local out [])
  (each [_ item (pairs source)]
    (table.insert out item))
  out)

(fn find-by-id [items id]
  (local source (array-or-empty items))
  (var found nil)
  (each [_ item (ipairs source)]
    (when (and (not found) (= item.id id))
      (set found item)))
  found)

(fn remove-by-id! [items id]
  (local source (array-or-empty items))
  (var removed nil)
  (var idx (length source))
  (while (> idx 0)
    (local item (. source idx))
    (when (= item.id id)
      (set removed item)
      (table.remove source idx))
    (set idx (- idx 1)))
  removed)

(fn dependent-edge? [edge step-id]
  (if (= edge.source-step-id step-id)
      true
      (= edge.target-step-id step-id)
      true
      false))

(fn apply-updates! [record updates]
  (local changes (table-or-empty updates))
  (each [k v (pairs changes)]
    (set (. record k) v))
  record)

(fn reject-update-key [updates key message]
  (when (not (= (. (table-or-empty updates) key) nil))
    (error message)))

(fn validate-definition-updates [updates]
  (reject-update-key updates :id "update-definition cannot change :id")
  (reject-update-key updates :steps "update-definition cannot change :steps")
  (reject-update-key updates :edges "update-definition cannot change :edges"))

(fn validate-step-updates [updates]
  (local changes (table-or-empty updates))
  (reject-update-key changes :id "update-step cannot change :id")
  (when (= changes.code-entity-id false)
    (error "workflow step requires :code-entity-id")))

(fn normalize-definition [definition]
  (local data (table-or-empty definition))
  {:id (tostring data.id)
   :name (tostring (value-or data.name ""))
   :description (tostring (value-or data.description ""))
   :version (tonumber (value-or data.version 1))
   :status (value-or data.status :draft)
   :parameters (table-or-empty data.parameters)
   :steps (array-or-empty data.steps)
   :edges (array-or-empty data.edges)
   :created-at (tonumber (value-or data.created-at 0))
   :updated-at (tonumber (value-or data.updated-at 0))})

(fn normalize-step [step id]
  (local data (table-or-empty step))
  (assert data.code-entity-id "workflow step requires :code-entity-id")
  {:id (prefixed-id "step-" (value-or id data.id))
   :name (tostring (value-or data.name ""))
   :code-entity-id (tostring data.code-entity-id)
   :config (table-or-empty data.config)
   :input-schema (table-or-empty data.input-schema)
   :output-schema (table-or-empty data.output-schema)
   :retry (value-or data.retry {:max-attempts 0})
   :timeout-ms data.timeout-ms})

(fn normalize-edge [edge id]
  (local data (table-or-empty edge))
  (assert data.source-step-id "workflow edge requires :source-step-id")
  (assert data.target-step-id "workflow edge requires :target-step-id")
  {:id (prefixed-id "edge-" (value-or id data.id))
   :kind (value-or data.kind :control)
   :source-step-id (tostring data.source-step-id)
   :target-step-id (tostring data.target-step-id)
   :condition data.condition
   :source-port data.source-port
   :target-port data.target-port})

(fn normalize-steps [steps]
  (local out [])
  (each [_ step (ipairs (array-or-empty steps))]
    (table.insert out (normalize-step step step.id)))
  out)

(fn normalize-edges [edges]
  (local out [])
  (each [_ edge (ipairs (array-or-empty edges))]
    (table.insert out (normalize-edge edge edge.id)))
  out)

(fn normalize-run [run]
  (local data (table-or-empty run))
  {:id (tostring data.id)
   :definition-id (tostring data.definition-id)
   :definition-version (tonumber (value-or data.definition-version 1))
   :status (value-or data.status :queued)
   :input (table-or-empty data.input)
   :output (table-or-empty data.output)
   :context (table-or-empty data.context)
   :current-step-ids (array-or-empty data.current-step-ids)
   :created-at (tonumber (value-or data.created-at 0))
   :started-at data.started-at
   :finished-at data.finished-at
   :error data.error
   :steps (table-or-empty data.steps)
   :events (array-or-empty data.events)})

(fn new-run-step [run-id step-id]
  {:run-id run-id
   :step-id step-id
   :status :pending
   :attempt 0
   :input {}
   :output {}
   :state {}
   :wait nil
   :started-at nil
   :finished-at nil
   :error nil})

(fn normalize-run-step [run-id step-id updates current]
  (local base (if (= current nil) (new-run-step run-id step-id) current))
  (apply-updates! base updates)
  (set base.run-id run-id)
  (set base.step-id step-id)
  base)

(fn definition-path [self definition-id]
  (fs.join-path self.definitions-dir (.. (tostring definition-id) ".json")))

(fn run-path [self run-id]
  (fs.join-path self.runs-dir (.. (tostring run-id) ".json")))

(fn read-json-record [path]
  (when (fs.exists path)
    (local parsed (json.loads (fs.read-file path)))
    (assert (= (type parsed) "table") (.. "workflow JSON record must be an object: " path))
    parsed))

(fn write-definition! [self definition]
  (ensure-dir self.definitions-dir)
  (JsonUtils.write-json! (definition-path self definition.id) definition)
  definition)

(fn write-run! [self run]
  (ensure-dir self.runs-dir)
  (JsonUtils.write-json! (run-path self run.id) run)
  run)

(fn load-definition [self definition-id]
  (local id (tostring definition-id))
  (local cached (. self._definitions id))
  (if cached
      cached
      (do
        (local record (read-json-record (definition-path self id)))
        (when record
          (local normalized (normalize-definition record))
          (set (. self._definitions id) normalized)
          normalized))))

(fn require-definition [self definition-id]
  (local definition (load-definition self definition-id))
  (if definition
      definition
      (error (.. "missing workflow definition: " (tostring definition-id)))))

(fn load-run [self run-id]
  (local id (tostring run-id))
  (local cached (. self._runs id))
  (if cached
      cached
      (do
        (local record (read-json-record (run-path self id)))
        (when record
          (local normalized (normalize-run record))
          (set (. self._runs id) normalized)
          normalized))))

(fn require-run [self run-id]
  (local run (load-run self run-id))
  (if run
      run
      (error (.. "missing workflow run: " (tostring run-id)))))

(fn require-step [definition step-id]
  (local step (find-by-id definition.steps (tostring step-id)))
  (if step
      step
      (error (.. "missing workflow step: " (tostring step-id)))))

(fn require-edge [definition edge-id]
  (local edge (find-by-id definition.edges (tostring edge-id)))
  (if edge
      edge
      (error (.. "missing workflow edge: " (tostring edge-id)))))

(fn touch-definition! [self definition]
  (set definition.updated-at (now))
  (write-definition! self definition))

(fn get-definition [self definition-id]
  (if definition-id (load-definition self definition-id) nil))

(fn list-definitions [self]
  (local items [])
  (when (fs.exists self.definitions-dir)
    (each [_ entry (ipairs (fs.list-dir self.definitions-dir false))]
      (when (and entry.is-file (string.match entry.name "%.json$"))
        (local definition (normalize-definition (read-json-record entry.path)))
        (set (. self._definitions definition.id) definition)
        (table.insert items definition))))
  (table.sort items (fn [a b] (< a.id b.id)))
  items)

(fn create-definition [self create-opts]
  (local data (table-or-empty create-opts))
  (local timestamp (now))
  (local definition (normalize-definition {:id (prefixed-id "wf-" data.id)
                                           :name data.name
                                           :description data.description
                                           :version (value-or data.version 1)
                                           :status (value-or data.status :draft)
                                           :parameters (table-or-empty data.parameters)
                                           :steps (normalize-steps data.steps)
                                           :edges (normalize-edges data.edges)
                                           :created-at (value-or data.created-at timestamp)
                                           :updated-at (value-or data.updated-at timestamp)}))
  (each [_ edge (ipairs definition.edges)]
    (require-step definition edge.source-step-id)
    (require-step definition edge.target-step-id))
  (set (. self._definitions definition.id) definition)
  (write-definition! self definition)
  (self.definition-created:emit definition)
  definition)

(fn update-definition [self definition-id updates]
  (local definition (require-definition self definition-id))
  (validate-definition-updates updates)
  (apply-updates! definition updates)
  (touch-definition! self definition)
  (self.definition-updated:emit definition)
  definition)

(fn delete-definition [self definition-id _opts]
  (local definition (require-definition self definition-id))
  (local path (definition-path self definition.id))
  (when (fs.exists path)
    (fs.remove path))
  (set (. self._definitions definition.id) nil)
  (self.definition-deleted:emit definition)
  definition)

(fn add-step [self definition-id step]
  (local definition (require-definition self definition-id))
  (local normalized (normalize-step step))
  (table.insert definition.steps normalized)
  (touch-definition! self definition)
  (self.definition-updated:emit definition)
  normalized)

(fn update-step [self definition-id step-id updates]
  (local definition (require-definition self definition-id))
  (local step (require-step definition step-id))
  (validate-step-updates updates)
  (apply-updates! step updates)
  (assert step.code-entity-id "workflow step requires :code-entity-id")
  (touch-definition! self definition)
  (self.definition-updated:emit definition)
  step)

(fn delete-dependent-edges! [definition step-id]
  (var idx (length definition.edges))
  (while (> idx 0)
    (when (dependent-edge? (. definition.edges idx) step-id)
      (table.remove definition.edges idx))
    (set idx (- idx 1))))

(fn dependent-edge-count [definition step-id]
  (var count 0)
  (each [_ edge (ipairs definition.edges)]
    (when (dependent-edge? edge step-id)
      (set count (+ count 1))))
  count)

(fn delete-step [self definition-id step-id opts]
  (local definition (require-definition self definition-id))
  (local id (tostring step-id))
  (require-step definition id)
  (when (and (> (dependent-edge-count definition id) 0)
             (not (and opts opts.delete-dependent-edges?)))
    (error (.. "workflow step has dependent edges: " id)))
  (when (and opts opts.delete-dependent-edges?)
    (delete-dependent-edges! definition id))
  (local deleted (remove-by-id! definition.steps id))
  (touch-definition! self definition)
  (self.definition-updated:emit definition)
  deleted)

(fn add-edge [self definition-id edge]
  (local definition (require-definition self definition-id))
  (local normalized (normalize-edge edge))
  (require-step definition normalized.source-step-id)
  (require-step definition normalized.target-step-id)
  (table.insert definition.edges normalized)
  (touch-definition! self definition)
  (self.definition-updated:emit definition)
  normalized)

(fn update-edge [self definition-id edge-id updates]
  (local definition (require-definition self definition-id))
  (local edge (require-edge definition edge-id))
  (apply-updates! edge updates)
  (require-step definition edge.source-step-id)
  (require-step definition edge.target-step-id)
  (touch-definition! self definition)
  (self.definition-updated:emit definition)
  edge)

(fn delete-edge [self definition-id edge-id]
  (local definition (require-definition self definition-id))
  (require-edge definition edge-id)
  (local deleted (remove-by-id! definition.edges (tostring edge-id)))
  (touch-definition! self definition)
  (self.definition-updated:emit definition)
  deleted)

(fn create-run [self definition-id input context]
  (local definition (require-definition self definition-id))
  (local timestamp (now))
  (local run (normalize-run {:id (prefixed-id "wfr-" nil)
                             :definition-id definition.id
                             :definition-version definition.version
                             :status :queued
                             :input (table-or-empty input)
                             :output {}
                             :context (table-or-empty context)
                             :current-step-ids []
                             :created-at timestamp
                             :steps {}
                             :events []}))
  (set (. self._runs run.id) run)
  (write-run! self run)
  (self.run-created:emit run)
  run)

(fn get-run [self run-id]
  (if run-id (load-run self run-id) nil))

(fn list-runs [self opts]
  (local options (table-or-empty opts))
  (local items [])
  (when (fs.exists self.runs-dir)
    (each [_ entry (ipairs (fs.list-dir self.runs-dir false))]
      (when (and entry.is-file (string.match entry.name "%.json$"))
        (local run (normalize-run (read-json-record entry.path)))
        (set (. self._runs run.id) run)
        (when (if (= options.definition-id nil)
                  true
                  (= run.definition-id options.definition-id))
          (table.insert items run)))))
  (table.sort items (fn [a b] (< a.id b.id)))
  items)

(fn update-run [self run-id updates]
  (local run (require-run self run-id))
  (apply-updates! run updates)
  (write-run! self run)
  (self.run-updated:emit run)
  run)

(fn upsert-run-step [self run-id step-id updates]
  (local run (require-run self run-id))
  (local definition (require-definition self run.definition-id))
  (require-step definition step-id)
  (local id (tostring step-id))
  (local run-step (normalize-run-step run.id id updates (. run.steps id)))
  (set (. run.steps id) run-step)
  (write-run! self run)
  (self.run-step-updated:emit run-step)
  run-step)

(fn get-run-step [self run-id step-id]
  (local run (if run-id (load-run self run-id) nil))
  (if run
      (. run.steps (tostring step-id))
      nil))

(fn list-run-steps [self run-id]
  (local run (require-run self run-id))
  (local items (table-values run.steps))
  (table.sort items (fn [a b] (< a.step-id b.step-id)))
  items)

(fn append-event [self run-id event]
  (local run (require-run self run-id))
  (local data (table-or-empty event))
  (local record {})
  (apply-updates! record data)
  (set record.id (prefixed-id "event-" data.id))
  (set record.run-id run.id)
  (set record.created-at (value-or data.created-at (now)))
  (table.insert run.events record)
  (write-run! self run)
  (self.event-appended:emit record)
  record)

(fn list-events [self run-id]
  (local run (require-run self run-id))
  (copy-array run.events))

(fn WorkflowStore [opts]
  (local options (table-or-empty opts))
  (assert options.base-dir "WorkflowStore requires :base-dir")
  (local root-dir (fs.join-path options.base-dir "workflows"))
  (local definitions-dir (fs.join-path root-dir "definitions"))
  (local runs-dir (fs.join-path root-dir "runs"))
  (ensure-dir definitions-dir)
  (ensure-dir runs-dir)
  {:base-dir options.base-dir
   :root-dir root-dir
   :definitions-dir definitions-dir
   :runs-dir runs-dir
   :_definitions {}
   :_runs {}
   :definition-created (Signal)
   :definition-updated (Signal)
   :definition-deleted (Signal)
   :run-created (Signal)
   :run-updated (Signal)
   :run-step-updated (Signal)
   :event-appended (Signal)
   :create-definition create-definition
   :get-definition get-definition
   :list-definitions list-definitions
   :update-definition update-definition
   :delete-definition delete-definition
   :add-step add-step
   :update-step update-step
   :delete-step delete-step
   :add-edge add-edge
   :update-edge update-edge
   :delete-edge delete-edge
   :create-run create-run
   :get-run get-run
   :list-runs list-runs
   :update-run update-run
   :upsert-run-step upsert-run-step
   :get-run-step get-run-step
   :list-run-steps list-run-steps
   :append-event append-event
   :list-events list-events})

(var default-store nil)

(fn get-default [opts]
  (if default-store
      default-store
      (do
        (local options (table-or-empty opts))
        (local base-dir (or options.base-dir
                            (and appdirs (appdirs.user-data-dir "space"))))
        (assert base-dir "WorkflowStore.get-default requires app user data dir")
        (set default-store (WorkflowStore {:base-dir base-dir}))
        default-store)))

{:WorkflowStore WorkflowStore
 :get-default get-default}
