(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local JsonUtils (require :json-utils))

(fn ensure-dir [path]
  (when (and path fs fs.create-dirs)
    (pcall (fn [] (fs.create-dirs path))))
  path)

(fn normalize-target-key [value]
  (if (or (= value nil) (= value :nil))
      ""
      (tostring value)))

(fn normalize-metadata [value]
  (if (= (type value) :table)
      value
      {}))

(fn keys-equal? [left right]
  (= (tostring (or left "")) (tostring (or right ""))))

(fn IdentityStore [opts]
  (local options (or opts {}))
  (local base-dir (or options.base-dir
                      (and appdirs (appdirs.user-data-dir "space"))))
  (local root (and base-dir fs (fs.join-path base-dir "entities")))
  (local entities-dir (and root fs (fs.join-path root "identity")))
  (ensure-dir entities-dir)

  (local cache {})

  (local identity-created (Signal))
  (local identity-updated (Signal))
  (local identity-deleted (Signal))

  (fn entity-path [id]
    (and entities-dir (fs.join-path entities-dir (.. (tostring id) ".json"))))

  (fn read-entity [path]
    (when (and path fs fs.exists (fs.exists path))
      (local (ok content) (pcall fs.read-file path))
      (when ok
        (local (parse-ok data) (pcall json.loads content))
        (when parse-ok
          {:id (tostring (or data.id ""))
           :target-key (normalize-target-key data.target-key)
           :created-at (tonumber (or data.created-at 0))
           :updated-at (tonumber (or data.updated-at 0))
           :metadata (normalize-metadata data.metadata)}))))

  (fn write-entity [entity]
    (when entity
      (local path (entity-path entity.id))
      (when path
        (ensure-dir entities-dir)
        (local data {:id (tostring entity.id)
                     :target-key (normalize-target-key entity.target-key)
                     :created-at entity.created-at
                     :updated-at entity.updated-at
                     :metadata (normalize-metadata entity.metadata)})
        (JsonUtils.write-json! path data)))
    entity)

  (fn load-entity [id]
    (local key (tostring id))
    (if (. cache key)
        (. cache key)
        (do
          (local data (read-entity (entity-path key)))
          (when data
            (set (. cache key) data))
          data)))

  (fn get-entity [_self id]
    (if id (load-entity id) nil))

  (fn create-entity [_self opts]
    (local create-opts (or opts {}))
    (local id (tostring (or create-opts.id (Uuid.v4))))
    (local now (os.time))
    (local entity {:id id
                   :target-key (normalize-target-key create-opts.target-key)
                   :created-at (or create-opts.created-at now)
                   :updated-at (or create-opts.updated-at now)
                   :metadata (normalize-metadata create-opts.metadata)})
    (set (. cache id) entity)
    (write-entity entity)
    (identity-created:emit entity)
    entity)

  (fn apply-updates! [entity updates]
    (var changed? false)
    (each [k v (pairs (or updates {}))]
      (local current (. entity k))
      (local next-value
        (if (or (= k :target-key) (= k "target-key"))
            (normalize-target-key v)
            (if (or (= k :metadata) (= k "metadata"))
                (normalize-metadata v)
                v)))
      (when (not (= current next-value))
        (set changed? true)
        (set (. entity k) next-value)))
    changed?)

  (fn update-entity [_self id updates]
    (local entity (load-entity id))
    (when entity
      (local changed? (apply-updates! entity updates))
      (when changed?
        (set entity.updated-at (os.time))
        (write-entity entity)
        (identity-updated:emit entity)))
    entity)

  (fn delete-entity [_self id]
    (local entity (load-entity id))
    (when entity
      (local path (entity-path id))
      (when (and path fs fs.remove (fs.exists path))
        (pcall (fn [] (fs.remove path))))
      (set (. cache (tostring id)) nil)
      (identity-deleted:emit entity))
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
                  (> (or a.updated-at 0) (or b.updated-at 0))))
    items)

  (fn find-by-target-key [_self target-key]
    (local target (tostring (or target-key "")))
    (if (= (string.len target) 0)
        nil
        (do
          (local matches [])
          (each [_ entity (ipairs (list-entities _self))]
            (when (keys-equal? entity.target-key target)
              (table.insert matches entity)))
          (. matches 1))))

  {:base-dir base-dir
   :root root
   :entities-dir entities-dir
   :identity-created identity-created
   :identity-updated identity-updated
   :identity-deleted identity-deleted
   :get-entity get-entity
   :create-entity create-entity
   :update-entity update-entity
   :delete-entity delete-entity
   :list-entities list-entities
   :find-by-target-key find-by-target-key})

(var default-store nil)

(fn get-default [opts]
  (if default-store
      default-store
      (do
        (set default-store (IdentityStore (or opts {})))
        default-store)))

{:IdentityStore IdentityStore
 :get-default get-default}
