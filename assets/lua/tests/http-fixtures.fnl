(local json (require :json))
(local JsonUtils (require :json-utils))
(local fs (require :fs))
(var http nil)

(fn ensure-http []
  (when (not http)
    (set http (require :http)))
  http)

(local http-fixtures {})

(fn assert-deps []
  (assert fs "http-fixtures requires the fs module")
  (assert json "http-fixtures requires the json module"))

(fn ensure-dir [path]
  (when (and fs fs.parent fs.create-dirs)
    (fs.create-dirs (fs.parent path))))

(fn read-json [path]
  (assert-deps)
  (local (ok contents) (pcall fs.read-file path))
  (when (not ok)
    (error (.. "Failed to read fixture " path ": " contents)))
  (let [(parsed-ok data) (pcall json.loads contents)]
    (if parsed-ok
        data
        (error (.. "Failed to parse JSON fixture " path ": " data)))))

(fn write-json! [path data]
  (assert-deps)
  (ensure-dir path)
  (let [(ok err) (pcall (fn [] (JsonUtils.write-json! path data)))]
    (when (not ok)
      (error (.. "Failed to write fixture " path ": " err))))
  path)

(fn strip-json-suffix [value]
  (string.gsub value "%.json$" ""))

(fn path-from-url [url]
  (local without-query (string.match url "([^?]+)"))
  (local with-domain (string.match without-query "^https?://[^/]+/(.+)"))
  (local trimmed (or with-domain without-query))
  (local without-prefix (or (string.match trimmed "v0/(.+)") trimmed))
  (strip-json-suffix without-prefix))

(fn normalize-key [entry]
  (or entry.key
      (and entry.url (path-from-url entry.url))
      (and entry.name (path-from-url entry.name))
      (error "Fixture entry missing key and url")))

(fn normalize-headers-field [headers]
  (if (not headers)
      []
      (do
        (var out [])
        (each [_ entry (ipairs headers)]
          (if (and (= (type entry) :table) (. entry 1))
              (table.insert out entry)
              (each [k v (pairs entry)]
                (table.insert out [k v]))))
        out)))

(fn normalize-response [entry id]
  {:id id
   :status (or entry.status 200)
   :ok (if (= entry.ok nil) (< (or entry.status 0) 400) entry.ok)
   :body (or entry.body "")
   :headers (normalize-headers-field entry.headers)
   :error entry.error})

(fn index-responses [fixture]
  (local indexed {})
  (each [_ entry (ipairs fixture.responses)]
    (local key (normalize-key entry))
    (when (not (. indexed key))
      (set (. indexed key) []))
    (table.insert (. indexed key) entry))
  indexed)

(fn derive-key [url]
  (assert url "http request missing url")
  (path-from-url url))

(fn make-mock-http [fixture]
  (assert fixture "fixture missing")
  (assert fixture.responses "fixture missing responses list")
  (local responses (index-responses fixture))
  (var next-id 1)
  (var queue [])
  (var requests-log [])

  (fn enqueue [req entry]
    (local id next-id)
    (set next-id (+ next-id 1))
    (local res (normalize-response entry id))
    (table.insert queue {:response res :callback req.callback})
    (table.insert requests-log {:id id
                                :key req.key
                                :url req.url
                                :method req.method
                                :status res.status
                                :headers res.headers})
    id)

  (local binding {})

  (set binding.request
       (fn [opts]
         (assert opts "http.request requires opts")
         (local url (or opts.url nil))
         (local method (string.upper (or opts.method "GET")))
         (local key (derive-key url))
         (local entries (. responses key))
         (when (or (not entries) (= (# entries) 0))
           (error (.. "No fixture response for " key)))
         (var chosen nil)
         (var idx 1)
         (while (and (<= idx (# entries)) (not chosen))
           (local candidate (. entries idx))
           (if (or (not candidate.method) (= (string.upper candidate.method) method))
               (do
                 (set chosen candidate)
                 (table.remove entries idx))
               (set idx (+ idx 1))))
         (when (not chosen)
           (error (.. "No fixture response for " key " with method " method)))
         (enqueue {:url url :method method :callback opts.callback :key key} chosen)))

  (set binding.poll
       (fn [max-results]
         (var limit (or max-results (# queue)))
         (when (= limit 0)
           (set limit (# queue)))
         (var results [])
         (var count 0)
         (while (and (< count limit) (> (# queue) 0))
           (local entry (. queue 1))
           (table.remove queue 1)
           (when entry.callback
             (entry.callback entry.response))
           (table.insert results entry.response)
           (set count (+ count 1)))
         results))

  (set binding.cancel
       (fn [id]
         (var removed false)
         (var idx 1)
         (while (<= idx (# queue))
           (local entry (. queue idx))
           (local res entry.response)
           (if (= (. res :id) id)
               (do
                 (table.remove queue idx)
                 (set removed true)
                 (set idx (+ (# queue) 1)))
               (set idx (+ idx 1))))
         removed))

  {:binding binding
   :requests (fn [] requests-log)
   :pending (fn [] queue)
   :reset (fn []
            (set queue [])
            (set requests-log [])
            (set next-id 1))})

(fn install-mock [fixture]
  (local mock (make-mock-http fixture))
  (local original http)
  (set (. package.loaded "http") mock.binding)
  (set http mock.binding)
  {:mock mock
   :restore (fn []
              (set (. package.loaded "http") original)
              (set http original))})

(fn await-response [id deadline-seconds]
  (assert http "await-response requires http binding")
  (local deadline (and deadline-seconds (+ (os.clock) deadline-seconds)))
  (var result nil)
  (while (not result)
    (each [_ res (ipairs (http.poll 0))]
      (when (= res.id id)
        (set result res)))
    (when (and (not result) deadline (> (os.clock) deadline))
      (error (.. "Timed out waiting for http response " id))))
  result)

(fn record-responses! [requests target-path]
  (ensure-http)
  (assert-deps)
  (var captured [])
  (each [_ req (ipairs requests)]
    (local id (http.request {:url req.url
                             :method (or req.method "GET")
                             :headers (or req.headers nil)
                             :timeout-ms (or req.timeout_ms 10000)
                             :connect-timeout-ms (or req.connect_timeout_ms 5000)}))
    (local res (await-response id 30))
    (table.insert captured {:key (or req.key (derive-key req.url))
                            :url req.url
                            :method (or req.method "GET")
                            :status res.status
                            :ok res.ok
                            :headers res.headers
                            :body res.body
                            :error res.error}))
  (local payload {:recorded_at (os.date "!%Y-%m-%dT%H:%M:%SZ")
                  :asset_path target-path
                  :responses captured})
  (write-json! target-path payload)
  payload)

(set http-fixtures.read-json read-json)
(set http-fixtures.write-json! write-json!)
(set http-fixtures.path-from-url path-from-url)
(set http-fixtures.make-mock-http make-mock-http)
(set http-fixtures.install-mock install-mock)
(set http-fixtures.record-responses! record-responses!)

http-fixtures
