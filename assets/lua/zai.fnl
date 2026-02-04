(local json (require :json))
(local HttpCommon (require :http/common))
(local http (require :http))
(local fs (require :fs))
(local appdirs (require :appdirs))
(local logging (require :logging))

(local encode-query HttpCommon.encode-query)
(local normalize-headers HttpCommon.normalize-headers)
(local decode-json HttpCommon.decode-json)

(fn redact-headers [headers]
  (local redacted {})
  (each [k v (pairs (or headers {}))]
    (if (= (string.lower (tostring k)) "authorization")
        (tset redacted k "Bearer ***")
        (tset redacted k v)))
  redacted)

(fn Zai [opts]
  (local options (or opts {}))
  (local http-binding (or options.http http))
  (assert http-binding "ZAI client requires the http binding")
  (assert json "ZAI client requires the json binding")

  (local log-root (and appdirs (appdirs.user-log-dir "space")))
  (local zai-log-dir
    (and log-root
         (if (and fs fs.join-path)
             (fs.join-path log-root "zai")
             (.. log-root "/zai"))))
  (local zai-log-path
    (and zai-log-dir
         (if (and fs fs.join-path)
             (fs.join-path zai-log-dir "requests.jsonl")
             (.. zai-log-dir "/requests.jsonl"))))

  (fn ensure-zai-log-dir []
    (when (and fs fs.create-dirs zai-log-dir)
      (pcall (fn [] (fs.create-dirs zai-log-dir)))))

  (fn append-log [payload]
    (if (not (and zai-log-path json))
        (when logging
          (logging.warn "[zai] logging unavailable; missing log path or json module"))
        (do
          (ensure-zai-log-dir)
          (pcall (fn []
                   (local handle (io.open zai-log-path "a"))
                   (when handle
                     (handle:write (json.dumps payload) "\n")
                     (handle:close)))))))

  (fn now-iso []
    (os.date "!%Y-%m-%dT%H:%M:%SZ"))

  (local api-key (or options.api_key (os.getenv "ZAI_API_KEY")))
  (assert api-key "ZAI API key missing; pass api_key or set ZAI_API_KEY")

  (local base-url (or options.base_url "https://api.z.ai"))
  (local user-agent (or options.user_agent "space-zai/1.0"))
  (local accept-language (or options.accept_language "en-US,en"))
  (local default-timeout-ms (or options.timeout_ms 0))
  (local default-connect-timeout-ms (or options.connect_timeout_ms 0))

  (local default-headers {})
  (tset default-headers "Authorization" (.. "Bearer " api-key))
  (tset default-headers "Content-Type" "application/json")
  (tset default-headers "Accept" "application/json")
  (tset default-headers "Accept-Language" accept-language)

  (fn merge-headers [extra]
    (local merged {})
    (each [k v (pairs default-headers)]
      (tset merged k v))
    (when extra
      (each [k v (pairs extra)]
        (when (not (= v nil))
          (tset merged (tostring k) (tostring v)))))
    merged)

  (fn build-url [path query]
    (.. base-url path (encode-query query)))

  (fn make-result [res]
    (local parsed (decode-json res.body))
    (local headers (normalize-headers res.headers))
    (local ok (and res.ok (< res.status 400)))
    (local message (or (and parsed parsed.error parsed.error.message) res.error res.body))
    {:status res.status
     :headers headers
     :data (or parsed res.body)
     :raw res.body
     :request_id (or (. headers "request-id") (. headers "x-request-id"))
     :id res.id
     :ok ok
     :error (if ok nil message)})

  (fn submit [method path request]
    (local payload (or (and request request.body) nil))
    (local query (or (and request request.query) nil))
    (local extra-headers (or (and request request.headers) nil))
    (local callback (or (and request request.callback)
                        (and request request.on-response)
                        (and request request.on_response)))
    (assert callback "ZAI request requires a callback")
    (local body-str
      (if payload
          (if (= (type payload) :string)
              payload
              (json.dumps payload))
          ""))
    (local req-headers (merge-headers extra-headers))
    (local url (build-url path query))
    (local id
      (http-binding.request {:method method
                             :url url
                             :headers req-headers
                             :body body-str
                             :user-agent user-agent
                             :timeout-ms (or (and request request.timeout_ms) default-timeout-ms)
                             :connect-timeout-ms (or (and request request.connect_timeout_ms) default-connect-timeout-ms)
                             :callback (fn [res]
                                         (append-log {:timestamp (now-iso)
                                                      :event "zai.response"
                                                      :request_id res.id
                                                      :status res.status
                                                      :ok res.ok
                                                      :error res.error
                                                      :headers (redact-headers res.headers)
                                                      :body res.body})
                                         (callback (make-result res)))}))
    (append-log {:timestamp (now-iso)
                 :event "zai.request"
                 :request_id id
                 :method method
                 :url url
                 :headers (redact-headers req-headers)
                 :body body-str
                 :timeout_ms (or (and request request.timeout_ms) default-timeout-ms)
                 :connect_timeout_ms (or (and request request.connect_timeout_ms) default-connect-timeout-ms)
                 :user_agent user-agent})
    id)

  (local client {})

  (set client.create-chat-completion
       (fn [payload opts]
         (submit "POST" "/api/paas/v4/chat/completions"
                 {:body payload
                  :query (or (and opts opts.query) nil)
                  :headers (or (and opts opts.headers) nil)
                  :callback (or (and opts opts.callback) (and opts opts.on-response))
                  :timeout_ms (or (and opts opts.timeout_ms) nil)
                  :connect_timeout_ms (or (and opts opts.connect_timeout_ms) nil)})))

  (set client.raw-request
       (fn [method path opts]
         (submit (string.upper method) path opts)))

  (set client.drop
       (fn []))

  client)

Zai

