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

(fn normalize-name [value]
  (if (or (= value nil) (= value :nil))
      ""
      (tostring value)))

(fn normalize-language [value]
  (local language (if (or (= value nil) (= value :nil))
                      ""
                      (tostring value)))
  (if (> (string.len language) 0)
      language
      "fnl"))

(fn normalize-source [value]
  (if (or (= value nil) (= value :nil))
      ""
      (tostring value)))

(fn normalize-kernel [value]
  (if (or (= value nil) (= value :nil))
      0
      (if (= (type value) "number")
          value
          (do
            (local text (tostring value))
            (if (> (string.len text) 0) text 0)))))

(fn CodeEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (or options.base-dir
                      (and appdirs (appdirs.user-data-dir "space"))))
  (local root (and base-dir fs (fs.join-path base-dir "entities")))
  (local entities-dir (and root fs (fs.join-path root "code")))
  (ensure-dir entities-dir)

  (local cache {})

  (local code-entity-created (Signal))
  (local code-entity-updated (Signal))
  (local code-entity-deleted (Signal))

  (fn entity-path [id]
    (and entities-dir (fs.join-path entities-dir (.. (tostring id) ".json"))))

  (fn read-entity [path]
    (when (and path fs fs.exists (fs.exists path))
      (local (ok content) (pcall fs.read-file path))
      (when ok
        (local (parse-ok data) (pcall json.loads content))
        (when parse-ok
          {:id (tostring (or data.id ""))
           :name (normalize-name data.name)
           :language (normalize-language data.language)
           :source (normalize-source data.source)
           :kernel (normalize-kernel data.kernel)
           :created-at (tonumber (or data.created-at 0))
           :updated-at (tonumber (or data.updated-at 0))}))))

  (fn write-entity [entity]
    (when entity
      (local path (entity-path entity.id))
      (when path
        (ensure-dir entities-dir)
        (local data {:id (tostring entity.id)
                     :name (normalize-name entity.name)
                     :language (normalize-language entity.language)
                     :source (normalize-source entity.source)
                     :kernel (normalize-kernel entity.kernel)
                     :created-at entity.created-at
                     :updated-at entity.updated-at})
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
                   :name (normalize-name create-opts.name)
                   :language (normalize-language create-opts.language)
                   :source (normalize-source create-opts.source)
                   :kernel (normalize-kernel create-opts.kernel)
                   :created-at (or create-opts.created-at now)
                   :updated-at (or create-opts.updated-at now)})
    (set (. cache id) entity)
    (write-entity entity)
    (code-entity-created:emit entity)
    entity)

  (fn apply-updates! [entity updates]
    (var changed? false)
    (each [k v (pairs (or updates {}))]
      (local current (. entity k))
      (local next-value
        (if (or (= k :name) (= k "name"))
            (normalize-name v)
            (if (or (= k :language) (= k "language"))
                (normalize-language v)
                (if (or (= k :source) (= k "source"))
                    (normalize-source v)
                    (if (or (= k :kernel) (= k "kernel"))
                        (normalize-kernel v)
                        v)))))
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
        (code-entity-updated:emit entity)))
    entity)

  (fn delete-entity [_self id]
    (local entity (load-entity id))
    (when entity
      (local path (entity-path id))
      (when (and path fs fs.remove (fs.exists path))
        (pcall (fn [] (fs.remove path))))
      (set (. cache (tostring id)) nil)
      (code-entity-deleted:emit entity))
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

  {:base-dir base-dir
   :root root
   :entities-dir entities-dir
   :code-entity-created code-entity-created
   :code-entity-updated code-entity-updated
   :code-entity-deleted code-entity-deleted
   :get-entity get-entity
   :create-entity create-entity
   :update-entity update-entity
   :delete-entity delete-entity
   :list-entities list-entities})

(var default-store nil)

(fn get-default [opts]
  (if default-store
      default-store
      (do
        (set default-store (CodeEntityStore (or opts {})))
        default-store)))

{:CodeEntityStore CodeEntityStore
 :get-default get-default}
