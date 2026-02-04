(local fs (require :fs))
(local appdirs (require :appdirs))

(assert appdirs "appdirs module is required for layout debug logging")
(local log-dir (appdirs.user-log-dir "space"))
(local log-path (if (and app.engine fs.join-path)
                    (fs.join-path log-dir "layout-queue.log")
                    (.. log-dir "/layout-queue.log")))

(fn safe-string [value]
  (local packed (table.pack (pcall tostring value)))
  (local ok (. packed 1))
  (local result (. packed 2))
  (if ok result "<tostring failed>"))

(fn safe-table? [value]
  (= (type value) :table))

(fn safe-count [value]
  (if (safe-table? value)
      (do
        (var count 0)
        (each [_ _ (pairs value)]
          (set count (+ count 1)))
        count)
      nil))

(fn safe-field [value key]
  (if (and (safe-table? value) (not (= (rawget value key) nil)))
      (rawget value key)
      nil))

(fn safe-call [value key]
  (if (safe-table? value)
      (let [candidate (rawget value key)]
        (if (= (type candidate) :function)
            (let [(ok result) (pcall (fn [] (candidate value)))]
              (if ok result nil))
            nil))
      nil))

(fn summarize-key [key]
  (if (not (safe-table? key))
      {:kind (type key)}
      (let [name (safe-field key :name)
            depth (safe-field key :depth)
            parent (safe-field key :parent)
            root (safe-field key :root)
            ancestor-names (safe-call key :get-ancestor-names)]
        {:kind :table
         :name name
         :depth depth
         :parent parent
         :root root
         :ancestor-names ancestor-names})))

(fn ensure-log-dir []
  (when (and fs fs.create-dirs)
    (pcall (fn []
             (local parent (and fs.parent (fs.parent log-path)))
             (fs.create-dirs (or parent log-dir))))))

(fn append-lines [lines]
  (ensure-log-dir)
  (pcall (fn []
           (local handle (io.open log-path "a"))
           (when handle
             (each [_ line (ipairs lines)]
               (handle:write line "\n"))
             (handle:close)))))

(fn log-next-error [message tbl key depth depths queue]
  (local queue-label (and queue queue.label))
  (local lookup (and queue queue.lookup))
  (local key-summary (summarize-key key))
  (local lines
    [(string.format "error=%s" (safe-string message))
     (string.format "queue-label=%s" (safe-string queue-label))
     (string.format "queue-depth-count=%s" (safe-string (length (or depths []))))
     (string.format "table-type=%s" (type tbl))
     (string.format "table=%s" (safe-string tbl))
     (string.format "table-count=%s" (safe-string (safe-count tbl)))
     (string.format "key-type=%s" (type key))
     (string.format "key=%s" (safe-string key))
     (string.format "key-name=%s" (safe-string (safe-field key-summary :name)))
     (string.format "key-depth=%s" (safe-string (safe-field key-summary :depth)))
     (string.format "key-root=%s" (safe-string (safe-field key-summary :root)))
     (string.format "key-parent=%s" (safe-string (safe-field key-summary :parent)))
     (string.format "key-ancestors=%s" (safe-string (safe-field key-summary :ancestor-names)))
     (string.format "key-in-bucket=%s" (safe-string (and (safe-table? tbl)
                                                         (not (= (rawget tbl key) nil)))))
     (string.format "key-lookup-depth=%s" (safe-string (and (safe-table? lookup)
                                                            (rawget lookup key))))
     (string.format "depth=%s" (safe-string depth))
     (string.format "frame-id=%s" (and app.engine app.engine.frame-id))
     (string.format "traceback=%s" (debug.traceback))])
  (append-lines lines))

{:log-next-error log-next-error
 :log-path log-path}
