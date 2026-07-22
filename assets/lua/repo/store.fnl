(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))

(fn ensure-dir [path]
  (when (not (fs.exists path))
    (fs.create-dirs path)))

(fn assert-task-id [task-id]
  (assert (= (type task-id) "string") "task-id must be a string")
  (assert (string.match task-id "^task%-[%w%-]+$")
          (.. "task-id must match generated format: " (tostring task-id))))

(fn Store [data-dir]
  (assert data-dir "Store requires :data-dir")
  (ensure-dir data-dir)
  (local registry-path (fs.join-path data-dir "registry.json"))
  (local tasks-dir (fs.join-path data-dir "tasks"))
  (ensure-dir tasks-dir)

  (fn registry-path* []
    registry-path)

  (fn task-path [task-id]
    (assert-task-id task-id)
    (fs.join-path tasks-dir (.. task-id ".json")))

  (fn load-registry []
    (if (not (fs.exists registry-path))
        {}
        (do
          (local parsed (json.loads (fs.read-file registry-path)))
          (assert (= (type parsed) "table") "repository registry must be a JSON object")
          parsed)))

  (fn save-registry [registry]
    (JsonUtils.write-json! registry-path registry)
    true)

  (fn get-repo [self repo-id]
    (. (load-registry) repo-id))

  (fn add-repo [self repo-data]
    (local registry (load-registry))
    (local repo-id repo-data.id)
    (tset registry repo-id repo-data)
    (save-registry registry)
    repo-data)

  (fn list-repos [self]
    (local registry (load-registry))
    (local result [])
    (each [_ repo-data (pairs registry)]
      (table.insert result repo-data))
    result)

  (fn task-exists? [self task-id]
    (fs.exists (task-path task-id)))

  (fn load-task [self task-id]
    (local path (task-path task-id))
    (when (fs.exists path)
      (local parsed (json.loads (fs.read-file path)))
      (assert (= (type parsed) "table") (.. "task " task-id " must be a JSON object"))
      parsed))

  (fn save-task [self task-data]
    (local task-id task-data.id)
    (JsonUtils.write-json! (task-path task-id) task-data)
    task-data)

  (fn list-tasks [self repo-id]
    (local result [])
    (each [entry (fs.list-dir tasks-dir)]
      (when (and entry.is-file (string.match entry.name "^task%-.+%.json$"))
        (local task (load-task self (string.sub entry.name 1 (- (# entry.name) 5))))
        (when (and task (= task.repo-id repo-id))
          (table.insert result task))))
    result)

  (fn delete-task [self task-id]
    (local path (task-path task-id))
    (when (fs.exists path)
      (fs.remove path)))

  {:registry-path registry-path*
   :get-repo get-repo
   :add-repo add-repo
   :list-repos list-repos
   :task-exists? task-exists?
   :load-task load-task
   :save-task save-task
   :list-tasks list-tasks
   :delete-task delete-task})

{:Store Store}
