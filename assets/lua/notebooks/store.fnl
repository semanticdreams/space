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

(fn normalize-items [items]
  (local seen {})
  (local out [])
  (each [_ value (ipairs (or items []))]
    (local key (tostring value))
    (when (and (> (string.len key) 0)
               (not (. seen key)))
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

(fn NotebookStore [opts]
  (local options (or opts {}))
  (local base-dir (or options.base-dir
                      (and appdirs (appdirs.user-data-dir "space"))))
  (local notebooks-dir (and base-dir fs (fs.join-path base-dir "notebooks")))
  (ensure-dir notebooks-dir)

  (local cache {})

  (local notebook-created (Signal))
  (local notebook-updated (Signal))
  (local notebook-deleted (Signal))
  (local notebook-items-changed (Signal))

  (fn notebook-path [id]
    (and notebooks-dir (fs.join-path notebooks-dir (.. (tostring id) ".json"))))

  (fn read-notebook [path]
    (when (and path fs fs.exists (fs.exists path))
      (local (ok content) (pcall fs.read-file path))
      (when ok
        (local (parse-ok data) (pcall json.loads content))
        (when parse-ok
          (local items (normalize-items (or data.items [])))
          {:id (tostring (or data.id ""))
           :name (normalize-name data.name)
           :items items
           :created-at (tonumber (or data.created-at 0))
           :updated-at (tonumber (or data.updated-at 0))}))))

  (fn write-notebook [notebook]
    (when notebook
      (local path (notebook-path notebook.id))
      (when path
        (ensure-dir notebooks-dir)
        (local data {:id (tostring notebook.id)
                     :name (normalize-name notebook.name)
                     :items (normalize-items notebook.items)
                     :created-at notebook.created-at
                     :updated-at notebook.updated-at})
        (JsonUtils.write-json! path data)))
    notebook)

  (fn load-notebook [id]
    (local key (tostring id))
    (if (. cache key)
        (. cache key)
        (do
          (local data (read-notebook (notebook-path key)))
          (when data
            (set (. cache key) data))
          data)))

  (fn get-notebook [_self id]
    (if id (load-notebook id) nil))

  (fn create-notebook [_self opts]
    (local create-opts (or opts {}))
    (local id (tostring (or create-opts.id (Uuid.v4))))
    (local now (os.time))
    (local notebook {:id id
                     :name (normalize-name create-opts.name)
                     :items (normalize-items (or create-opts.items []))
                     :created-at (or create-opts.created-at now)
                     :updated-at (or create-opts.updated-at now)})
    (set (. cache id) notebook)
    (write-notebook notebook)
    (notebook-created:emit notebook)
    notebook)

  (fn apply-updates! [notebook updates]
    (var changed? false)
    (each [k v (pairs (or updates {}))]
      (local current (. notebook k))
      (local next-value
        (if (or (= k :items) (= k "items"))
            (normalize-items v)
            (if (or (= k :name) (= k "name"))
                (normalize-name v)
                v)))
      (local different?
        (if (or (= k :items) (= k "items"))
            (not (items-equal? current next-value))
            (not (= current next-value))))
      (when different?
        (set changed? true)
        (set (. notebook k) next-value)))
    changed?)

  (fn update-notebook [_self id updates]
    (local notebook (load-notebook id))
    (when notebook
      (local changed? (apply-updates! notebook updates))
      (when changed?
        (set notebook.updated-at (os.time))
        (write-notebook notebook)
        (notebook-updated:emit notebook)))
    notebook)

  (fn delete-notebook [_self id]
    (local notebook (load-notebook id))
    (when notebook
      (local path (notebook-path id))
      (when (and path fs fs.remove (fs.exists path))
        (pcall (fn [] (fs.remove path))))
      (set (. cache (tostring id)) nil)
      (notebook-deleted:emit notebook))
    notebook)

  (fn list-notebooks [_self]
    (local items [])
    (when (and notebooks-dir fs fs.list-dir (fs.exists notebooks-dir))
      (local (ok entries) (pcall fs.list-dir notebooks-dir false))
      (when ok
        (each [_ entry (ipairs (or entries []))]
          (when (and entry entry.is-file entry.name (string.match entry.name "%.json$"))
            (local data (read-notebook entry.path))
            (when data
              (set (. cache (tostring data.id)) data)
              (table.insert items data))))))
    (table.sort items
                (fn [a b]
                  (> (or a.updated-at 0) (or b.updated-at 0))))
    items)

  (fn add-item [_self id node-key]
    (local notebook (load-notebook id))
    (when notebook
      (local key (tostring node-key))
      (when (and (> (string.len key) 0)
                 (not (contains-item? notebook.items key)))
        (table.insert notebook.items key)
        (set notebook.items (normalize-items notebook.items))
        (set notebook.updated-at (os.time))
        (write-notebook notebook)
        (notebook-updated:emit notebook)
        (notebook-items-changed:emit {:id notebook.id :items notebook.items})))
    notebook)

  (fn remove-item [_self id node-key]
    (local notebook (load-notebook id))
    (when notebook
      (local key (tostring node-key))
      (local items (or notebook.items []))
      (var removed? false)
      (for [i 1 (length items)]
        (when (and (not removed?) (= (. items i) key))
          (table.remove items i)
          (set removed? true)))
      (when removed?
        (set notebook.items (normalize-items items))
        (set notebook.updated-at (os.time))
        (write-notebook notebook)
        (notebook-updated:emit notebook)
        (notebook-items-changed:emit {:id notebook.id :items notebook.items})))
    notebook)

  (fn reorder-items [_self id new-order]
    (local notebook (load-notebook id))
    (when notebook
      (local normalized (normalize-items new-order))
      (when (not (items-equal? notebook.items normalized))
        (set notebook.items normalized)
        (set notebook.updated-at (os.time))
        (write-notebook notebook)
        (notebook-updated:emit notebook)
        (notebook-items-changed:emit {:id notebook.id :items notebook.items})))
    notebook)

  (fn move-item [_self id from-index to-index]
    (local notebook (load-notebook id))
    (when notebook
      (local items (or notebook.items []))
      (local from (tonumber from-index))
      (local to (tonumber to-index))
      (when (and from to
                 (>= from 1) (<= from (length items))
                 (>= to 1) (<= to (length items))
                 (not (= from to)))
        (local value (. items from))
        (table.remove items from)
        (table.insert items to value)
        (set notebook.items (normalize-items items))
        (set notebook.updated-at (os.time))
        (write-notebook notebook)
        (notebook-updated:emit notebook)
        (notebook-items-changed:emit {:id notebook.id :items notebook.items})))
    notebook)

  {:base-dir base-dir
   :notebooks-dir notebooks-dir
   :notebook-created notebook-created
   :notebook-updated notebook-updated
   :notebook-deleted notebook-deleted
   :notebook-items-changed notebook-items-changed
   :get-notebook get-notebook
   :create-notebook create-notebook
   :update-notebook update-notebook
   :delete-notebook delete-notebook
   :list-notebooks list-notebooks
   :add-item add-item
   :remove-item remove-item
   :reorder-items reorder-items
   :move-item move-item})

(var default-store nil)

(fn get-default [opts]
  (if default-store
      default-store
      (do
        (set default-store (NotebookStore (or opts {})))
        default-store)))

{:NotebookStore NotebookStore
 :get-default get-default}
