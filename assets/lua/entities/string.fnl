(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))

(fn ensure-dir [path]
  (when (and path fs fs.create-dirs)
    (pcall (fn [] (fs.create-dirs path))))
  path)

(fn strip-whitespace [text]
  (if (not text)
      ""
      (string.match text "^%s*(.-)%s*$")))

(fn parse-frontmatter [content]
  (if (not content)
      {:frontmatter {} :body ""}
      (let [pattern "^%-%-%-\n(.-)\n%-%-%-\n?(.*)$"]
        (local (fm body) (string.match content pattern))
        (if fm
            (do
              (local frontmatter {})
              (each [line (string.gmatch fm "[^\n]+")]
                (local (key value) (string.match line "^([^:]+):%s*(.*)$"))
                (when (and key value)
                  (set (. frontmatter (strip-whitespace key)) (strip-whitespace value))))
              {:frontmatter frontmatter
               :body (strip-whitespace (or body ""))})
            {:frontmatter {}
             :body (strip-whitespace content)}))))

(fn serialize-frontmatter [entity]
  (local lines ["---"])
  (table.insert lines (.. "id: " (tostring entity.id)))
  (table.insert lines (.. "created-at: " (tostring entity.created-at)))
  (table.insert lines (.. "updated-at: " (tostring entity.updated-at)))
  (table.insert lines "---")
  (table.insert lines "")
  (table.insert lines (or entity.value ""))
  (table.concat lines "\n"))

(fn StringEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (or options.base-dir
                      (and appdirs (appdirs.user-data-dir "space"))))
  (local root (and base-dir fs (fs.join-path base-dir "entities")))
  (local entities-dir (and root fs (fs.join-path root "string")))
  (ensure-dir entities-dir)

  (local cache {})

  (local string-entity-created (Signal))
  (local string-entity-updated (Signal))
  (local string-entity-deleted (Signal))

  (fn entity-path [id]
    (and entities-dir (fs.join-path entities-dir (.. (tostring id) ".md"))))

  (fn read-entity [path]
    (when (and path fs fs.exists (fs.exists path))
      (local (ok content) (pcall fs.read-file path))
      (when ok
        (local parsed (parse-frontmatter content))
        (local fm parsed.frontmatter)
        {:id (or fm.id "")
         :created-at (tonumber (or fm.created-at 0))
         :updated-at (tonumber (or fm.updated-at 0))
         :value parsed.body})))

  (fn write-entity [entity]
    (when entity
      (local path (entity-path entity.id))
      (when path
        (ensure-dir entities-dir)
        (local content (serialize-frontmatter entity))
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
                   :created-at (or options.created-at now)
                   :updated-at (or options.updated-at now)
                   :value (or options.value "")})
    (set (. cache id) entity)
    (write-entity entity)
    (string-entity-created:emit entity)
    entity)

  (fn update-entity [_self id updates]
    (local entity (load-entity id))
    (when entity
      (each [k v (pairs (or updates {}))]
        (set (. entity k) v))
      (set entity.updated-at (os.time))
      (write-entity entity)
      (string-entity-updated:emit entity))
    entity)

  (fn delete-entity [_self id]
    (local entity (load-entity id))
    (when entity
      (local path (entity-path id))
      (when (and path fs fs.remove (fs.exists path))
        (pcall (fn [] (fs.remove path))))
      (set (. cache (tostring id)) nil)
      (string-entity-deleted:emit entity))
    entity)

  (fn list-entities [_self]
    (local items [])
    (when (and entities-dir fs fs.list-dir (fs.exists entities-dir))
      (local (ok entries) (pcall fs.list-dir entities-dir false))
      (when ok
        (each [_ entry (ipairs (or entries []))]
          (when (and entry entry.is-file entry.name (string.match entry.name "%.md$"))
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
   :string-entity-created string-entity-created
   :string-entity-updated string-entity-updated
   :string-entity-deleted string-entity-deleted
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
        (set default-store (StringEntityStore (or opts {})))
        default-store)))

{:StringEntityStore StringEntityStore
 :get-default get-default}
