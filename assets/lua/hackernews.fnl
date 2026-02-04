(local json (require :json))
(local JsonUtils (require :json-utils))
(local HttpCommon (require :http/common))
(local RateLimiter (require :rate-limiter))
(var fs (require :fs))
(local math math)
(local logging (require :logging))
(local base-url "https://hacker-news.firebaseio.com/v0")
(local user-agent "space-hackernews/1.0")
(local list-ttl 60)
(local updates-ttl 30)
(local maxitem-ttl 30)
(local user-ttl 300)

(fn sanitize-name [value]
  (string.gsub value "[/%\\]" "_"))

(fn cache-path [cache-dir key]
  (fs.join-path cache-dir (.. (sanitize-name key) ".json")))

(fn read-cache [cache-dir key]
  (local path (cache-path cache-dir key))
  (if (and fs fs.exists (fs.exists path))
      (let [(ok content) (pcall fs.read-file path)]
        (when ok
          (let [(parsed-ok parsed) (pcall json.loads content)]
            (when (and parsed-ok parsed (not parsed.cached_at) parsed.fetched_at)
              (set parsed.cached_at parsed.fetched_at))
            (and parsed-ok parsed))))
      nil))

(fn write-cache! [cache-dir key data]
  (local path (cache-path cache-dir key))
  (when (and fs fs.parent fs.create-dirs)
    (fs.create-dirs (fs.parent path)))
  (local payload {:cached_at (os.time) :data data})
  (let [(ok err) (pcall (fn [] (JsonUtils.write-json! path payload)))]
    (when (not ok)
      (error (.. "Failed to write cache at " path ": " err))))
  path)

(fn cache-valid? [entry ttl-fn now]
  (and entry
       entry.data
       (let [ttl (ttl-fn entry now)]
         (if (= ttl nil)
             true
             (and entry.cached_at
                  (< (- now entry.cached_at) ttl))))))

(fn item-ttl [entry now]
  (local item (and entry entry.data))
  (local created (and item item.time))
  (if (not created)
      300
      (do
        (local age (- now created))
        (if (< age 3600)
            60
            (if (< age (* 48 3600))
                300
                nil))))) 

(fn number-ttl [seconds]
  (fn [_entry _now] seconds))

(fn make-future [poll-fn]
  (var done? false)
  (var ok? false)
  (var value nil)
  (var err nil)
  (var source "pending")
  (var listeners [])
  (var cancel-fn nil)

  (fn notify []
    (each [_ cb (ipairs listeners)]
      (cb ok? value err source))
    (set listeners []))

  (fn resolve [result origin]
    (when (not done?)
      (set done? true)
      (set ok? true)
      (set value result)
      (set source origin)
      (notify)))

  (fn reject [message]
    (when (not done?)
      (set done? true)
      (set ok? false)
      (set err message)
      (notify)))

  (fn cancel []
    (when (not done?)
      (when cancel-fn
        (cancel-fn))
      (reject "cancelled")))

  (fn set-cancel [cb]
    (set cancel-fn cb))

  (fn on-complete [cb]
    (assert (= (type cb) :function) "future.on-complete expects a function")
    (if done?
        (cb ok? value err source)
        (table.insert listeners cb)))

  (fn await [timeout]
    (local deadline (and timeout (+ (os.clock) timeout)))
    (while (not done?)
      (when poll-fn
        (poll-fn))
      (when (and deadline (> (os.clock) deadline))
        (reject "timeout waiting for response")))
    (if ok?
        value
        (error err)))

  {:resolve resolve
   :reject reject
   :cancel cancel
   :set-cancel set-cancel
   :on-complete on-complete
   :await await
   :done? (fn [] done?)
   :ok? (fn [] ok?)
   :error (fn [] err)
   :source (fn [] source)
   :value (fn [] value)})

(fn resolved-future [value poll-fn]
  (local future (make-future poll-fn))
  (future.resolve value "cache")
  future)

(fn HackerNews [opts]
  (local options (or opts {}))
  (local http-binding (or options.http (require :http)))
  (local fs-binding (or options.fs fs))
  (local app-binding (or options.app app))
  (assert http-binding "HackerNews requires the http binding")
  (assert fs-binding "HackerNews requires the fs module")
  (assert json "HackerNews requires the json module")
  (assert (and app-binding app-binding.get-app-dir) "HackerNews requires app.get-app-dir")
  (set fs fs-binding)

  (local rate-limit (or options.requests_per_window 4))
  (local window-ms (or options.window_ms 1000))
  (local app-name (or options.app-name "hackernews"))

  (local base-dir (app-binding.get-app-dir app-name))
  (local cache-dir (fs-binding.join-path base-dir "cache"))
  (when (and fs-binding fs-binding.create-dirs)
    (fs-binding.create-dirs cache-dir))

  (local limiter (RateLimiter {:limit rate-limit :window_ms window-ms}))
  (var pending {})
  (var callback-count 0)
  (var poll nil)

  (fn log-http-error [res entry]
    (when (and res res.status (>= res.status 400))
      (local cache-key (or (and entry entry.cache-key) "<unknown>"))
      (local body (or res.body ""))
      (local err (or res.error ""))
      (logging.warn (.. "[hackernews] HTTP " res.status
                        " for " cache-key
                        (if (> (# err) 0) (.. " error=\"" err "\"") "")
                        (if (> (# body) 0) (.. " body=\"" body "\"") " body=<empty>")))))

  (fn process-response [res]
    (local entry (. pending res.id))
    (when entry
      (set (. pending res.id) nil)
      (if (and res.ok res.body)
          (do
            (local (ok parsed-or-err) (pcall (fn [] (HttpCommon.decode-json! res.body "Failed to decode JSON"))))
            (if ok
                (do
                  (write-cache! cache-dir entry.cache-key parsed-or-err)
                  (entry.future.resolve parsed-or-err "network"))
                (entry.future.reject parsed-or-err)))
          (do
            (log-http-error res entry)
            (entry.future.reject
             (or res.error (.. "HTTP request failed with status " res.status)))))))

  (set poll
       (fn [max-results]
         (each [_ res (ipairs (http-binding.poll max-results))]
           (process-response res))))

  (fn wait [future timeout]
    (HttpCommon.poll-until poll (fn [] (future.done?)) timeout "timeout waiting for hackernews response")
    (if (future.ok?)
        (future.value)
        (error (future.error))))

  (fn drop []
    (each [id entry (pairs pending)]
      (http-binding.cancel id)
      (entry.future.reject "client dropped"))
    (set pending {}))

  (fn enqueue-request [path cache-key ttl-fn]
    (local now (os.time))
    (local cached (and cache-key (read-cache cache-dir cache-key)))
    (if (and cached ttl-fn (cache-valid? cached ttl-fn now))
        (resolved-future cached.data poll)
        (do
          (local delay (limiter.acquire))
          (local future (make-future poll))
	          (local id (http-binding.request {:url (.. base-url "/" path ".json")
	                                   :method "GET"
	                                   :timeout-ms 10000
	                                   :connect-timeout-ms 5000
	                                   :user-agent user-agent
	                                   :follow-redirects true
	                                   :delay-ms (math.floor delay)
	                                   :callback (fn [res]
	                                               (set callback-count (+ callback-count 1))
	                                               (process-response res))}))
          (future.set-cancel
           (fn []
            (http-binding.cancel id)
            (set (. pending id) nil)
            (future.reject "cancelled")))
          (set (. pending id) {:future future :cache-key cache-key})
          future)))

  (fn normalize-item-id [id]
    (if (= (type id) :number)
        (let [integer (math.tointeger id)]
          (assert integer "item id must be an integer")
          (tostring integer))
        (if (= (type id) :string)
            (let [num (tonumber id)
                  integer (and num (math.tointeger num))]
              (if integer
                  (tostring integer)
                  (do
                    (assert (string.match id "^%d+$") "item id must be numeric")
                    id)))
            (error "fetch-item requires a numeric id"))))

  (fn fetch-item [id]
    (assert id "fetch-item requires an id")
    (local id-str (normalize-item-id id))
    (enqueue-request (.. "item/" id-str) (.. "item-" id-str) item-ttl))

  (fn fetch-user [name]
    (assert name "fetch-user requires a username")
    (enqueue-request (.. "user/" name) (.. "user-" (sanitize-name name)) (number-ttl user-ttl)))

  (fn fetch-list [name]
    (enqueue-request name (.. name "-list") (number-ttl list-ttl)))

  (fn fetch-updates []
    (enqueue-request "updates" "updates" (number-ttl updates-ttl)))

  (fn fetch-max-item []
    (enqueue-request "maxitem" "maxitem" (number-ttl maxitem-ttl)))

  {:fetch-item fetch-item
   :fetch-user fetch-user
   :fetch-topstories (fn [] (fetch-list "topstories"))
   :fetch-newstories (fn [] (fetch-list "newstories"))
   :fetch-beststories (fn [] (fetch-list "beststories"))
   :fetch-askstories (fn [] (fetch-list "askstories"))
   :fetch-showstories (fn [] (fetch-list "showstories"))
   :fetch-jobstories (fn [] (fetch-list "jobstories"))
   :fetch-updates fetch-updates
   :fetch-max-item fetch-max-item
   :poll poll
   :wait wait
   :drop drop
   :cache-dir (fn [] cache-dir)
   :callback-count (fn [] callback-count)
   :pending-count (fn []
                    (var count 0)
                    (each [_ _ (pairs pending)]
                      (set count (+ count 1)))
                    count)})

HackerNews
