(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local Ids (require :llm/ids))
(local Settings (require :settings))

(fn ensure-dir [path]
  (when (and path fs fs.create-dirs)
    (pcall (fn [] (fs.create-dirs path))))
  path)

(fn read-json [path]
  (local content (fs.read-file path))
  (json.loads content))

(fn write-json [path payload]
  (when (and path payload)
    (ensure-dir (fs.parent path))
    (JsonUtils.write-json! path payload))
  payload)

(fn is-json-file? [entry]
  (and entry entry.is-file entry.name (string.match entry.name "%.json$")))

(fn list-json [path]
  (if (and path fs fs.list-dir (fs.exists path))
      (let [(ok entries) (pcall fs.list-dir path false)]
        (if ok entries []))
      []))

(fn sort-updated [entries]
  (table.sort entries
              (fn [a b]
                (> (or a.updated_at 0) (or b.updated_at 0))))
  entries)

(fn Store [opts]
  (local options (or opts {}))
  (local settings (or options.settings (Settings {:app-name "space"})))
  (local base-dir (or options.base-dir
                      (and appdirs (appdirs.user-data-dir "space"))))
  (local root (and base-dir fs (fs.join-path base-dir "llm")))
  (local conversations-dir (and root fs (fs.join-path root "conversations")))
  (local messages-dir (and root fs (fs.join-path root "messages")))
  (local links-dir (and root fs (fs.join-path root "links" "conversation-items")))
  (ensure-dir conversations-dir)
  (ensure-dir messages-dir)
  (ensure-dir links-dir)

  (local conversations {})
  (local messages {})
  (local links {})
  (var active-conversation-id nil)

  (local conversations-changed (Signal))
  (local conversation-changed (Signal))
  (local message-changed (Signal))
  (local conversation-items-changed (Signal))
  (local active-conversation-changed (Signal))

  (fn conversation-path [id]
    (and conversations-dir (fs.join-path conversations-dir (.. (tostring id) ".json"))))

  (fn message-path [id]
    (and messages-dir (fs.join-path messages-dir (.. (tostring id) ".json"))))

  (fn link-path [conversation-id]
    (and links-dir (fs.join-path links-dir (.. (tostring conversation-id) ".json"))))

  (fn load-conversation [id]
    (local key (tostring id))
    (if (. conversations key)
        (. conversations key)
        (let [data (read-json (conversation-path key))]
          (when data
            (when (not data.provider)
              (set data.provider "openai"))
            (when (= data.provider "zai")
              (set data.model "glm-4.7"))
            (when (and (= data.provider "openai") (= data.model "glm-4.7"))
              (set data.model "gpt-4o-mini"))
            (when (not data.cwd)
              (set data.cwd (fs.cwd)))
            (when (not data.reasoning_effort)
              (set data.reasoning_effort "none"))
            (when (not data.text_verbosity)
              (set data.text_verbosity "medium"))
            (set (. conversations key) data))
          data)))

  (fn load-message [id]
    (local key (tostring id))
    (if (. messages key)
        (. messages key)
        (let [data (read-json (message-path key))]
          (when data
            (set (. messages key) data))
          data)))

  (fn load-links [conversation-id]
    (local key (tostring conversation-id))
    (if (. links key)
        (. links key)
        (let [path (link-path key)]
          (when (and path (not (fs.exists path)))
            (write-json path {:conversation_id key
                              :items []}))
          (local data (read-json path))
          (var resolved data)
          (when (and resolved (not (. resolved :items)))
            (set resolved {:conversation_id key
                           :items []}))
          (when (not resolved)
            (set resolved {:conversation_id key
                           :items []}))
          (set (. links key) resolved)
          resolved)))

  (fn save-conversation [record]
    (when record
      (write-json (conversation-path record.id) record))
    record)

  (fn save-message [record]
    (when record
      (write-json (message-path record.id) record))
    record)

  (fn save-links [conversation-id payload]
    (when payload
      (write-json (link-path conversation-id) payload))
    payload)

  (fn remove-file [path]
    (when (and path fs fs.remove (fs.exists path))
      (pcall (fn [] (fs.remove path))))
    path)

  (fn set-active-conversation [id]
    (local value (if id (tostring id) nil))
    (when (not (= value active-conversation-id))
      (set active-conversation-id value)
      (active-conversation-changed:emit value))
    value)

  (fn list-conversations [opts]
    (local options (or opts {}))
    (local include-archived? (= options.include-archived? true))
    (local items [])
    (each [_ entry (ipairs (list-json conversations-dir))]
      (when (is-json-file? entry)
        (local data (read-json entry.path))
        (when data
          (set (. conversations (tostring data.id)) data)
          (local archived? (or (= data.archived true)
                               (not (= data.archived_at nil))))
          (when (or include-archived? (not archived?))
            (table.insert items data)))))
    (sort-updated items)
    items)

  (fn get-conversation [id]
    (if id (load-conversation id) nil))

  (fn get-message [id]
    (if id (load-message id) nil))

  (var create-conversation nil)

  (fn ensure-conversation [id opts]
    (local record (get-conversation id))
    (if record
        record
        (create-conversation (or opts {}) id)))

  (set create-conversation
    (fn [opts forced-id]
    (local options (or opts {}))
    (local id (tostring (or forced-id (Ids.new-id "conv"))))
    (local now (os.time))
    (local provider (or options.provider "openai"))
    (local model
      (if (= provider "zai")
          (do
            (when (and options.model (not (= options.model "glm-4.7")))
              (error (.. "Unsupported ZAI model: " (tostring options.model))))
            "glm-4.7")
          (or options.model "gpt-4o-mini")))
    (local record {:id id
                   :name (or options.name "")
                   :provider provider
                   :model model
                   :temperature (if (not (= options.temperature nil)) options.temperature 0)
                   :reasoning_effort (or options.reasoning_effort "none")
                   :text_verbosity (or options.text_verbosity "medium")
                   :max_tool_rounds options.max_tool_rounds
                   :tools (or options.tools [])
                   :cwd (or options.cwd
                            (settings.get-value "llm.default_conversation_cwd")
                            (fs.cwd))
                   :item_seq (or options.item-seq 0)
                   :archived false
                   :archived_at nil
                   :created_at (or options.created-at now)
                   :updated_at (or options.updated-at now)})
    (set (. conversations id) record)
    (save-conversation record)
    (conversations-changed:emit record)
    (conversation-changed:emit record)
    (when (not active-conversation-id)
      (set-active-conversation id))
    record))

  (fn update-conversation [id updates]
    (local record (get-conversation id))
    (when record
      (each [k v (pairs (or updates {}))]
        (set (. record k) v))
      (set record.updated_at (os.time))
      (when updates.cwd
         (set record.cwd updates.cwd))
      (save-conversation record)
      (conversation-changed:emit record))
    record)

  (fn touch-conversation [id]
    (update-conversation id {}))

  (fn archive-conversation [id]
    (local record (get-conversation id))
    (when record
      (set record.archived true)
      (set record.archived_at (os.time))
      (save-conversation record)
      (conversation-changed:emit record)
      (conversations-changed:emit record))
    record)

  (fn delete-conversation [id]
    (local record (get-conversation id))
    (if (not record)
        nil
        (do
          (assert id "delete-conversation requires an id")
          (local convo-id-str (tostring id))
          (local payload (load-links convo-id-str))
          (local items (or (and payload payload.items) []))
          (local usage {})
          (local convos (list-conversations {:include-archived? true}))
          (fn update-usage [entry]
            (when entry
              (local key (tostring entry.id))
              (set (. usage key) (+ (or (. usage key) 0) 1))))
          (each [_ convo (ipairs convos)]
            (when (not (= (tostring convo.id) convo-id-str))
              (local other-links (load-links convo.id))
              (each [_ entry (ipairs (or (and other-links other-links.items) []))]
                (update-usage entry))))
          (each [_ entry (ipairs items)]
            (local key (tostring entry.id))
            (when (= (or (. usage key) 0) 0)
              (set (. messages key) nil)
              (remove-file (message-path key))))
          (when (> (length convo-id-str) 0)
            (set (. links convo-id-str) nil)
            (remove-file (link-path convo-id-str))
            (set (. conversations convo-id-str) nil)
            (remove-file (conversation-path convo-id-str))
            (when (= active-conversation-id convo-id-str)
              (set-active-conversation nil))
            (conversation-items-changed:emit {:conversation_id convo-id-str
                                              :deleted true})
            (conversation-changed:emit {:id convo-id-str
                                        :deleted true})
            (conversations-changed:emit {:id convo-id-str
                                         :deleted true}))
          record)))

  (fn create-item [opts forced-id]
    (local options (or opts {}))
    (local id (tostring (or forced-id (Ids.new-id "msg"))))
    (local now (os.time))
    (local record {:id id
                   :parent_id options.parent-id
                   :type (or options.type "message")
                   :role options.role
                   :content (or options.content "")
                   :tool_name options.tool-name
                   :tool_call_id options.tool-call-id
                   :tools (or options.tools [])
                   :response_id options.response-id
                   :name options.name
                   :call_id options.call-id
                   :arguments options.arguments
                   :output options.output
                   :last_usage options.last-usage
                   :last_context_window options.last-context-window
                   :last_model options.last-model
                   :created_at (or options.created-at now)
                   :updated_at (or options.updated-at now)})
    (set (. messages id) record)
    (save-message record)
    (message-changed:emit record)
    record)

  (fn update-item [id updates]
    (local record (get-message id))
    (when record
      (fn normalize-key [key]
        (if (= key :parent-id)
            :parent_id
        (if (= key :tool-name)
            :tool_name
            (if (= key :tool-call-id)
                :tool_call_id
                (if (= key :response-id)
                    :response_id
                    (if (= key :call-id)
                        :call_id
                        (if (= key :last-usage)
                            :last_usage
                            (if (= key :last-context-window)
                                :last_context_window
                                (if (= key :last-model)
                                    :last_model
                                    key)))))))))
      (each [k v (pairs (or updates {}))]
        (set (. record (normalize-key k)) v))
      (set record.updated_at (os.time))
      (save-message record)
      (message-changed:emit record))
    record)

  (fn link-item [conversation-id item]
    (local convo (get-conversation conversation-id))
    (when (and convo item)
      (local payload (load-links convo.id))
      (local items (or (and payload payload.items) []))
      (var exists? false)
      (each [_ entry (ipairs items)]
        (when (= entry.id item.id)
          (set exists? true)))
      (when (not exists?)
        (set convo.item_seq (+ (or convo.item_seq 0) 1))
        (local link {:id item.id
                     :type item.type
                     :order convo.item_seq})
        (table.insert items link)
        (set payload.items items)
        (save-links convo.id payload)
        (save-conversation convo)
        (conversation-items-changed:emit {:conversation_id convo.id}))
      item))

  (fn add-message [conversation-id opts]
    (local record (create-item (or opts {})))
    (link-item conversation-id record)
    record)

(fn add-tool-call [conversation-id opts]
    (local options (or opts {}))
    (set options.type "tool-call")
    (local record (create-item options))
    (link-item conversation-id record)
    record)

(fn add-tool-result [conversation-id opts]
    (local options (or opts {}))
    (set options.type "tool-result")
    (local record (create-item options))
    (link-item conversation-id record)
    record)

  (fn list-conversation-items [conversation-id]
    (local payload (load-links conversation-id))
    (local items (or (and payload payload.items) []))
    (table.sort items (fn [a b] (< (or a.order 0) (or b.order 0))))
    (local resolved [])
    (each [_ entry (ipairs items)]
      (local record (get-message entry.id))
      (when record
        (set record.order entry.order)
        (table.insert resolved record)))
    resolved)

  (fn build-input-items [conversation-id up-to-id]
    (local all-items (list-conversation-items conversation-id))
    (if (not up-to-id)
        all-items
        (do
          (local result [])
          (var found? false)
          (each [_ item (ipairs all-items)]
            (when (not found?)
              (table.insert result item)
              (when (= (tostring item.id) (tostring up-to-id))
                (set found? true))))
          result)))

  (fn find-conversation-for-item [item-id]
    (local id (tostring item-id))
    (local convos (list-conversations {:include-archived? true}))
    (var found nil)
    (var i 1)
    (while (and (<= i (length convos)) (not found))
      (local convo (. convos i))
      (local payload (load-links convo.id))
      (local items (or (and payload payload.items) []))
      (var j 1)
      (while (and (<= j (length items)) (not found))
        (local entry (. items j))
        (when (and entry (= entry.id id))
          (set found convo))
        (set j (+ j 1)))
      (set i (+ i 1)))
    found)

  {:base-dir base-dir
   :root root
   :conversations-dir conversations-dir
   :messages-dir messages-dir
   :links-dir links-dir
   :conversations-changed conversations-changed
   :conversation-changed conversation-changed
   :message-changed message-changed
   :conversation-items-changed conversation-items-changed
   :active-conversation-changed active-conversation-changed
   :get-active-conversation-id (fn [_self] active-conversation-id)
   :set-active-conversation-id (fn [_self id] (set-active-conversation id))
   :list-conversations (fn [_self opts] (list-conversations opts))
   :get-conversation (fn [_self id] (get-conversation id))
   :ensure-conversation (fn [_self id opts] (ensure-conversation id opts))
   :create-conversation (fn [_self opts id] (create-conversation opts id))
   :update-conversation (fn [_self id updates] (update-conversation id updates))
   :archive-conversation (fn [_self id] (archive-conversation id))
   :delete-conversation (fn [_self id] (delete-conversation id))
   :touch-conversation (fn [_self id] (touch-conversation id))
   :get-item (fn [_self id] (get-message id))
   :create-item (fn [_self opts id] (create-item opts id))
   :update-item (fn [_self id updates] (update-item id updates))
   :add-message (fn [_self conversation-id opts] (add-message conversation-id opts))
   :add-tool-call (fn [_self conversation-id opts] (add-tool-call conversation-id opts))
   :add-tool-result (fn [_self conversation-id opts] (add-tool-result conversation-id opts))
   :link-item (fn [_self conversation-id item] (link-item conversation-id item))
   :list-conversation-items (fn [_self conversation-id] (list-conversation-items conversation-id))
   :build-input-items (fn [_self conversation-id up-to-id] (build-input-items conversation-id up-to-id))
   :find-conversation-for-item (fn [_self item-id] (find-conversation-for-item item-id))})

(var default-store nil)

(fn get-default [opts]
  (if default-store
      default-store
      (do
        (set default-store (Store (or opts {})))
        default-store)))

{:Store Store
 :get-default get-default}
