(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))

(fn ensure-dir [path]
  (when (and path fs fs.create-dirs)
    (pcall (fn [] (fs.create-dirs path))))
  path)

(fn LinkEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (or options.base-dir
                      (and appdirs (appdirs.user-data-dir "space"))))
  (local root (and base-dir fs (fs.join-path base-dir "entities")))
  (local entities-dir (and root fs (fs.join-path root "link")))
  (ensure-dir entities-dir)

  (local cache {})

  (local link-entity-created (Signal))
  (local link-entity-updated (Signal))
  (local link-entity-deleted (Signal))

  (fn entity-path [id]
    (and entities-dir (fs.join-path entities-dir (.. (tostring id) ".json"))))

  (fn read-entity [path]
    (when (and path fs fs.exists (fs.exists path))
      (local (ok content) (pcall fs.read-file path))
      (when ok
        (local (parse-ok data) (pcall json.loads content))
        (when parse-ok
          {:id (or data.id "")
           :source-key (or data.source-key "")
           :target-key (or data.target-key "")
           :created-at (tonumber (or data.created-at 0))
           :metadata (or data.metadata {})}))))

  (fn write-entity [entity]
    (when entity
      (local path (entity-path entity.id))
      (when path
        (ensure-dir entities-dir)
        (local data {:id entity.id
                     :source-key entity.source-key
                     :target-key entity.target-key
                     :created-at entity.created-at
                     :metadata entity.metadata})
        (local content (json.dumps data))
        (fs.write-file path content)))
    entity)

  (fn load-entity [id]
    (local key (tostring id))
    (if (. cache key)
        (. cache key)
        (let [data (read-entity (entity-path key))]
          (when data
            (set (. cache key) data))
          data)))

  (fn get-entity [_self id]
    (if id (load-entity id) nil))

  (fn create-entity [_self opts]
    (local options (or opts {}))
    (local id (tostring (or options.id (Uuid.v4))))
    (local now (os.time))
    (local entity {:id id
                   :source-key (or options.source-key "")
                   :target-key (or options.target-key "")
                   :created-at (or options.created-at now)
                   :metadata (or options.metadata {})})
    (set (. cache id) entity)
    (write-entity entity)
    (link-entity-created:emit entity)
    entity)

  (fn update-entity [_self id updates]
    (local entity (load-entity id))
    (when entity
      (each [k v (pairs (or updates {}))]
        (set (. entity k) v))
      (write-entity entity)
      (link-entity-updated:emit entity))
    entity)

  (fn delete-entity [_self id]
    (local entity (load-entity id))
    (when entity
      (local path (entity-path id))
      (when (and path fs fs.remove (fs.exists path))
        (pcall (fn [] (fs.remove path))))
      (set (. cache (tostring id)) nil)
      (link-entity-deleted:emit entity))
    entity)

  (fn list-entities [_self]
    (local items [])
    (when (and entities-dir fs fs.list-dir (fs.exists entities-dir))
      (local (ok entries) (pcall fs.list-dir entities-dir false))
      (when ok
        (each [_ entry (ipairs (or entries []))]
          (when (and entry entry.is-file entry.name (string.match entry.name "%.json$"))
            (local data (read-entity entry.path))
            (when data
              (set (. cache (tostring data.id)) data)
              (table.insert items data))))))
    (table.sort items
                (fn [a b]
                  (> (or a.created-at 0) (or b.created-at 0))))
    items)

  (fn find-edges-for-nodes [_self node-keys]
    (local key-set {})
    (each [_ k (ipairs (or node-keys []))]
      (set (. key-set (tostring k)) true))
    (local results [])
    (when (and entities-dir fs fs.list-dir (fs.exists entities-dir))
      (local (ok entries) (pcall fs.list-dir entities-dir false))
      (when ok
        (each [_ entry (ipairs (or entries []))]
          (when (and entry entry.is-file entry.name (string.match entry.name "%.json$"))
            (local data (read-entity entry.path))
            (when (and data
                       (. key-set (tostring data.source-key))
                       (. key-set (tostring data.target-key)))
              (set (. cache (tostring data.id)) data)
              (table.insert results data))))))
    results)

  (fn find-entities-for-key [_self key]
    (local key-str (tostring key))
    (local results [])
    (when (and entities-dir fs fs.list-dir (fs.exists entities-dir))
      (local (ok entries) (pcall fs.list-dir entities-dir false))
      (when ok
        (each [_ entry (ipairs (or entries []))]
          (when (and entry entry.is-file entry.name (string.match entry.name "%.json$"))
            (local data (read-entity entry.path))
            (when (and data
                       (or (= (tostring data.source-key) key-str)
                           (= (tostring data.target-key) key-str)))
              (set (. cache (tostring data.id)) data)
              (table.insert results data))))))
    results)

  {:base-dir base-dir
   :root root
   :entities-dir entities-dir
   :link-entity-created link-entity-created
   :link-entity-updated link-entity-updated
   :link-entity-deleted link-entity-deleted
   :get-entity get-entity
   :create-entity create-entity
   :update-entity update-entity
   :delete-entity delete-entity
   :list-entities list-entities
   :find-edges-for-nodes find-edges-for-nodes
   :find-entities-for-key find-entities-for-key})

(var default-store nil)

(fn get-default [opts]
  (if default-store
      default-store
      (do
        (set default-store (LinkEntityStore (or opts {})))
        default-store)))

{:LinkEntityStore LinkEntityStore
 :get-default get-default}
