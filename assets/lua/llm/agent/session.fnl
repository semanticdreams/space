;; Agent session persistence — in-memory cache backed by JSON files.
;; Session shape: {:id :agent-id :status :items [] :data {} :created-at :updated-at}
;; Item types: message, tool-call, tool-result, event, error

(local fs (require :fs))
(local json (require :json))
(local Uuid (require :uuid))
(local JsonUtils (require :json-utils))

(var cache {})

(fn new-id []
  (.. "agt-ses-" (Uuid.v4)))

(fn session-path [id data-dir]
  (fs.join-path data-dir (.. id ".json")))

(fn now []
  (os.time))

(fn default-session [agent-id data-dir]
  {:id (new-id)
   :agent-id agent-id
   :status :idle
   :items []
   :data {}
   :created-at (now)
   :updated-at (now)})

(fn validate-item [item]
  (assert (= (type item) "table") "item must be a table")
  (assert (= (type item.type) "string") "item must have a string type")
  (assert (= (type item.id) "string") "item must have a string id"))

(fn save-session [session data-dir]
  (set session.updated-at (now))
  (JsonUtils.write-json! (session-path session.id data-dir) session)
  session)

(fn create-session [agent-id data-dir]
  (assert (= (type agent-id) "string") "agent-id must be a string")
  (assert (= (type data-dir) "string") "data-dir must be a string")
  (when (not (fs.exists data-dir))
    (fs.create-dirs data-dir))
  (local session (default-session agent-id data-dir))
  (tset cache session.id session)
  (save-session session data-dir)
  session)

(fn load-session [id data-dir]
  (assert (= (type id) "string") "session id must be a string")
  (if (. cache id)
      (. cache id)
      (do
        (local path (session-path id data-dir))
        (if (not (fs.exists path))
            nil
            (do
              (local (ok content) (pcall fs.read-file path))
              (when (not ok)
                (error (.. "failed to read agent session '" id "': " (tostring content))))
              (local (parse-ok session) (pcall json.loads content))
              (when (not parse-ok)
                (error (.. "failed to parse agent session '" id "': " (tostring session))))
              (tset cache id session)
              session)))))

(fn delete-session [id data-dir]
  (tset cache id nil)
  (local path (session-path id data-dir))
  (when (fs.exists path)
    (fs.remove path)))

(fn session-summary [session]
  {:id session.id
   :agent-id session.agent-id
   :status session.status
   :item-count (length (or session.items []))
   :created-at session.created-at
   :updated-at session.updated-at})

(fn read-session-file [path label]
  (local (ok content) (pcall fs.read-file path))
  (when (not ok)
    (error (.. "failed to read agent session " label ": " (tostring content))))
  (local (parse-ok session) (pcall json.loads content))
  (when (not parse-ok)
    (error (.. "failed to parse agent session " label ": " (tostring session))))
  session)

(fn list-sessions [data-dir]
  (if (not (fs.exists data-dir))
      []
      (do
        (local entries (fs.list-dir data-dir))
        (local result [])
        (each [_ entry (ipairs entries)]
          (when (and entry.is-file (string.match entry.name "%.json$"))
            (local session-id (string.match entry.name "^(.-)%.json$"))
            (local cached (. cache session-id))
            (if cached
                (table.insert result (session-summary cached))
                (do
                  (local path (fs.join-path data-dir entry.name))
                  (local session (read-session-file path (.. "list entry '" entry.name "'")))
                  (table.insert result (session-summary session))))))
        result)))

(fn append-item [session item]
  (validate-item item)
  (when (not item.created-at)
    (tset item :created-at (now)))
  (table.insert session.items item)
  session)

(fn update-session [session updates]
  (each [k v (pairs (or updates {}))]
    (tset session k v))
  session)

(fn invalidate-cache [id]
  (tset cache id nil))

{:create-session create-session
 :load-session load-session
 :save-session save-session
 :delete-session delete-session
 :list-sessions list-sessions
 :append-item append-item
 :update-session update-session
 :invalidate-cache invalidate-cache}
