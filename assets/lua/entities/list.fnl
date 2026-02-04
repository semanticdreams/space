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

(fn normalize-items [items]
  (local seen {})
  (local out [])
  (each [_ value (ipairs (or items []))]
    (local key (tostring value))
    (when (and key (> (string.len key) 0) (not (. seen key)))
      (set (. seen key) true)
      (table.insert out key)))
  out)

(fn items-equal? [a b]
  (local left (or a []))
  (local right (or b []))
  (if (not (= (length left) (length right)))
      false
      (do
        (var same? true)
        (for [i 1 (length left)]
          (when (not (= (. left i) (. right i)))
            (set same? false)))
        same?)))

(fn contains-item? [items value]
  (var found? false)
  (each [_ existing (ipairs (or items []))]
    (when (= existing value)
      (set found? true)))
  found?)

(fn ListEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (or options.base-dir
                      (and appdirs (appdirs.user-data-dir "space"))))
  (local root (and base-dir fs (fs.join-path base-dir "entities")))
  (local entities-dir (and root fs (fs.join-path root "list")))
  (ensure-dir entities-dir)

  (local cache {})

  (local list-entity-created (Signal))
  (local list-entity-updated (Signal))
  (local list-entity-deleted (Signal))
  (local list-entity-items-changed (Signal))

  (fn entity-path [id]
    (and entities-dir (fs.join-path entities-dir (.. (tostring id) ".json"))))

  (fn read-entity [path]
    (when (and path fs fs.exists (fs.exists path))
      (local (ok content) (pcall fs.read-file path))
      (when ok
        (local (parse-ok data) (pcall json.loads content))
        (when parse-ok
          (local items (normalize-items (or data.items [])))
          {:id (or data.id "")
           :name (or data.name "")
           :items items
           :created-at (tonumber (or data.created-at 0))
           :updated-at (tonumber (or data.updated-at 0))}))))

  (fn write-entity [entity]
    (when entity
      (local path (entity-path entity.id))
      (when path
        (ensure-dir entities-dir)
        (local data {:id entity.id
                     :name entity.name
                     :items (normalize-items entity.items)
                     :created-at entity.created-at
                     :updated-at entity.updated-at})
        (JsonUtils.write-json! path data)))
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
    (local create-opts (or opts {}))
    (local id (tostring (or create-opts.id (Uuid.v4))))
    (local now (os.time))
    (local entity {:id id
                   :name (or create-opts.name "")
                   :items (normalize-items (or create-opts.items []))
                   :created-at (or create-opts.created-at now)
                   :updated-at (or create-opts.updated-at now)})
    (set (. cache id) entity)
    (write-entity entity)
    (list-entity-created:emit entity)
    entity)

  (fn apply-updates! [entity updates]
    (var changed? false)
    (each [k v (pairs (or updates {}))]
      (local current (. entity k))
      (local next-value
        (if (or (= k :items) (= k "items"))
            (normalize-items v)
            v))
      (local different?
        (if (or (= k :items) (= k "items"))
            (not (items-equal? current next-value))
            (not (= current next-value))))
      (when different?
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
        (list-entity-updated:emit entity)))
    entity)

  (fn delete-entity [_self id]
    (local entity (load-entity id))
    (when entity
      (local path (entity-path id))
      (when (and path fs fs.remove (fs.exists path))
        (pcall (fn [] (fs.remove path))))
      (set (. cache (tostring id)) nil)
      (list-entity-deleted:emit entity))
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

  (fn add-item [_self id node-key]
    (local entity (load-entity id))
    (when entity
      (local key (tostring node-key))
      (when (and (> (string.len key) 0)
                 (not (contains-item? entity.items key)))
        (table.insert entity.items key)
        (set entity.items (normalize-items entity.items))
        (set entity.updated-at (os.time))
        (write-entity entity)
        (list-entity-updated:emit entity)
        (list-entity-items-changed:emit {:id entity.id :items entity.items})))
    entity)

  (fn remove-item [_self id node-key]
    (local entity (load-entity id))
    (when entity
      (local key (tostring node-key))
      (local items (or entity.items []))
      (var removed? false)
      (for [i 1 (length items)]
        (when (and (not removed?) (= (. items i) key))
          (table.remove items i)
          (set removed? true)))
      (when removed?
        (set entity.items (normalize-items items))
        (set entity.updated-at (os.time))
        (write-entity entity)
        (list-entity-updated:emit entity)
        (list-entity-items-changed:emit {:id entity.id :items entity.items})))
    entity)

  (fn reorder-items [_self id new-order]
    (local entity (load-entity id))
    (when entity
      (local normalized (normalize-items new-order))
      (when (not (items-equal? entity.items normalized))
        (set entity.items normalized)
        (set entity.updated-at (os.time))
        (write-entity entity)
        (list-entity-updated:emit entity)
        (list-entity-items-changed:emit {:id entity.id :items entity.items})))
    entity)

  (fn move-item [_self id from-index to-index]
    (local entity (load-entity id))
    (when entity
      (local items (or entity.items []))
      (local from (tonumber from-index))
      (local to (tonumber to-index))
      (when (and from to
                 (>= from 1) (<= from (length items))
                 (>= to 1) (<= to (length items))
                 (not (= from to)))
        (local value (. items from))
        (table.remove items from)
        (table.insert items to value)
        (set entity.items (normalize-items items))
        (set entity.updated-at (os.time))
        (write-entity entity)
        (list-entity-updated:emit entity)
        (list-entity-items-changed:emit {:id entity.id :items entity.items})))
    entity)

  {:base-dir base-dir
   :root root
   :entities-dir entities-dir
   :list-entity-created list-entity-created
   :list-entity-updated list-entity-updated
   :list-entity-deleted list-entity-deleted
   :list-entity-items-changed list-entity-items-changed
   :get-entity get-entity
   :create-entity create-entity
   :update-entity update-entity
   :delete-entity delete-entity
   :list-entities list-entities
   :add-item add-item
   :remove-item remove-item
   :reorder-items reorder-items
   :move-item move-item})

(var default-store nil)

(fn get-default [opts]
  (if default-store
      default-store
      (do
        (set default-store (ListEntityStore (or opts {})))
        default-store)))

{:ListEntityStore ListEntityStore
 :get-default get-default}
