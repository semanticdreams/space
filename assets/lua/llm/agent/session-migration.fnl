(local fs (require :fs))
(local json (require :json))
(local WorkflowTemplate (require :llm/agent/workflow-template))
(local WorkflowEvents (require :llm/agent/workflow-events))

(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn array-or-empty [value]
  (if (= value nil) [] value))

(fn deep-copy [value]
  (if (not (= (type value) "table"))
      value
      (do
        (local out {})
        (each [k v (pairs value)]
          (tset out k (deep-copy v)))
        out)))

(fn legacy-sessions-dir [base-dir]
  (fs.join-path base-dir "agent-sessions"))

(fn archive-root [base-dir]
  (fs.join-path base-dir "agent-sessions-archive"))

(fn archive-dir [base-dir timestamp]
  (fs.join-path (archive-root base-dir) (tostring timestamp)))

(fn json-session-file? [entry]
  (and entry entry.is-file entry.name (string.match entry.name "%.json$")))

(fn session-files [base-dir]
  (local dir (legacy-sessions-dir base-dir))
  (local files [])
  (when (fs.exists dir)
    (each [_ entry (ipairs (fs.list-dir dir false))]
      (when (json-session-file? entry)
        (table.insert files {:name entry.name :path entry.path}))))
  (table.sort files (fn [a b] (< a.name b.name)))
  files)

(fn read-legacy-session [file]
  (local (read-ok content) (pcall fs.read-file file.path))
  (when (not read-ok)
    (error (.. "failed to read legacy agent session " file.path ": " (tostring content))))
  (local (parse-ok session) (pcall json.loads content))
  (when (not parse-ok)
    (error (.. "failed to parse legacy agent session " file.path ": " (tostring session))))
  (assert (= (type session) "table") (.. "legacy agent session must be an object: " file.path))
  session)

(fn validate-legacy-session [session file]
  (assert (= (type session.id) "string") (.. "legacy agent session requires string :id: " file.path))
  (assert (= (type session.agent-id) "string") (.. "legacy agent session requires string :agent-id: " file.path))
  (assert session.status (.. "legacy agent session requires :status: " file.path))
  (assert (= (type session.items) "table") (.. "legacy agent session requires :items array: " file.path))
  (assert (= (type session.data) "table") (.. "legacy agent session requires :data object: " file.path))
  (assert session.created-at (.. "legacy agent session requires :created-at: " file.path))
  (assert session.updated-at (.. "legacy agent session requires :updated-at: " file.path))
  (each [idx item (ipairs (array-or-empty session.items))]
    (assert (= (type item) "table") (.. "legacy agent session item must be an object at index " idx ": " file.path))
    (assert (= (type item.id) "string") (.. "legacy agent session item requires string :id at index " idx ": " file.path)))
  session)

(fn find-existing-run [workflow-store legacy-id]
  (var found nil)
  (each [_ run (ipairs (workflow-store:list-runs {:definition-id WorkflowTemplate.definition-id}))]
    (when (and (not found)
               run.context
               (= run.context.legacy-agent-session-id legacy-id))
      (set found run)))
  found)

(fn projected-matches-legacy? [projected legacy]
  (var matches true)
  (when (not (= projected.agent-id legacy.agent-id))
    (set matches false))
  (assert (= (type projected.items) "table") "projected migration session requires :items")
  (assert (= (type legacy.items) "table") "legacy migration session requires :items")
  (when (not (= (length projected.items) (length legacy.items)))
    (set matches false))
  (each [idx item (ipairs legacy.items)]
    (local projected-item (. projected.items idx))
    (when (or (not projected-item)
              (not (= projected-item.id item.id)))
      (set matches false)))
  matches)

(fn ensure-existing-run-compatible [run legacy]
  (local projected (WorkflowEvents.project-session run))
  (when (not (projected-matches-legacy? projected legacy))
    (error (.. "existing workflow run does not match legacy agent session: " legacy.id)))
  run)

(fn migration-context [legacy]
  (local context {:kind :agent-session
                  :agent-session? true
                  :agent-id legacy.agent-id
                  :status legacy.status
                  :data (deep-copy legacy.data)})
  (tset context :legacy-agent-session-id legacy.id)
  context)

(fn append-legacy-events! [workflow-store run-id legacy]
  (WorkflowEvents.append-session-created workflow-store run-id {:agent-id legacy.agent-id
                                                                :legacy-agent-session-id legacy.id
                                                                :data (deep-copy legacy.data)
                                                                :created-at legacy.created-at})
  (each [_ item (ipairs (array-or-empty legacy.items))]
    (WorkflowEvents.append-item workflow-store run-id (deep-copy item)))
  (WorkflowEvents.append-status workflow-store run-id legacy.status {:created-at legacy.updated-at}))

(fn create-workflow-run! [opts legacy]
  (WorkflowTemplate.ensure-definition {:workflow-store opts.workflow-store
                                       :code-store opts.code-store
                                       :agent-id legacy.agent-id})
  (local run (opts.workflow-runner:start-run WorkflowTemplate.definition-id {} (migration-context legacy)))
  (opts.workflow-store:update-run run.id {:created-at legacy.created-at})
  (append-legacy-events! opts.workflow-store run.id legacy)
  (opts.workflow-runner:tick-run run.id {:max-steps 1})
  (assert (opts.workflow-store:get-run run.id) (.. "migrated workflow run was not durable: " run.id))
  (opts.workflow-store:get-run run.id))

(fn archive-file! [base-dir archive-dir-path file]
  (when (not (fs.exists (archive-root base-dir)))
    (fs.create-dirs (archive-root base-dir)))
  (when (not (fs.exists archive-dir-path))
    (fs.create-dirs archive-dir-path))
  (local target (fs.join-path archive-dir-path file.name))
  (local (ok err) (pcall fs.rename file.path target))
  (when (not ok)
    (error (.. "failed to archive legacy agent session " file.path " to " target ": " (tostring err))))
  target)

(fn migrate-file! [opts result archive-dir-path file]
  (local legacy (validate-legacy-session (read-legacy-session file) file))
  (local existing (find-existing-run opts.workflow-store legacy.id))
  (local run (if existing
                 (ensure-existing-run-compatible existing legacy)
                 (do
                   (local created (create-workflow-run! opts legacy))
                   (set result.migrated (+ result.migrated 1))
                   created)))
  (tset result.mapping legacy.id run.id)
  (archive-file! opts.base-dir archive-dir-path file)
  (set result.archived (+ result.archived 1))
  result)

(fn assert-opts [opts]
  (local options (table-or-empty opts))
  (assert options.base-dir "SessionMigration.migrate requires :base-dir")
  (assert options.workflow-store "SessionMigration.migrate requires :workflow-store")
  (assert options.workflow-runner "SessionMigration.migrate requires :workflow-runner")
  (assert options.code-store "SessionMigration.migrate requires :code-store")
  options)

(fn migrate [opts]
  (local options (assert-opts opts))
  (local archive-dir-path (archive-dir options.base-dir (os.time)))
  (local result {:migrated 0
                 :archived 0
                 :mapping {}
                 :archive-dir archive-dir-path})
  (each [_ file (ipairs (session-files options.base-dir))]
    (migrate-file! options result archive-dir-path file))
  result)

{:migrate migrate}
